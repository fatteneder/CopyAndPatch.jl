const stencils = Dict{String,Any}()
const MAGICNR = 0x0070605040302010


function init_stencils()
    stencildir = joinpath(@__DIR__, "..", "stencils", "bin")
    files = readdir(stencildir, join=true)
    filter!(files) do f
        endswith(f, ".json")
    end
    empty!(stencils)
    for f in files
        try
            s = StencilGroup(f)
            bvec = ByteVector(UInt8.(only(s.code.body)))
            bvecs_data = if !isempty(s.data.body)
                [ ByteVector(UInt8.(b)) for b in s.data.body ]
            else
                [ ByteVector(0) ]
            end
            patch_default_deps!(bvec, bvecs_data, s)
            for h in s.code.relocations
                @assert h.kind == "R_X86_64_64"
                bvec[h.offset+1] = MAGICNR
            end
            name = first(splitext(basename(f)))
            stencils[name] = (s,bvec,bvecs_data)
        catch e
            println("Failure when processing $f")
            rethrow(e)
        end
    end
    return
end


function patch_default_deps!(bvec::ByteVector, bvecs_data::Vector{ByteVector}, s::StencilGroup)
    holes = s.code.relocations
    patched = Hole[]
    for h in holes
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
        elseif startswith(h.symbol, "jlh_")
            dlsym(libjuliahelpers[], h.symbol)
        elseif startswith(h.symbol, ".rodata")
            idx = get(s.data.symbols, h.symbol) do
                error("can't locate symbol $(h.symbol) in data section")
            end
            bvec_data = bvecs_data[idx+1]
            @assert h.addend+1 < length(bvec_data)
            pointer(bvec_data.d, h.addend+1)
        elseif startswith(h.symbol, "ffi_")
            dlsym(libffi_handle, Symbol(h.symbol))
        else
            dlsym(libc[], h.symbol)
        end
        bvec[h.offset+1] = ptr
        push!(patched, h)
    end
    filter!(holes) do h
        !(h in patched)
    end
end


function jit(@nospecialize(fn::Function), @nospecialize(argtypes::Tuple))
    init_stencils() # this here does the linking of all non-copy-patched parts

    optimize = true
    codeinfo, rettype = only(code_typed(fn, argtypes; optimize))
    # @show codeinfo
    nslots = length(codeinfo.slotnames)
    nssas = length(codeinfo.ssavaluetypes)
    nstencils = length(codeinfo.code)

    stencil_starts = zeros(Int64, nstencils)
    code_size, data_size = 0, 0
    for (i,ex) in enumerate(codeinfo.code)
        st, bvec, _ = get_stencil(ex)
        stencil_starts[i] = 1+code_size
        code_size += length(only(st.code.body))
        data_size += sum(length(b) for b in st.code.body)
    end

    mc = MachineCode(code_size, fn, rettype, argtypes)
    mc.stencil_starts = stencil_starts
    mc.codeinfo = codeinfo
    @assert nssas == length(codeinfo.code)
    resize!(mc.slots, nslots)
    resize!(mc.ssas, nssas)

    for (ip,ex) in enumerate(codeinfo.code)
        emitcode!(mc, ip, ex)
    end
    return mc
end


function get_stencil_name(ex)
    if isexpr(ex, :call)
        g = ex.args[1]
        fn = g isa GlobalRef ? unwrap(g) : g
        if fn isa Core.IntrinsicFunction
            return string("jl_", Symbol(fn))
        else
            return "ast_call"
        end
    elseif isexpr(ex, :invoke)
        return "ast_invoke"
    elseif isexpr(ex, :new)
        return "ast_new"
    elseif isexpr(ex, :foreigncall)
        return "ast_foreigncall"
    elseif isexpr(ex, :boundscheck)
        return "ast_boundscheck"
    elseif isexpr(ex, :leave)
        return "ast_leave"
    elseif isexpr(ex, :pop_exception)
        return "ast_pop_exception"
    elseif isexpr(ex, :the_exception)
        return "ast_the_exception"
    else
        TODO("Stencil not implemented yet:", ex)
    end
