const stencils = Dict{String,Any}()


function init_stencils()
    stencildir = joinpath(@__DIR__, "..", "stencils")
    files = readdir(stencildir, join=true)
    filter!(files) do f
        contains(f, "libjl") && return false
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
        elseif startswith(h.symbol, "ffi_")
            dlsym(libffi_handle, Symbol(h.symbol))
        else
            dlsym(libc[], h.symbol)
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
    codeinfo, rettype = only(code_typed(fn, args; optimize))

    # @show codeinfo
    # @show codeinfo.code
    # @show codeinfo.slottypes
    # @show codeinfo.ssavaluetypes
    # @show propertynames(codeinfo)

    nslots = length(codeinfo.slottypes)
    slots = ByteVector(nslots*sizeof(Ptr{UInt64}))
    nssas = length(codeinfo.ssavaluetypes)
    # TODO we use this assumption to save return values into ssa array
    @assert nssas == length(codeinfo.code)
    ssas = ByteVector(nssas*sizeof(Ptr{UInt64}))
    boxes = Any[]
    used_rets = find_used(codeinfo)

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

    nstencils = length(codeinfo.code)
    stencil_starts = zeros(Int64, nstencils)
    code_size = 0
    data_size = 0
    for (i,ex) in enumerate(codeinfo.code)
        if isnothing(ex)
            # FIXME This might cause problems with continuations when we patch with stencil_starts[ic+1]
            # and ic+1 is a nothing node, I think...
            if i > 1
                stencil_starts[i] = stencil_starts[i-1]
            end
            continue
        end
        st, bvec, _ = get_stencil(ex)
        stencil_starts[i] = 1+code_size
        code_size += length(only(st.code.body))
        if !isempty(st.data.body)
            data_size += length(only(st.data.body))
        end
    end
    memory = mmap(Vector{UInt8}, code_size, shared=false, exec=true)
    # memory = mmap(Vector{UInt8}, code_size+data_size, shared=false, exec=true)
    # bvec_code = view(memory, 1:code_size)
    # bvec_data = view(memory, code_size+1:code_size+data_size)
    preserve = Any[]
    for (ic,ex) in enumerate(codeinfo.code)
        emitcode!(memory, stencil_starts, ic, slots, ssas, preserve, used_rets, ex)
    end

    return memory, preserve
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
    elseif isexpr(ex, :new)
        return stencils["jl_new_structv"]
    elseif isexpr(ex, :foreigncall)
        return stencils["jl_foreigncall"]
    else
        TODO("Stencil not implemented yet:", ex)
    end
end
get_stencil(ex::Core.ReturnNode) = stencils["jit_returnnode"]
get_stencil(ex::Core.GotoIfNot)  = stencils["jit_gotoifnot"]
get_stencil(ex::Core.GotoNode)   = stencils["jit_goto"]
get_stencil(ex::Core.PhiNode)    = stencils["jit_phinode"]


# TODO Need to collect the a's which need to be GC.@preserved when their pointers are used.
# - Anything to which we apply pointer_from_objref or pointer needs to be preserved when used.
# - Also slots and ssas need to be kept alive till the function is finished.
# - What about boxed stuff?
function box_arg(a, slots, ssas)
    if a isa Core.Argument
        return slots[UInt64,a.n]
    elseif a isa Core.SSAValue
        return ssas[UInt64,a.id]
    elseif a isa String
        return pointer_from_objref(a)
    elseif a isa Number
        return box(a)
    elseif a isa Type
        return pointer_from_objref(a)
    elseif a isa GlobalRef
        # do it similar to src/interpreter.c:jl_eval_globalref
        p = ccall(:jl_get_globalref_value, Ptr{Cvoid}, (Any,), a)
        if p === C_NULL
            throw(UndefVarError(a.name,a.mod))
        end
        return p
    elseif typeof(a) <: Boxable
        return box(a)
    elseif a isa MethodInstance
        return pointer_from_objref(a)
    else
        TODO(a)
    end
end
function box_args(ex_args::AbstractVector, slots, ssas)
    # TODO Need to cast to Ptr{UInt64} here?
    return Ptr{Cvoid}[ box_arg(a, slots, ssas) for a in ex_args ]
end


