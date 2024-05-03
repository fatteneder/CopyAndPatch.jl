const stencils = Dict{String,Any}()


function init_stencils()
    stencildir = joinpath(@__DIR__, "..", "stencils")
    files = readdir(stencildir, join=true)
    filter!(files) do f
        endswith(f, ".json")
    end
    empty!(stencils)
    for f in files
        try
            s = StencilGroup(f)
            bvec = ByteVector(UInt8.(only(s.code.body)))
            bvec_data = if !isempty(s.data.body)
                ByteVector(UInt8.(only(s.data.body)))
            else
                ByteVector(0)
            end
            patch_default_deps!(bvec, bvec_data, s)
            name = first(splitext(basename(f)))
            stencils[name] = (s,bvec,bvec_data)
        catch e
            println("Failure when processing $f")
            rethrow(e)
        end
    end
    return
end


function patch_default_deps!(bvec::ByteVector, bvec_data::ByteVector, s::StencilGroup)
    holes = s.code.relocations
    for h in holes
        # TODO Is there a list of intrinsics which I can skip here?
        # Shall we use _JIT_ENTRY here?
        startswith(h.symbol, "_JIT_") && continue
        ptr = if startswith(h.symbol, "jl_")
            p = dlsym(libjulia[], h.symbol, throw_error=false)
            if isnothing(p)
                p = dlsym(libjuliainternal[], h.symbol, throw_error=false)
                if isnothing(p)
                    @warn "failed to find $(h.symbol) symbol"
                    continue
                end
            end
            p
        elseif startswith(h.symbol, ".rodata")
            @assert h.addend+1 < length(bvec_data)
            pointer(bvec_data.d, h.addend+1)
        else
            dlsym(libc[], h.symbol)#, throw_error=false)
            # @assert !isnothing(p)
            # p
        end
        bvec[h.offset+1] = ptr
    end
end


function jit(@nospecialize(fn::Function), @nospecialize(args))

    # this here does the linking of all non-copy-patched parts
    # so that the stencils can be used as they already below
    # this includes setting up the data part too, which is important
    # because below we separate code and data parts in memory
    init_stencils()

    optimize = true
    code = code_typed(fn, args; optimize)
    @assert length(code) == 1
    codeinfo = code[1].first
    ret = code[1].second

    @show codeinfo
    # @show codeinfo.slottypes
    # @show codeinfo.ssavaluetypes
    # @show propertynames(codeinfo)

    nslots = length(codeinfo.slottypes)
    slots = ByteVector(nslots*sizeof(Ptr{UInt64}))
    nssas = length(codeinfo.ssavaluetypes)
    ssas = ByteVector(nssas*sizeof(Ptr{UInt64}))
    boxes = Any[]

    # init ssas and slots
    for i = 1:nslots
        T = codeinfo.slottypes[i]
        T isa Core.Const && continue
        if T <: Number
            # the rand(T) version can trigger random 'LoadError: sext_int: value is not a primitive type error'
            # z = T(T === Bool ? true : rand(T))
            z = T(T === Bool ? true : i)
            b = box(z)
            slots[UInt64,i] = b
        elseif T <: String
            str = "Slot$i"
            b = pointer_from_objref(str)
            slots[UInt64,i] = b
            push!(boxes, str)
        end
    end
    for i = 1:nssas
        T = codeinfo.ssavaluetypes[i]
        if T <: Number
            z = T(T === Bool ? true : i)
            b = box(z)
            ssas[UInt64,i] = b
        elseif T <: String
            str = "SSA$i"
            b = pointer_from_objref(str)
            ssas[UInt64,i] = b
            push!(boxes, str)
        end
    end

    @show codeinfo.code
    nstencils = length(codeinfo.code)
    stencil_starts = zeros(Int64, nstencils)
    code_size = 0
    data_size = 0
    for (i,ex) in enumerate(codeinfo.code)
        st, bvec, _ = get_stencil(ex)
        stencil_starts[i] = 1+code_size
        code_size += length(only(st.code.body))
        if !isempty(st.data.body)
            data_size += length(only(st.data.body))
        end
    end
    memory = mmap(Vector{UInt8}, code_size+data_size, shared=false, exec=true)

    for (ic,ex) in enumerate(codeinfo.code)
        emitcode!(ic, memory, stencil_starts, slots, ssas, boxes, ex)
    end

    return memory