end
get_stencil_name(ex::Core.EnterNode)   = "ast_enternode"
get_stencil_name(ex::Core.GlobalRef)   = "ast_assign"
get_stencil_name(ex::Core.GotoIfNot)   = "ast_gotoifnot"
get_stencil_name(ex::Core.GotoNode)    = "ast_goto"
get_stencil_name(ex::Core.PhiNode)     = "ast_phinode"
get_stencil_name(ex::Core.PhiCNode)    = "ast_phicnode"
get_stencil_name(ex::Core.PiNode)      = "ast_pinode"
get_stencil_name(ex::Core.ReturnNode)  = "ast_returnnode"
get_stencil_name(ex::Core.UpsilonNode) = "ast_upsilonnode"
get_stencil_name(ex::Nothing)          = "ast_goto"

function get_stencil(ex)
    name = get_stencil_name(ex)
    if !haskey(stencils, name)
        error("no stencil '$name' found for expression $ex")
    end
    return stencils[name]
end


# TODO About box: From https://docs.julialang.org/en/v1/devdocs/object/
#   > A value may be stored "unboxed" in many circumstances
#     (just the data, without the metadata, and possibly not even stored but
#     just kept in registers), so it is unsafe to assume that the address of
#     a box is a unique identifier.
#     ...
#   > Note that modification of a jl_value_t pointer in memory is permitted
#     only if the object is mutable. Otherwise, modification of the value may
#     corrupt the program and the result will be undefined.
# TODO https://docs.julialang.org/en/v1/manual/embedding/#Memory-Management
#   > f the variable is immutable, then it needs to be wrapped in an equivalent mutable
#     container or, preferably, in a RefValue{Any} before it is pushed to IdDict.
#     ...
# const refs = IdDict()
function box_arg(@nospecialize(a), mc)
    slots, ssas, static_prms = mc.slots, mc.ssas, mc.static_prms
    if a isa Core.Argument
        return pointer(slots, a.n)
    elseif a isa Core.SSAValue
        return pointer(ssas, a.id)
    else
        # r = Base.RefValue{Any}(a)
        # refs[r] = r
        if a isa Boxable
            push!(static_prms, [box(a)])
        elseif a isa Nothing
            push!(static_prms, [value_pointer(nothing)])
        elseif a isa QuoteNode
            push!(static_prms, [value_pointer(a.value)])
        elseif a isa Tuple
            push!(static_prms, [value_pointer(a)])
        elseif a isa GlobalRef
            # do it similar to src/interpreter.c:jl_eval_globalref
            p = @ccall jl_get_globalref_value(a::Any)::Ptr{Cvoid}
            p === C_NULL && throw(UndefVarError(a.name,a.mod))
            push!(static_prms, [p])
        elseif a isa Core.Builtin
            push!(static_prms, [value_pointer(a)])
        elseif isbits(a)
            push!(static_prms, [value_pointer(a)])
        else
            push!(static_prms, [pointer_from_objref(a)])
        end
        return pointer(static_prms[end])
    end
end
function box_args(ex_args::AbstractVector, mc::MachineCode)
    return Ptr{Any}[ box_arg(a, mc) for a in ex_args ] # =^= jl_value_t ***
end


# CodeInfo can contain following symbols
# (from https://juliadebug.github.io/JuliaInterpreter.jl/stable/ast/)
# - %2 ... single static assignment (SSA) value
#          see CodeInfo.ssavaluetypes, CodeInfo.ssaflags
# - _2 ... slot variable; either a function argument or a local variable
#          _1 refers to function, _2 to first arg, etc.
#          see CodeInfo.slottypes, CodeInfo.slotnames
emitcode!(mc, ip, ex) = TODO(typeof(ex))
function emitcode!(mc, ip, ex::Nothing)
    st, bvec, _ = get_stencil(ex)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",   Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
end
function emitcode!(mc, ip, ex::GlobalRef)
    st, bvec, _ = get_stencil(ex)
    val = box_arg(ex, mc)
    ret = pointer(mc.ssas, ip)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",   Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",  ret)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_VAL",  val)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