# Based on base/compiler/ssair/ir.jl
# JuliaInterpreter.jl implements its own version of scan_ssa_use!,
# not sure why though.
function find_used(ci::CodeInfo)
    used = BitSet()
    for stmt in ci.code
        Core.Compiler.scan_ssa_use!(push!, used, stmt)
    end
    return used
end


# CodeInfo can contain following symbols
# (from https://juliadebug.github.io/JuliaInterpreter.jl/stable/ast/)
# - %2 ... single static assignment (SSA) value
#          see CodeInfo.ssavaluetypes, CodeInfo.ssaflags
# - _2 ... slot variable; either a function argument or a local variable
#          _1 refers to function, _2 to first arg, etc.
#          see CodeInfo.slottypes, CodeInfo.slotnames
emitcode!(memory, stencil_starts, ic, slots::ByteVector, ssas::ByteVector, preserve, used_rets, ex) = TODO(typeof(ex))
emitcode!(memory, stencil_starts, ic, slots::ByteVector, ssas::ByteVector, preserve, used_rets, ex::Nothing) = nothing
function emitcode!(memory, stencil_starts, ic, slots::ByteVector, ssas::ByteVector, preserve, used_rets, ex::Core.ReturnNode)
    st, bvec, _ = stencils["jit_returnnode"]
    retbox = ic in used_rets ? box_arg(ex.val, slots, ssas) : pointer([C_NULL])
    push!(preserve, retbox)
    # TODO Atm _JIT_RET is unused in stencils, so it is optimzed away and we can't patch it
    # patch!(bvec, st.code, "_JIT_RET", retbox)
    copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
end
function emitcode!(memory, stencil_starts, ic, slots::ByteVector, ssas::ByteVector, preserve, used_rets, ex::Core.GotoNode)
    st, bvec, _ = stencils["jit_goto"]
    copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
    patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_CONT", pointer(memory, stencil_starts[ex.label]))
end
function emitcode!(memory, stencil_starts, ic, slots::ByteVector, ssas::ByteVector, preserve, used_rets, ex::Core.GotoIfNot)
    st, bvec, _ = stencils["jit_gotoifnot"]
    copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
    test = ssas[UInt64,ex.cond.id] # TODO Can this also be a slot?
    patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_TEST",  test)
    patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_CONT1", pointer(memory, stencil_starts[ex.dest]))
    patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_CONT2", pointer(memory, stencil_starts[ic+1]))
end
function emitcode!(memory, stencil_starts, ic, slots::ByteVector, ssas::ByteVector, preserve, used_rets, ex::Core.PhiNode)
    st, bvec, _ = stencils["jit_phinode"]
    copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
    nedges = length(ex.edges)
    append!(preserve, ex.edges)
    vals_boxes = box_args(ex.values, slots, ssas)
    append!(preserve, vals_boxes)
    retbox = [ic in used_rets ? ssas[UInt64,ic] : C_NULL]
    push!(preserve, retbox)
    patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_NEDGES",  nedges)
    patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_EDGES",   pointer(ex.edges))
    patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_VALS",    pointer(vals_boxes))
    patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_RET",     pointer(retbox))
    patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_THIS_IP", ic)
    patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_CONT",    pointer(memory, stencil_starts[ic+1]))
