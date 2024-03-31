const stencils = Dict{String,Any}()


function init_stencils()

    stencildir = joinpath(@__DIR__, "..", "stencils")
    files = readdir(stencildir, join=true)
    filter!(files) do f
        endswith(f, ".json")
    end

    empty!(stencils)
    for f in files
        s = StencilGroup(f)
        bvec = ByteVector(UInt8.(s.code.body[1]))
        bvec_data = if !isempty(s.data.body)
            ByteVector(UInt8.(s.data.body[1]))
        else
            ByteVector(0)
        end
        patch_default_deps!(bvec, bvec_data, s)

        # mmap stencils to make them executable
        buf_bvec      = mmap(Vector{UInt8}, length(bvec), shared=false, exec=true)
        buf_bvec_data = mmap(Vector{UInt8}, length(bvec_data), shared=false, exec=true)
        copy!(buf_bvec, bvec)
        copy!(buf_bvec_data, bvec_data)

        name = first(splitext(basename(f)))
        stencils[name] = (s,buf_bvec,buf_bvec_data)
    end

    return
end


function patch_default_deps!(bvec::ByteVector, bvec_data::ByteVector, s::StencilGroup)
    holes = s.code.relocations
    for h in holes
        # TODO Is there a list of intrinsics which I can skip here?
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


const Stack = Vector{Ptr{UInt64}}


function jit(@nospecialize(fn::Function), @nospecialize(args))

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

    stack = Stack()
    nslots = length(codeinfo.slottypes)
    slots = ByteVector(nslots*sizeof(Ptr{UInt64}))
    nssas = length(codeinfo.ssavaluetypes)
    ssas = ByteVector(nssas*sizeof(Ptr{UInt64}))

    # init ssas and slots
    for i = 1:nslots
        T = codeinfo.slottypes[i]
        T isa Core.Const && continue
        T <: Number || continue
        z = T(0)
        b = box(z)
        slots[UInt64,i] = b
    end
    for i = 1:nssas
        T = codeinfo.ssavaluetypes[i]
        T <: Number || continue
        z = T(0)
        b = box(z)
        ssas[UInt64,i] = b
    end

    boxes = Any[]
    for (i,ex) in Iterators.reverse(enumerate(codeinfo.code))
        emitcode!(stack, slots, ssas, boxes, ex, codeinfo.ssavaluetypes[i])
    end

    return stack, slots, ssas, boxes
end


# CodeInfo can contain following symbols
# (from https://juliadebug.github.io/JuliaInterpreter.jl/stable/ast/)
# - %2 ... single static assignment (SSA) value
#          see CodeInfo.ssavaluetypes, CodeInfo.ssaflags
# - _2 ... slot variable; either a function argument or a local variable
#          _1 refers to function, _2 to first arg, etc.
#          see CodeInfo.slottypes, CodeInfo.slotnames
#
# Our calling convention:
# stack[end-3] = continuation_ptr
# stack[end-2] = fn_ptr
# stack[end-1] = pointer(boxes.(args))
# stack[end]   = nargs
#
# TODO Does the jit code need to handle argstack?
emitcode!(stack::Stack, slots::ByteVector, ssas::ByteVector, boxes, ex, rettype) = TODO(typeof(ex))
function emitcode!(stack::Stack, slots::ByteVector, ssas::ByteVector, boxes, ex::Core.ReturnNode, rettype)
    _, bvec, _ = stencils["jit_end"]
    push!(stack, pointer(bvec))
end
function emitcode!(stack::Stack, slots::ByteVector, ssas::ByteVector, bxs, ex::Expr, rettype)
    if isexpr(ex, :call)
        g = ex.args[1]
        @assert g isa GlobalRef
        fn = unwrap(g)
        if fn isa Core.IntrinsicFunction
            ex_args = @view ex.args[2:end]
            nargs = length(ex_args)
            boxes = Ptr{UInt64}[]
            name = string(g.name)
            for a in ex_args
                @show ex, a
                if a isa Core.Argument || a isa Core.SSAValue
                    p = if a isa Core.Argument
                        slots[UInt64, a.n]
                    elseif a isa Core.SSAValue
                        @show a
                        ssas[UInt64, a.id]
                    end
                    push!(boxes, p)
                elseif a isa Number
                    b = box(a)
                    push!(boxes, b)
                    push!(bxs, b)
                elseif a isa Type
                    push!(boxes, pointer_from_objref(a))
                else
                    TODO(a)
                end
            end
            retbox = Ref{Ptr{Cvoid}}(C_NULL)
            push!(stack, unsafe_convert(Ptr{Cvoid}, retbox))
            append!(bxs, boxes) # preseve boxes
            append!(stack, reverse(boxes))
            name = string("jl_", Symbol(fn))
            _, intrinsic, _ = get(stencils, name) do
                error("don't know how to handle intrinsic $name")
            end
            push!(stack, pointer(intrinsic))
        elseif fn isa Function
            @assert iscallable(fn)
            fn_ptr = pointer_from_function(fn)
            push!(stack, fn_ptr)
            ex_args = @view ex.args[2:end]
            nargs = length(ex_args)
            boxes = Ptr{UInt64}[]
            for a in ex_args
                if a isa Core.Argument
                    @assert a.n > 1
                    push!(boxes, pointer(slots, UInt64, a.n))
                elseif a isa Core.SSAValue
                    push!(boxes, pointer(ssas, UInt64, a.id))
                else
                    push!(boxes, box(a))
                end
            end
            append!(bxs, boxes)
            push!(stack, pointer(boxes))
            push!(stack, UInt64(nargs))
            _, bvec, _ = stencils["jit_call"]
            push!(stack, pointer(bvec))
        else
            TODO(fn)
        end
    else
        TODO(ex.head)
    end
end


const IntrinsicDispatchType = Union{Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64,Float16,Float32,Float64}
name_stack_jl_box(@nospecialize(t::Type{T})) where T<:IntrinsicDispatchType = string("stack_jl_box_", lowercase(string(Symbol(t))))


function emitcode_box!(stack::Stack, p::Ptr, @nospecialize(type::Type{T})) where T<:IntrinsicDispatchType

    retbox = Ref{Ptr{Cvoid}}(C_NULL)
    name = name_stack_jl_box(type)
    _, bvec, _ = stencils[name]

    # arg
    push!(stack, p)
    # retvalue
    push!(stack, unsafe_convert(Ptr{Cvoid}, retbox))
    # continuation
    push!(stack, pointer(bvec))

    return bvec, retbox
end


code_native(code::Vector{UInt8};syntax=:intel) = code_native(stdout, code; syntax)
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