end
function emitcode!(mc, ip, ex::Core.EnterNode)
    st, bvec, _ = get_stencil(ex)
    new_scope = isdefined(ex, :scope) ? box_arg(ex.scope, mc) : C_NULL
    ret = pointer(mc.ssas, ip)
    catch_ip = ex.catch_dest
    leave_ip = catch_ip-1
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",         Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NEW_SCOPE",  new_scope)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",        ret)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_EXC_THROWN", pointer_from_objref(mc.exc_thrown))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CALL", pointer(mc.buf, mc.stencil_starts[ip+1]))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT_LEAVE",
                                                    pointer(mc.buf, mc.stencil_starts[leave_ip]))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT_CATCH",
                                                    pointer(mc.buf, mc.stencil_starts[catch_ip]))
end
function emitcode!(mc, ip, ex::Core.ReturnNode)
    # TODO :unreachable nodes are also of type Core.ReturnNode. Anything to do here?
    st, bvec, _ = get_stencil(ex)
    val = isdefined(ex,:val) ? box_arg(ex.val, mc) : C_NULL
    ret = pointer(mc.ssas, ip)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",  Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET", ret)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_VAL", val)
end
function emitcode!(mc, ip, ex::Core.GotoNode)
    st, bvec, _ = get_stencil(ex)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",   Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ex.label]))
end
function emitcode!(mc, ip, ex::Core.GotoIfNot)
    st, bvec, _ = get_stencil(ex)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    test = pointer(mc.ssas, ex.cond.id) # TODO Can this also be a slot?
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",    Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_TEST",  test)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT1", pointer(mc.buf, mc.stencil_starts[ex.dest]))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT2", pointer(mc.buf, mc.stencil_starts[ip+1]))
end
function emitcode!(mc, ip, ex::Core.PhiNode)
    st, bvec, _ = get_stencil(ex)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    nedges = length(ex.edges)
    vals_boxes = box_args(ex.values, mc)
    push!(mc.gc_roots, vals_boxes)
    n = length(mc.codeinfo.code)
    local nphis
    if ip+1 >= n
        nphis = 1
    else
        nphis = findfirst(mc.codeinfo.code[ip+1:end]) do e
            if e isa Expr || e isa Core.ReturnNode || e isa Core.GotoIfNot ||
                e isa Core.GotoNode || e isa Core.PhiCNode || e isa Core.UpsilonNode ||
                e isa Core.SSAValue
                return true
            end
            if !(e isa Core.PhiNode)
                TODO("encountered $e in a phi block")
            end
            return false
        end
        if isnothing(nphis)
            nphis = n-ip+1
        end
    end
    ip_blockend = ip+nphis-1
    retbox = pointer(mc.ssas, ip)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_EDGES_FROM",  pointer(ex.edges))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_PHIOFFSET",   pointer_from_objref(mc.phioffset))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",          Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP_BLOCKEND", Cint(ip_blockend))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NEDGES",      nedges)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",         retbox)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_VALS",        pointer(vals_boxes))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT",        pointer(mc.buf, mc.stencil_starts[ip+1]))
end
function emitcode!(mc, ip, ex::Core.PhiCNode)
    st, bvec, _ = get_stencil(ex)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",   Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
end
function emitcode!(mc, ip, ex::Core.PiNode)
    # https://docs.julialang.org/en/v1/devdocs/ssair/#Phi-nodes-and-Pi-nodes
    # PiNodes are ignored in the interpreter, so ours also only copy values into ssas[ip]
    st, bvec, _ = get_stencil(ex)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    val = box_arg(ex.val, mc)
    ret = pointer(mc.ssas, ip)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",   Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",  ret)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_VAL",  val)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