end
function emitcode!(memory, stencil_starts, ic, slots::ByteVector, ssas::ByteVector, preserve, used_rets, ex::Expr)
    if isexpr(ex, :call)
        g = ex.args[1]
        @assert g isa GlobalRef
        fn = unwrap(g)
        if fn isa Core.IntrinsicFunction
            ex_args = @view ex.args[2:end]
            nargs = length(ex_args)
            boxes = box_args(ex_args, slots, ssas)
            append!(preserve, boxes)
            retbox = [ic in used_rets ? ssas[UInt64,ic] : C_NULL]
            push!(preserve, retbox)
            name = string("jl_", Symbol(fn))
            st, bvec, bvec2 = get(stencils, name) do
                error("don't know how to handle intrinsic $name")
            end
            @assert length(bvec2) == 0
            copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
            for n in 1:nargs
                # TODO I think one of the problems is that one
                # box argument here is a literal and the other one a dynamic value.
                # patch!(bvec, st.code, "_JIT_A$n", pointer(boxes, n))
                patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_A$n", boxes[n])
            end
            patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_RET",  pointer(retbox))
            patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_CONT", pointer(memory, stencil_starts[ic+1]))
        elseif fn isa Function
            @assert iscallable(fn)
            fn_ptr = pointer_from_function(fn)
            ex_args = @view ex.args[2:end]
            nargs = length(ex_args)
            boxes = box_args(ex_args, slots, ssas)
            append!(preserve, boxes)
            retbox = [ic in used_rets ? ssas[UInt64,ic] : C_NULL]
            push!(preserve, retbox)
            st, bvec, _ = stencils["jit_call"]
            copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
            patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_NARGS", nargs)
            patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_ARGS",  pointer(boxes))
            patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_FN",    pointer_from_function(fn))
            patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_RET",   pointer(retbox))
            patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_CONT",  pointer(memory, stencil_starts[ic+1]))
            TODO("still used?")
        else
            TODO(fn)
        end
    elseif isexpr(ex, :invoke)
        mi, g = ex.args[1], ex.args[2]
        @assert mi isa MethodInstance
        @assert g isa GlobalRef
        ex_args = ex.args
        boxes = box_args(ex_args, slots, ssas)
        append!(preserve, boxes)
        nargs = length(boxes)
        retbox = [ic in used_rets ? ssas[UInt64,ic] : C_NULL]
        push!(preserve, retbox)
        st, bvec, bvec2 = stencils["jl_invoke"]
        copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_ARGS",  pointer(boxes))
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_NARGS", nargs)
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_RET",   pointer(retbox))
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_CONT",  pointer(memory, stencil_starts[ic+1]))
    elseif isexpr(ex, :new)
        ex_args = ex.args
        boxes = box_args(ex_args, slots, ssas)
        append!(preserve, boxes)
        nargs = length(boxes)
        retbox = [ic in used_rets ? ssas[UInt64,ic] : C_NULL]
        push!(preserve, retbox)
        st, bvec, bvec2 = stencils["jl_new_structv"]
        @assert length(bvec2) == 0
        copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_ARGS",  pointer(boxes))
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_NARGS", nargs)
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_RET",   pointer(retbox))
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_CONT",  pointer(memory, stencil_starts[ic+1]))
    elseif isexpr(ex, :foreigncall)
        fname, libname = ex.args[1].args[2].value, unwrap(ex.args[1].args[3].args[2])
        rettype = ex.args[2]
        argtypes = ex.args[3]
        nreq = ex.args[4]
        @assert nreq == 0
        conv = ex.args[5]
        @assert conv === QuoteNode(:ccall)
        args = ex.args[6:5+length(ex.args[3])]
        gc_roots = ex.args[6+length(ex.args[3])+1:end]
        @assert length(gc_roots) == 0
        boxes = box_args(args, slots, ssas)
        append!(preserve, boxes)
        nargs = length(boxes)
        retbox = [ic in used_rets ? ssas[UInt64,ic] : C_NULL]
        push!(preserve, retbox)
        cif = Ffi_cif(rettype, argtypes)
        st, bvec, bvec2 = stencils["jl_foreigncall"]
        @assert length(bvec2) == 0
        handle = dlopen(libname[])
        fptr = dlsym(handle, fname)
        copyto!(memory, stencil_starts[ic], bvec, 1, length(bvec))
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_CIF",  pointer(cif))
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_F",    fptr)
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_ARGS", pointer(boxes))
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_RET",  pointer(retbox))
        patch!(memory, stencil_starts[ic]-1, st.code, "_JIT_CONT", pointer(memory, stencil_starts[ic+1]))
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
    # TODO src/disasm.cpp also exports exports a disassembler which is based on llvm-mc
    # jl_value_t *jl_dump_fptr_asm_impl(uint64_t fptr, char emit_mc, const char* asm_variant, const char *debuginfo, char binary)
    # maybe we can repurpose that to avoid the extra llvm-mc dependence?
    cmd = `llvm-mc --disassemble --triple=$triple --output-asm-variant=$variant`
    pipe = pipeline(cmd, stdout=out, stderr=err)
    open(pipe, "w", stdin) do p
        println(p, codestr)
    end
    close(out.in)
    close(err.in)
    str_out = read(out, String)
    str_err = read(err, String)
    # TODO print_native outputs a place holder expression like
    #   add     byte ptr [rax], al
    # whenever there are just zeros. Is that a bug?
    print_native(io, str_out)
end