end


function get_stencil(ex)
    if isexpr(ex, :call)
        g = ex.args[1]
        @assert g isa GlobalRef
        fn = unwrap(g)
        if fn isa Core.IntrinsicFunction
            name = string("jl_", Symbol(fn))
            return get(stencils, name) do
                error("don't know how to handle intrinsic $name")
            end
        elseif fn isa Function
            return stencils["jl_call"]
        else
            TODO(fn)
        end
    elseif isexpr(ex, :invoke)
        return stencils["jl_invoke"]
    else
        TODO("Stencil not implemented yet:", ex)
    end
end
get_stencil(ex::Core.ReturnNode) = stencils["jit_end"]
get_stencil(ex::Core.GotoIfNot)  = stencils["jit_gotoifnot"]


# TODO Maybe dispatch on fn
function box_args(ex_args, slots, ssas, fn)
    boxes = Ptr{UInt64}[]
    for a in ex_args
        if a isa Core.Argument
            push!(boxes,
                  fn isa Core.IntrinsicFunction ? slots[UInt64,a.n] : pointer(slots, UInt64, a.n))
        elseif a isa Core.SSAValue
            push!(boxes,
                  fn isa Core.IntrinsicFunction ? ssas[UInt64,a.id] : pointer(ssas, UInt64, a.id))
        elseif a isa String
            push!(boxes, pointer_from_objref(a))
        elseif a isa Number
            b = box(a)
            push!(boxes, b)
            # push!(bxs, b) # TODO Was this necessary before?
        elseif a isa Type
            push!(boxes, pointer_from_objref(a))
        else
            push!(boxes, box(a))
        end
    end
    return boxes
end

# Given a CodeInfo ci object, use the following to figure out which
# ssa values are actually used in the body.
# ```
# used = BitSet()
# for stmt in ci.code
#   Core.Compiler.scan_ssa_use!(push!, used, stmt)
# end
# ```


# CodeInfo can contain following symbols
# (from https://juliadebug.github.io/JuliaInterpreter.jl/stable/ast/)
# - %2 ... single static assignment (SSA) value
#          see CodeInfo.ssavaluetypes, CodeInfo.ssaflags
# - _2 ... slot variable; either a function argument or a local variable
#          _1 refers to function, _2 to first arg, etc.
#          see CodeInfo.slottypes, CodeInfo.slotnames
emitcode!(ic, memory, stencil_starts, slots::ByteVector, ssas::ByteVector, boxes, ex) = TODO(typeof(ex))
function emitcode!(ic, memory, stencil_starts, slots::ByteVector, ssas::ByteVector, boxes, ex::Core.ReturnNode)
    _, bvec, _ = stencils["jit_end"]
    # patch!(bvec, st.code, "_JIT_RET", ssas[end])
    copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
end
function emitcode!(ic, memory, stencil_starts, slots::ByteVector, ssas::ByteVector, boxes, ex::Core.GotoIfNot)
    st, bvec, _ = stencils["jl_gotoifnot"]
    TODO()