end
function emitcode!(mc, ip, ex::Core.UpsilonNode)
    st, bvec, _ = get_stencil(ex)
    # jl_get_nth_field_checked identifiese NULLs as undefined
    val = isdefined(ex, :val) ? box_arg(ex.val, mc) : box(C_NULL)
    ssa_ip = Core.SSAValue(ip)
    ret_ip = something(findfirst(mc.codeinfo.code[ip+1:end]) do e
        e isa Core.PhiCNode && ssa_ip in e.values
    end) + ip
    ret = pointer(mc.ssas, ret_ip)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",   Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",  ret)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_VAL",  val)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
end
function emitcode!(mc, ip, ex::Expr)
    st, bvec, _ = get_stencil(ex)
    if isexpr(ex, :call)
        g = ex.args[1]
        fn = g isa GlobalRef ? unwrap(g) : g
        if fn isa Core.IntrinsicFunction
            ex_args = @view ex.args[2:end]
            nargs = length(ex_args)
            boxes = box_args(ex_args, mc)
            push!(mc.gc_roots, boxes)
            retbox = pointer(mc.ssas, ip)
            name = string("jl_", Symbol(fn))
            st, bvec, _ = get(stencils, name) do
                error("don't know how to handle intrinsic $name")
            end
            copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
            for n in 1:nargs
                patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_A$n", boxes[n])
            end
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",  retbox)
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
        elseif iscallable(fn)
            nargs = length(ex.args)
            boxes = box_args(ex.args, mc)
            push!(mc.gc_roots, boxes)
            retbox = pointer(mc.ssas, ip)
            copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_ARGS",    pointer(boxes))
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",      Cint(ip))
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS",   nargs)
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",     retbox)
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT",    pointer(mc.buf, mc.stencil_starts[ip+1]))
        else
            TODO(fn)
        end
    elseif isexpr(ex, :invoke)
        mi, g = ex.args[1], ex.args[2]
        @assert mi isa MethodInstance
        ex_args = ex.args
        boxes = box_args(ex_args, mc)
        push!(mc.gc_roots, boxes)
        nargs = length(boxes)
        retbox = pointer(mc.ssas, ip)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_ARGS",    pointer(boxes))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",      Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS",   nargs)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",     retbox)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT",    pointer(mc.buf, mc.stencil_starts[ip+1]))
    elseif isexpr(ex, :new)
        ex_args = ex.args
        boxes = box_args(ex_args, mc)
        push!(mc.gc_roots, boxes)
        nargs = length(boxes)
        retbox = pointer(mc.ssas, ip)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_ARGS",    pointer(boxes))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",      Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS",   nargs)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",     retbox)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT",    pointer(mc.buf, mc.stencil_starts[ip+1]))
    elseif isexpr(ex, :foreigncall)
        fname, libname = if ex.args[1] isa QuoteNode
            ex.args[1].value, nothing
        elseif ex.args[1] isa Expr
            @assert Base.isexpr(ex.args[1], :call)
            eval(ex.args[1].args[2]), ex.args[1].args[3]
        elseif ex.args[1] isa Core.SSAValue || ex.args[1] isa Core.Argument
            ex.args[1], nothing
        else
            fname = ex.args[1].args[2].value
            libname = if ex.args[1].args[3] isa GlobalRef
                unwrap(ex.args[1].args[3])
            else
                unwrap(ex.args[1].args[3].args[2])
            end
            fname, libname
        end
        rettype = ex.args[2]
        argtypes = ex.args[3]
        nreq = ex.args[4]
        @assert nreq == 0
        conv = ex.args[5]
        @assert conv === QuoteNode(:ccall)
        args = ex.args[6:5+length(ex.args[3])]
        gc_roots = ex.args[6+length(ex.args[3])+1:end]
        boxes = box_args(args, mc)
        boxed_gc_roots = box_args(gc_roots, mc)
        push!(mc.gc_roots, boxes)
        push!(mc.gc_roots, boxed_gc_roots)
        nargs = length(boxes)
        retbox = pointer(mc.ssas, ip)
        ffi_argtypes = [ Cint(ffi_ctype_id(at)) for at in argtypes ]
        push!(mc.gc_roots, ffi_argtypes)
        ffi_rettype = Cint(ffi_ctype_id(rettype, return_type=true))
        # push!(mc.gc_roots, ffi_rettype) # kept alive through FFI_TYPE_CACHE
        sz_ffi_arg = Csize_t(ffi_rettype == -2 ? sizeof(rettype) : sizeof_ffi_arg())
        ffi_retval = Vector{UInt8}(undef, sz_ffi_arg)
        push!(mc.gc_roots, ffi_retval)
        rettype_ptr = pointer_from_objref(rettype)
        cif = Ffi_cif(rettype, tuple(argtypes...))
        push!(mc.gc_roots, cif)
        # set up storage for cargs array
        # - the first nargs elements hold pointers to the values
        # - the remaning elements are storage for pass-by-value arguments
        sz_cboxes = sizeof(Ptr{UInt64})*nargs
        for (i,ffi_at) in enumerate(ffi_argtypes)
            if 0 ≤ ffi_at ≤ 10 || ffi_at == -2
                at = argtypes[i]
                @assert sizeof(at) > 0
                sz_cboxes += sizeof(at)
            end
        end
        cboxes = ByteVector(sz_cboxes)
        push!(mc.gc_roots, cboxes)
        offset = sizeof(Ptr{UInt64})*nargs+1
        for (i,ffi_at) in enumerate(ffi_argtypes)
            if 0 ≤ ffi_at ≤ 10 || ffi_at == -2
                at = argtypes[i]
                cboxes[UInt64,i] = pointer(cboxes,UInt8,offset)
                offset += sizeof(at)
            end
        end
        sz_argtypes = Cint[ ffi_argtypes[i] == -2 ? sizeof(argtypes[i]) : 0 for i in 1:nargs ]
        push!(mc.gc_roots, sz_argtypes)
        static_f = true
        fptr = if isnothing(libname)
            if fname isa Symbol
                h = dlopen(dlpath("libjulia.so"))
                p = dlsym(h, fname, throw_error=false)
                if isnothing(p)
                    h = dlopen(dlpath("libjulia-internal.so"))
                    p = dlsym(h, fname)
                end
                p
            else
                static_f = false
                box_arg(fname, mc)
            end
        else
            if libname isa GlobalRef
                libname = unwrap(libname)
            elseif libname isa Expr
                @assert Base.isexpr(libname, :call)
                libname = unwrap(libname.args[2])
            end
            dlsym(dlopen(libname isa Ref ? libname[] : libname), fname)
        end
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_ARGS",        pointer(boxes))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CARGS",       pointer(cboxes))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CIF",         pointer(cif))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_F",           fptr)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_STATICF",     Cint(static_f))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_GCROOTS",     pointer(boxed_gc_roots))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NGCROOTS",    Cint(length(boxed_gc_roots)))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",          Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_ARGTYPES",    pointer(ffi_argtypes))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_SZARGTYPES",  pointer(sz_argtypes))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RETTYPE",     ffi_rettype)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RETTYPEPTR",  rettype_ptr)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_FFIRETVAL",   pointer(ffi_retval))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS",       nargs)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",         retbox)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT",        pointer(mc.buf, mc.stencil_starts[ip+1]))
    elseif isexpr(ex, :boundscheck)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        val = box_arg(ex.args[1], mc)
        ret = pointer(mc.ssas, ip)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",   Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",  ret)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_VAL",  val)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
    elseif isexpr(ex, :leave)
        hand_n_leave = count(ex.args) do a
            a !== nothing && mc.codeinfo.code[a.id] !== nothing
        end
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",           Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_HAND_N_LEAVE", Cint(hand_n_leave))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_EXC_THROWN",   pointer_from_objref(mc.exc_thrown))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
    elseif isexpr(ex, :pop_exception)
        prev_state = pointer(mc.ssas, ex.args[1].id)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",         Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_PREV_STATE", prev_state)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
    elseif isexpr(ex, :the_exception)
        ret = pointer(mc.ssas, ip)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",   Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",  ret)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
    else
        TODO(ex.head)
    end
