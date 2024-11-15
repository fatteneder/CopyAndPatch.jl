function jit(codeinfo::Core.CodeInfo, @nospecialize(fn), @nospecialize(rettype), @nospecialize(argtypes))
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


function jit(@nospecialize(fn), @nospecialize(argtypes::Tuple))
    optimize = true
    codeinfo, rettype = only(code_typed(fn, argtypes; optimize))
    return jit(codeinfo, fn, rettype, argtypes)
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
    elseif isexpr(ex, :throw_undef_if_not)
        return "ast_throw_undef_if_not"
    elseif isexpr(ex, :meta)
        return "ast_meta"
    elseif isexpr(ex, :coverageeffect)
        return "ast_coverageeffect"
    elseif isexpr(ex, :inbounds)
        return "ast_inbounds"
    elseif isexpr(ex, :loopinfo)
        return "ast_loopinfo"
    elseif isexpr(ex, :aliasscope)
        return "ast_aliasscope"
    elseif isexpr(ex, :popaliasscope)
        return "ast_popaliasscope"
    elseif isexpr(ex, :inline)
        return "ast_inline"
    elseif isexpr(ex, :noinline)
        return "ast_noinline"
    elseif isexpr(ex, :gc_preserve_begin)
        return "ast_gc_preserve_begin"
    elseif isexpr(ex, :gc_preserve_end)
        return "ast_gc_preserve_end"
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
    if !haskey(STENCILS[], name)
        error("no stencil '$name' found for expression $ex")
    end
    return STENCILS[][name]
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
        if a isa Boxable
            push!(static_prms, [value_pointer(a)])
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
        elseif a isa Union
            push!(static_prms, [value_pointer(a)])
        elseif a isa Type
            push!(static_prms, [value_pointer(a)])
        else
            try
                push!(static_prms, [pointer_from_objref(a)])
            catch e
                @error "boxing of $a failed"
                rethrow(e)
            end
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
            if !(e isa Core.PhiNode)
                if e isa Expr || e isa Core.ReturnNode || e isa Core.GotoIfNot ||
                    e isa Core.GotoNode || e isa Core.PhiCNode || e isa Core.UpsilonNode ||
                    e isa Core.SSAValue
                    return true
                end
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
            st, bvec, _ = get(STENCILS[], name) do
                error("don't know how to handle intrinsic $name")
            end
            copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
            for n in 1:nargs
                patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_A$n", boxes[n])
            end
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",  retbox)
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
        elseif iscallable(fn) || g isa Core.SSAValue
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
            @assert ex.args[1].args[2] isa QuoteNode
            ex.args[1].args[2].value, ex.args[1].args[3]
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
        @assert length(argtypes) ≥ nreq
        conv = ex.args[5]
        @assert conv isa QuoteNode
        @assert conv.value === :ccall || first(conv.value) === :ccall
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
        ret = pointer(mc.ssas, ip)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",   Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",  ret)
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
    elseif isexpr(ex, :throw_undef_if_not)
        var  = box_arg(ex.args[1], mc)
        cond = box_arg(ex.args[2], mc)
        ret = pointer(mc.ssas, ip)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",   Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_COND", cond)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_VAR",  var)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",  ret)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1]))
    elseif any(s -> isexpr(ex, s),
               (:meta, :coverageeffect, :inbounds, :loopinfo, :aliasscope, :popaliasscope,
                :inline, :noinline, :gc_preserve_begin, :gc_preserve_end)
              )
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