end
function emitcode!(ic, memory, stencil_starts, slots::ByteVector, ssas::ByteVector, bxs, ex::Expr)
    if isexpr(ex, :call)
        g = ex.args[1]
        @assert g isa GlobalRef
        fn = unwrap(g)
        if fn isa Core.IntrinsicFunction
            ex_args = @view ex.args[2:end]
            nargs = length(ex_args)
            boxes = box_args(ex_args, slots, ssas, fn)
            retbox = Ref{Ptr{Cvoid}}(C_NULL)
            append!(bxs, boxes)
            name = string("jl_", Symbol(fn))
            st, bvec, bvec2 = get(stencils, name) do
                error("don't know how to handle intrinsic $name")
            end
            @assert length(bvec2) == 0
            for n in 1:nargs
                # TODO I think one of the problems is that one
                # box argument here is a literal and the other one a dynamic value.
                # patch!(bvec, st.code, "_JIT_A$n", pointer(boxes, n))
                patch!(bvec, st.code, "_JIT_A$n", boxes[n])
            end
            patch!(bvec, st.code, "_JIT_RET", unsafe_convert(Ptr{Cvoid}, retbox))
            patch!(bvec, st.code, "_JIT_CONT", pointer(memory, stencil_starts[ic+1]))
            copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
        elseif fn isa Function
            @assert iscallable(fn)
            fn_ptr = pointer_from_function(fn)
            ex_args = @view ex.args[2:end]
            nargs = length(ex_args)
            boxes = box_args(ex_args, slots, ssas, fn)
            append!(bxs, boxes)
            retbox = Ref{Ptr{Cvoid}}(C_NULL)
            st, bvec, _ = stencils["jit_call"]
            patch!(bvec, st.code, "_JIT_NARGS", nargs)
            patch!(bvec, st.code, "_JIT_ARGS",  pointer(boxes))
            patch!(bvec, st.code, "_JIT_FN",    pointer_from_function(fn))
            patch!(bvec, st.code, "_JIT_RET",   unsafe_convert(Ptr{Cvoid}, retbox))
            patch!(bvec, st.code, "_JIT_CONT",  pointer(memory, stencil_starts[ic+1]))
            copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
            TODO("still used?")
        else
            TODO(fn)
        end
    elseif isexpr(ex, :invoke)
        mi, g = ex.args[1], ex.args[2]
        @assert mi isa MethodInstance
        @assert g isa GlobalRef
        fn = unwrap(g)
        ex_args = length(ex.args) > 2 ? ex.args[3:end] : []
        # TODO Need to figure out how to connect the call arguments with the slots!
        boxes = box_args(ex_args, slots, ssas, fn)
        nargs = length(boxes)
        append!(bxs, boxes)
        retbox = Ref{Ptr{Cvoid}}(C_NULL)
        st, bvec, bvec2 = stencils["jl_invoke"]
        @assert length(bvec2) == 0
        patch!(bvec, st.code, "_JIT_MI",    pointer_from_objref(mi))
        patch!(bvec, st.code, "_JIT_NARGS", nargs)
        patch!(bvec, st.code, "_JIT_ARGS",  pointer(boxes))
        patch!(bvec, st.code, "_JIT_FN",    pointer_from_function(fn))
        patch!(bvec, st.code, "_JIT_RET",   unsafe_convert(Ptr{Cvoid}, retbox))
        patch!(bvec, st.code, "_JIT_CONT",  pointer(memory, stencil_starts[ic+1]))
        copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
    else
        TODO(ex.head)
    end
end


const IntrinsicDispatchType = Union{Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64,Float16,Float32,Float64}


# code_native(code::AbstractVector{<:AbstractVector}; syntax=:intel) = foreach(code_native(c; syntax) for c in code)
code_native(code::AbstractVector; syntax=:intel) = code_native(UInt8.(code); syntax)
code_native(code::Vector{UInt8}; syntax=:intel) = code_native(stdout, code; syntax)
function code_native(io::IO, code::Vector{UInt8}; syntax=:intel)
    if syntax === :intel
        variant = 1
    elseif syntax === :att
        variant = 0
    else
        throw(ArgumentError("'syntax' must be either :intel or :att"))
    end
    triple = lowercase(string(Sys.KERNEL, '-', Sys.MACHINE))
    codestr = join(Iterators.map(string, code), ' ')
    out, err = Pipe(), Pipe()
    cmd = `llvm-mc --disassemble --triple=$triple --output-asm-variant=$variant`
    pipe = pipeline(cmd, stdout=out, stderr=err)
    open(pipe, "w", stdin) do p
        println(p, codestr)
    end
    close(out.in)
    close(err.in)
    str_out = read(out, String)
    str_err = read(err, String)
    print_native(io, str_out)
end