end
function ffi_ctype_id(t; return_type=false)
    # need to keep this in sync with switch statements in ast_foreigncall.c
    return if t === Bool # Int8
        0
    elseif t === Cchar # Int8
        1
    elseif t === Cuchar # UInt8
        2
    elseif t === Cshort # Int16
        3
    elseif t === Cushort # UInt16
        4
    elseif t === Cint # Int32
        5
    elseif t === Cuint # UInt32
        6
    elseif t === Clonglong # Int64
        7
    elseif t === Culonglong # UInt64
        8
    elseif t === Cfloat # Float32
        9
    elseif t === Cdouble # Float64
        10
    elseif t === Ptr{UInt8} # TODO For what is this even needed?
        11
    elseif t <: Ptr
        12
    elseif t <: Ref
        if return_type
            # cf. https://discourse.julialang.org/t/returning-arbitrary-julia-value-from-c-function/11429/2
            @goto any
        end
        12
    elseif isconcretetype(t)
        -2
    else # Any
        @label any
        -1
    end
end

default_terminal() = REPL.LineEdit.terminal(Base.active_repl)

code_native(code::AbstractVector; kwargs...) = code_native(UInt8.(code); kwargs...)
code_native(code::Vector{UInt8};  kwargs...) = code_native(stdout, code; kwargs...)
function code_native(mc::MachineCode;
                     syntax::Symbol=:intel, interactive::Bool=false, color::Bool=true,
                     hex_for_imm::Bool=true)
    if interactive
        menu = CopyAndPatchMenu(mc, syntax, hex_for_imm)
        term = default_terminal()
        print('\n', annotated_code_native(menu, 1), '\n')
        TerminalMenus.request(term, menu; cursor=1)
    else
        io = IOBuffer()
        ioc = IOContext(io, stdout) # to keep the colors!!
        for i in 1:length(mc.codeinfo.code)
            _code_native!(ioc, mc, i; syntax, color, hex_for_imm)
        end
        println(stdout, String(take!(io)))
    end
    nothing
end
function code_native(io::IO, code::AbstractVector{UInt8};
                     syntax::Symbol=:intel, color::Bool=true, hex_for_imm::Bool=true)
    if syntax === :intel
        variant = 1
    elseif syntax === :att
        variant = 0
    else
        throw(ArgumentError("'syntax' must be either :intel or :att"))
    end
    codestr = join(Iterators.map(string, code), ' ')
    out, err = Pipe(), Pipe()
    # TODO src/disasm.cpp also exports exports a disassembler which is based on llvm-mc
    # jl_value_t *jl_dump_fptr_asm_impl(uint64_t fptr, char emit_mc, const char* asm_variant, const char *debuginfo, char binary)
    # maybe we can repurpose that to avoid the extra llvm-mc dependence?
    if hex_for_imm
        cmd = `llvm-mc --disassemble --output-asm-variant=$variant --print-imm-hex`
    else
        cmd = `llvm-mc --disassemble --output-asm-variant=$variant`
    end
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
    color ? print_native(io, str_out) : print(io, str_out)
end
function _code_native!(io::IO, mc::MachineCode, i::Int64;
                       syntax::Symbol=:intel, color::Bool=true, hex_for_imm::Bool=true)
    starts = mc.stencil_starts
    nstarts = length(starts)
    rng = starts[i]:(i < nstarts ? starts[i+1]-1 : length(mc.buf))
    stencil = view(mc.buf, rng)
    ex = mc.codeinfo.code[i]
    name = get_stencil_name(ex)
    title = " | $(name) | $ex"
    _code_native!(io, title, stencil, i; syntax, color, hex_for_imm)
end
@inline function _code_native!(io::IO, title, stencil, i;
                               syntax::Symbol=:intel, color::Bool=true, hex_for_imm::Bool=true)
    printstyled(io, i, ' ', title, '\n', bold=true, color=:green)
    code_native(io, stencil; syntax, color, hex_for_imm)
end



mutable struct CopyAndPatchMenu{T_MC<:MachineCode} <: TerminalMenus.ConfiguredMenu{TerminalMenus.Config}
    mc::T_MC
    syntax::Symbol
    hex_for_imm::Bool
    options::Vector{String}
    selected::Int
    pagesize::Int
    pageoffset::Int
    ip_col_width::Int
    ip_fmt::Format
    stencil_name_col_width::Int
    stencil_name_fmt::Format
    nheader::Int
    print_relocs::Bool
    config::TerminalMenus.Config
end

function CopyAndPatchMenu(mc, syntax, hex_for_imm)
    config = TerminalMenus.Config(scroll_wrap=true)
    options = string.(mc.codeinfo.code)
    pagesize = 10
    pageoffset = 0
    ip_col_width = max(ndigits(length(options)),2)
    ip_fmt = Format("%-$(ip_col_width)d")
    stencil_name_col_width = maximum(ex -> length(get_stencil_name(ex)), mc.codeinfo.code)
    stencil_name_fmt = Format("%-$(stencil_name_col_width)s")
    nheader = 0
    print_relocs = true
    menu = CopyAndPatchMenu(mc, syntax, hex_for_imm, options, 1, pagesize, pageoffset,
                            ip_col_width, ip_fmt, stencil_name_col_width, stencil_name_fmt,
                            nheader, print_relocs, config)
    header = TerminalMenus.header(menu)
    menu.nheader = countlines(IOBuffer(header))
    return menu
end

TerminalMenus.options(m::CopyAndPatchMenu) = m.options
TerminalMenus.cancel(m::CopyAndPatchMenu) = m.selected = -1
function annotated_code_native(menu::CopyAndPatchMenu, cursor::Int64)
    io = IOBuffer()
    ioc = IOContext(io, stdout)
    _code_native!(ioc, menu.mc, cursor; syntax=menu.syntax, hex_for_imm=menu.hex_for_imm)
    code = String(take!(io))
    menu.print_relocs || return code
    # this is a hacky way to relocate the _JIT_* patches in the native code output
    # we are given formatted and colored native code output of a patched stencil: code
    # we compute the native code output of an unpatched stencil (only _JIT_* args are unpatched): unpatched_code
    # we then compare code vs unpatched_code line by line, and every mismatch is a line where we patched
    # in practice we use the uncolored version of code_native to ignore any ansii color codes,
    # because we also need to compute the max line width for each line
    stencilinfo, buf, _ = get_stencil(menu.mc.codeinfo.code[cursor])
    relocs = stencilinfo.code.relocations
    ex = menu.mc.codeinfo.code[cursor]
    _code_native!(ioc, ex, buf, cursor; syntax=menu.syntax, color=false, hex_for_imm=menu.hex_for_imm)
    unpatched_code = String(take!(io))
    _code_native!(ioc, menu.mc, cursor; syntax=menu.syntax, color=false, hex_for_imm=menu.hex_for_imm)
    uncolored_code = String(take!(io))
    max_w = maximum(split(uncolored_code,'\n')[2:end]) do line
        # ignore first line which contains the SSA expression
        length(repr(line))
    end
    nreloc = 0
    for (i,(uc_line, line, up_line)) in enumerate(zip(eachline(IOBuffer(uncolored_code)),
                                                      eachline(IOBuffer(code)),
                                                      eachline(IOBuffer(unpatched_code))))
        i == 1 && (println(ioc, line); continue) # this is the title
        print(ioc, line)
        if !isempty(line) && uc_line != up_line && nreloc < length(relocs)
            nreloc += 1
            w = length(uc_line)
            Δw = max_w - w
            printstyled(ioc, ' '^Δw, "    # $(relocs[nreloc].symbol)", color=:light_blue)
        end
        println(ioc)
    end
    if nreloc != length(relocs)
        s = SimpleLogger(ioc)
        with_logger(s) do
            println(ioc)
            @error "relocation failed, found $nreloc but expected $(length(relocs))"
        end
    end
    code = String(take!(io))
    return code
end
function annotated_code_native_with_newlines(menu::CopyAndPatchMenu, cursor::Int64)
    N = length(menu.mc.codeinfo.code)
    n = min(N,menu.pagesize)+menu.nheader-1
    println(stdout, '\n'^(menu.nheader-1), annotated_code_native(menu, cursor), '\n'^n)
end

function TerminalMenus.move_down!(menu::CopyAndPatchMenu, cursor::Int64, lastoption::Int64)
    # from stdlib/REPL/TerminalMenus/AbstractMenu.jl
    if cursor < lastoption
        cursor += 1 # move selection down
        pagepos = menu.pagesize + menu.pageoffset
        if pagepos <= cursor && pagepos < lastoption
            menu.pageoffset += 1 # scroll page down
        end
    elseif TerminalMenus.scroll_wrap(menu)
        # wrap to top
        cursor = 1
        menu.pageoffset = 0
    end
    if cursor != menu.selected
        menu.selected = cursor
        annotated_code_native_with_newlines(menu, cursor)
    end
    cursor
end
function TerminalMenus.move_up!(menu::CopyAndPatchMenu, cursor::Int64, lastoption::Int64)
    # from stdlib/REPL/TerminalMenus/AbstractMenu.jl
    if cursor > 1
        cursor -= 1 # move selection up
        if cursor < (2+menu.pageoffset) && menu.pageoffset > 0
            menu.pageoffset -= 1 # scroll page up
        end
    elseif TerminalMenus.scroll_wrap(menu)
        # wrap to bottom
        cursor = lastoption
        menu.pageoffset = max(0, lastoption - menu.pagesize)
    end
    if cursor != menu.selected
        menu.selected = cursor
        annotated_code_native_with_newlines(menu, cursor)
    end
    cursor
end

function TerminalMenus.pick(menu::CopyAndPatchMenu, cursor::Int)
    menu.selected = cursor
    return false
end

function TerminalMenus.header(menu::CopyAndPatchMenu)
    io = IOBuffer(); ioc = IOContext(io, stdout)
    printstyled(ioc, 'q', color=:light_red, bold=true)
    q_str = String(take!(io))
    printstyled(ioc, 's', bold=true,
                color = menu.syntax === :intel ? :light_magenta : :light_yellow)
    s_str = String(take!(io))
    printstyled(ioc, menu.syntax,
                color = menu.syntax === :intel ? :light_magenta : :light_yellow)
    syntax_str = String(take!(io))
    printstyled(ioc, 'r', bold=true,
                color = menu.print_relocs ? :light_blue : :none)
    r_str = String(take!(io))
    printstyled(ioc, 'h', bold=true,
                color = menu.hex_for_imm ? :light_blue : :none)
    h_str = String(take!(io))
    """
    Scroll through expressions for analysis:
    [$q_str]uit, [$s_str]yntax = $(syntax_str), [$r_str]elocations, [$h_str]ex for immediate values
       ip$(' '^(menu.ip_col_width-2)) | stencil$(' '^(menu.stencil_name_col_width-7)) | SSA
    """
end

function TerminalMenus.writeline(buf::IOBuffer, menu::CopyAndPatchMenu, idx::Int, iscursor::Bool)
    ioc = IOContext(buf, stdout)
    sidx = format(menu.ip_fmt, idx)
    name = get_stencil_name(menu.mc.codeinfo.code[idx])
    sname = format(menu.stencil_name_fmt, name)
    if iscursor
        printstyled(ioc, sidx, " | ", sname, " | ", menu.options[idx], bold=true, color=:green)
    else
        print(ioc, sidx, " | ", sname, " | ", menu.options[idx])
    end
end


function TerminalMenus.keypress(menu::CopyAndPatchMenu, key::UInt32)
    if key == UInt32('s')
        menu.syntax = (menu.syntax === :intel) ? :att : :intel
        annotated_code_native_with_newlines(menu, menu.selected)
    elseif key == UInt32('r')
        menu.print_relocs ⊻= true
        annotated_code_native_with_newlines(menu, menu.selected)
    elseif key == UInt32('h')
        menu.hex_for_imm ⊻= true
        annotated_code_native_with_newlines(menu, menu.selected)
    end
    return false
end
