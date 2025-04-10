function jit(@nospecialize(fn), @nospecialize(argtypes::Tuple))
    optimize = true
    codeinfo, rettype = only(Base.code_typed(fn, argtypes; optimize))
    return jit(codeinfo, fn, rettype, argtypes)
end
function jit(codeinfo::Core.CodeInfo, @nospecialize(fn), @nospecialize(rettype), @nospecialize(argtypes))
    nstencils = length(codeinfo.code)
    ssa_stencil_starts = zeros(Int64, nstencils)
    inputs_stencil = Vector{Vector{Any}}(undef, nstencils)
    inputs_stencil_starts = Vector{Vector{Int64}}(undef, nstencils)

    st, bvec, _ = get_stencil("abi")
    code_size = length(only(st.code.body))
    ntmps = 0
    nroots = 0
    for (ip, ex) in enumerate(codeinfo.code)
        inputs = Vector{Any}()
        get_inputs!(inputs, codeinfo.code, ip)
        ntmps = max(ntmps, length(inputs) - ngcroots(ex))
        nroots = max(nroots, ngcroots(ex))
        inputs_stencil[ip] = inputs
        inputs_stencil_starts[ip] = zeros(Int64, length(inputs))
        for (i, input) in enumerate(inputs)
            # some inputs require value_pointers referencing codeinfo.code
            if Base.isexpr(ex, :foreigncall) && i == 1
                input = interpret_func_symbol(input, codeinfo)
                if input.jl_ptr === nothing && input.fptr === C_NULL && isempty(input.f_name)
                    if input.gcroot === nothing
                        error("ccall: first argument not a pointer or valid constant expression")
                    else
                        error("ccall: null function pointer")
                    end
                end
                if input.lib_expr !== C_NULL
                    nroots = max(nroots, ngcroots(ex) + 1)
                end
            elseif requires_value_pointer(input)
                if input isa ExprOf
                    id = input.ssa.id
                    stmt = codeinfo.code[id]
                    input = WithValuePtr{ExprOf}(value_pointer(stmt), input, stmt)
                elseif ex isa GlobalRef
                    input = WithValuePtr{GlobalRef}(value_pointer(codeinfo.code[ip]), input, ex)
                else
                    input = WithValuePtr(input, ex)
                end
            end
            inputs[i] = input
            st, bvec, _ = get_push_stencil(input)
            inputs_stencil_starts[ip][i] = 1 + code_size
            code_size += length(only(st.code.body))
        end
        st, bvec, _ = get_stencil(ex)
        ssa_stencil_starts[ip] = 1 + code_size
        code_size += length(only(st.code.body))
    end

    mc = MachineCode(
        code_size, fn, rettype, argtypes, codeinfo,
        ssa_stencil_starts, inputs_stencil_starts
    )

    ctx = Context(ntmps, nroots)
    emitabi!(mc, ctx)
    for ex in codeinfo.code
        ctx.ip += 1
        emitpushes!(mc, ctx, ex, inputs_stencil[ctx.ip])
        emitcode!(mc, ctx.ip, ex)
    end
    return mc
end


mutable struct Context
    ip::Int64 # current instruction pointer (F->ssa), 1-based
    i::Int64 # current push instruction pointer (F->tmps), 1-based
    ntmps::Int64 # max number of tmps needed
    nroots::Int64 # max nunmber of gcroots needed
end
Context(ntmps::Int64, nroots::Int64) = Context(0, 0, ntmps, nroots)


requires_value_pointer(::Any) = true
# We can address inputs of these kinds without value_pointer shenanigans
requires_value_pointer(::Boxable) = false
requires_value_pointer(::UndefInput) = false
requires_value_pointer(::Core.Argument) = false
requires_value_pointer(::Core.SSAValue) = false


# decorator-like type to capture value_pointer(val) where val is rooted *in* ex
# said differently: can take a pointer to an immutable object contained in ex
struct WithValuePtr{T}
    ptr::Ptr{Cvoid}
    val::T
    ex::Any
end

function WithValuePtr(val, ex)
    return TODO((val, ex))
end
function WithValuePtr(val, ex::Expr)
    i = something(findfirst(a -> a === val, ex.args))
    return WithValuePtr(value_pointer(ex.args[i]), val, ex)
end
function WithValuePtr(val, ex::Core.PhiNode)
    i = something(findfirst(a -> a === val, ex.values))
    return WithValuePtr(value_pointer(ex.values[i]), val, ex)
end
function WithValuePtr(val, ex::Union{Core.UpsilonNode, Core.PiNode, Core.ReturnNode})
    return WithValuePtr(value_pointer(ex.val), val, ex)
end


function get_stencil_name(ex::Expr)
    if Base.isexpr(ex, :call)
        return "ast_call"
    elseif Base.isexpr(ex, :invoke)
        return "ast_invoke"
    elseif Base.isexpr(ex, :new)
        return "ast_new"
    elseif Base.isexpr(ex, :foreigncall)
        return "ast_foreigncall"
    elseif Base.isexpr(ex, :boundscheck)
        return "ast_boundscheck"
    elseif Base.isexpr(ex, :leave)
        return "ast_leave"
    elseif Base.isexpr(ex, :pop_exception)
        return "ast_pop_exception"
    elseif Base.isexpr(ex, :the_exception)
        return "ast_the_exception"
    elseif Base.isexpr(ex, :throw_undef_if_not)
        return "ast_throw_undef_if_not"
    elseif Base.isexpr(ex, :meta)
        return "ast_meta"
    elseif Base.isexpr(ex, :coverageeffect)
        return "ast_coverageeffect"
    elseif Base.isexpr(ex, :inbounds)
        return "ast_inbounds"
    elseif Base.isexpr(ex, :loopinfo)
        return "ast_loopinfo"
    elseif Base.isexpr(ex, :aliasscope)
        return "ast_aliasscope"
    elseif Base.isexpr(ex, :popaliasscope)
        return "ast_popaliasscope"
    elseif Base.isexpr(ex, :inline)
        return "ast_inline"
    elseif Base.isexpr(ex, :noinline)
        return "ast_noinline"
    elseif Base.isexpr(ex, :gc_preserve_begin)
        return "ast_gc_preserve_begin"
    elseif Base.isexpr(ex, :gc_preserve_end)
        return "ast_gc_preserve_end"
    else
        TODO("Stencil not implemented yet:", ex)
    end
end
get_stencil_name(ex::Core.EnterNode) = "ast_enternode"
get_stencil_name(ex::Core.GlobalRef) = "ast_globalref"
get_stencil_name(ex::Core.GotoIfNot) = "ast_gotoifnot"
get_stencil_name(ex::Core.GotoNode) = "ast_goto"
get_stencil_name(ex::Core.PhiNode) = "ast_phinode"
get_stencil_name(ex::Core.PhiCNode) = "ast_phicnode"
get_stencil_name(ex::Core.PiNode) = "ast_pinode"
get_stencil_name(ex::Core.ReturnNode) = "ast_returnnode"
get_stencil_name(ex::Core.UpsilonNode) = "ast_upsilonnode"
get_stencil_name(ex::Nothing) = "ast_goto"
function get_stencil(name::String)
    if !haskey(STENCILS[], name)
        error("no stencil named '$name'")
    end
    return STENCILS[][name]
end
function get_stencil(ex)
    name = get_stencil_name(ex)
    if !haskey(STENCILS[], name)
        error("no stencil named '$name' found for expression $ex")
    end
    return STENCILS[][name]
end


get_push_stencil_name(arg::Any) = "jl_push_any"
get_push_stencil_name(arg::Core.Argument) = "jl_push_slot"
get_push_stencil_name(arg::Core.SSAValue) = "jl_push_ssa"
get_push_stencil_name(arg::Core.Const) = get_stencil_name(c.val)
function get_push_stencil_name(arg::Boxable)
    typename = lowercase(string(typeof(arg)))
    return "jl_box_and_push_$typename"
end
get_push_stencil_name(arg::GlobalRef) = "jl_eval_and_push_globalref"
get_push_stencil_name(arg::QuoteNode) = "jl_push_quotenode_value"
get_push_stencil_name(arg::Ptr{UInt8}) = "jl_box_uint8pointer"
get_push_stencil_name(@nospecialize(arg::Ptr)) = "jl_box_and_push_voidpointer"
get_push_stencil_name(@nospecialize(arg::WithValuePtr)) = get_push_stencil_name(arg.val)
function get_push_stencil_name(arg::NativeSymArg)
    if arg.jl_ptr isa Core.SSAValue
        return "jl_push_deref_ssa"
    elseif arg.jl_ptr isa Core.Argument
        return "jl_push_deref_slot"
    elseif arg.jl_ptr !== nothing
        TOOD(arg.jl_ptr)
    end
    arg.fptr !== C_NULL && return "jl_push_literal_voidpointer"
    @assert !isempty(arg.f_name)
    arg.lib_expr !== C_NULL && return "jl_push_runtime_sym_lookup"
    # TODO Vararg?
    return "jl_push_plt_voidpointer"
end
function get_push_stencil(ex)
    name = get_push_stencil_name(ex)
    if !haskey(STENCILS[], name)
        error("no stencil named '$name' found for expression $ex")
    end
    return STENCILS[][name]
end


function emitabi!(mc::MachineCode, ctx::Context)
    st, bvec, _ = get_stencil("abi")
    copyto!(mc.buf, 1, bvec, 1, length(bvec))
    patch!(mc.buf, 1, st.code, "_JIT_NARGS", Cint(length(mc.argtypes)))
    patch!(mc.buf, 1, st.code, "_JIT_NSSAS", Cint(length(mc.codeinfo.code)))
    patch!(mc.buf, 1, st.code, "_JIT_NTMPS", Cint(ctx.ntmps))
    patch!(mc.buf, 1, st.code, "_JIT_NGCROOTS", Cint(ctx.nroots))
    next = if length(mc.inputs_stencil_starts) > 0 &&
            length(first(mc.inputs_stencil_starts)) > 0
        first(first(mc.inputs_stencil_starts))
    else
        first(mc.stencil_starts)
    end
    patch!(mc.buf, 1, st.code, "_JIT_STENCIL", pointer(mc.buf, next))
    return
end


function emitpushes!(mc::MachineCode, ctx::Context, ex, inputs::Vector{Any})
    ctx.i = 0
    for input in inputs
        ctx.i += 1
        continuation = if ctx.i < length(inputs)
            pointer(mc.buf, mc.inputs_stencil_starts[ctx.ip][ctx.i + 1])
        else
            pointer(mc.buf, mc.stencil_starts[ctx.ip])
        end
        emitpush!(mc, ctx, continuation, input)
    end
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Boxable
    )
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_X", input)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Ptr{UInt8}
    )
    # special case jl_box_and_push_uint8pointer
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_P", input)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        @nospecialize(input::Ptr)
    )
    # special case for jl_box_and_push_voidpointer
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_P", Ptr{Cvoid}(input))
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::UndefInput
    )
    # C_NULL != jl_box_voidpointer(NULL)
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_P", Ptr{Cvoid}(C_NULL))
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Core.Argument
    )
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_N", Cint(input.n))
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Core.SSAValue
    )
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_ID", Cint(input.id))
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{ExprOf}
    )
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_P", input.ptr)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        @nospecialize(input::WithValuePtr{<:Any})
    )
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_P", input.ptr)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{GlobalRef}
    )
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_GR", input.ptr)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{QuoteNode}
    )
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_Q", input.ptr)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    return
end
function emitpush!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::NativeSymArg
    )
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
    if input.jl_ptr isa Core.SSAValue
        # TODO emit cpointer check
        patch!(mc.buf, stencil_start, st.code, "_JIT_ID", Cint(input.jl_ptr.id))
    elseif input.jl_ptr isa Core.Argument
        # TODO emit cpointer check
        patch!(mc.buf, stencil_start, st.code, "_JIT_N", Cint(input.jl_ptr.n))
    elseif input.jl_ptr !== nothing
        TOOD(input.jl_ptr)
    elseif input.fptr !== C_NULL
        TODO()
    elseif input.lib_expr !== C_NULL
        i_gc = ctx.nroots # root lib_expr result at the end of F->gcroots
        mi = mc.codeinfo.parent
        ptr_mod = mi.def isa Method ? value_pointer(mi.def.module) : value_pointer(mi.def)
        patch!(mc.buf, stencil_start, st.code, "_JIT_I_GC", Cint(i_gc))
        patch!(mc.buf, stencil_start, st.code, "_JIT_MOD", ptr_mod)
        patch!(mc.buf, stencil_start, st.code, "_JIT_LIB_EXPR", input.lib_expr)
        patch!(mc.buf, stencil_start, st.code, "_JIT_F_NAME", pointer(input.f_name))
    else
        # TODO Vararg?
        h = Libdl.dlopen(input.f_lib)
        p = Libdl.dlsym(h, input.f_name)
        patch!(mc.buf, stencil_start, st.code, "_JIT_P", p)
    end
    return
end


emitcode!(mc, ip, ex) = TODO(typeof(ex))
function emitcode!(mc, ip, ex::Nothing)
    st, bvec, _ = get_stencil(ex)
    continuation = get_continuation(mc, ip + 1)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::GlobalRef)
    st, bvec, _ = get_stencil(ex)
    continuation = get_continuation(mc, ip + 1)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::Core.EnterNode)
    st, bvec, _ = get_stencil(ex)
    catch_ip = ex.catch_dest
    leave_ip = catch_ip - 1
    call = get_continuation(mc, ip + 1)
    continuation_leave = get_continuation(mc, leave_ip)
    continuation_catch = get_continuation(mc, catch_ip)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CALL", call)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT_LEAVE", continuation_leave)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT_CATCH", continuation_catch)
    return
end
function emitcode!(mc, ip, ex::Core.ReturnNode)
    # TODO :unreachable nodes are also of type Core.ReturnNode. Anything to do here?
    st, bvec, _ = get_stencil(ex)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    return
end
function emitcode!(mc, ip, ex::Core.GotoNode)
    st, bvec, _ = get_stencil(ex)
    continuation = get_continuation(mc, ex.label)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::Core.GotoIfNot)
    st, bvec, _ = get_stencil(ex)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    continuation1 = get_continuation(mc, ex.dest)
    continuation2 = get_continuation(mc, ip + 1)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT1", continuation1)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT2", continuation2)
    return
end
function emitcode!(mc, ip, ex::Core.PhiNode)
    st, bvec, _ = get_stencil(ex)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    nedges = length(ex.edges)
    n = length(mc.codeinfo.code)
    local nphis
    if ip + 1 >= n
        nphis = 1
    else
        nphis = findfirst(mc.codeinfo.code[(ip + 1):end]) do e
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
            nphis = n - ip + 1
        end
    end
    ip_blockend = ip + nphis - 1
    continuation = get_continuation(mc, ip + 1)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_EDGES_FROM", pointer(ex.edges))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP_BLOCKEND", Cint(ip_blockend))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NEDGES", nedges)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::Core.PhiCNode)
    st, bvec, _ = get_stencil(ex)
    continuation = get_continuation(mc, ip + 1)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::Core.PiNode)
    # https://docs.julialang.org/en/v1/devdocs/ssair/#Phi-nodes-and-Pi-nodes
    # PiNodes are ignored in the interpreter, so ours also only copy values into ssas[ip]
    st, bvec, _ = get_stencil(ex)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    continuation = get_continuation(mc, ip + 1)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::Core.UpsilonNode)
    st, bvec, _ = get_stencil(ex)
    ssa_ip = Core.SSAValue(ip)
    ret_ip = findfirst(mc.codeinfo.code[(ip + 1):end]) do e
        e isa Core.PhiCNode && ssa_ip in e.values
    end
    if ret_ip === nothing
        # no use of this store, so it is safe to delete/ignore it
        # cf. https://docs.julialang.org/en/v1/devdocs/ssair/#PhiC-nodes-and-Upsilon-nodes
        ret_ip = 0
    else
        ret_ip += ip
    end
    continuation = get_continuation(mc, ip + 1)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET_IP", Cint(ret_ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::Expr)
    st, bvec, _ = get_stencil(ex)
    if Base.isexpr(ex, :call)
        nargs = length(ex.args)
        continuation = get_continuation(mc, ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS", UInt32(nargs))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :invoke)
        mi, g = ex.args[1], ex.args[2]
        @assert mi isa Core.MethodInstance || mi isa Base.CodeInstance
        nargs = length(ex.args)
        continuation = get_continuation(mc, ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS", UInt32(nargs))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :new)
        nargs = length(ex.args)
        continuation = get_continuation(mc, ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS", UInt32(nargs))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :foreigncall)
        rettype = ex.args[2]
        argtypes = ex.args[3]
        nreq = ex.args[4]
        @assert length(argtypes) ≥ nreq
        conv = ex.args[5]
        @assert conv isa QuoteNode
        @assert conv.value === :ccall || first(conv.value) === :ccall
        args = ex.args[6:(5 + length(ex.args[3]))]
        nargs = length(args)
        for at in argtypes
            isconcretetype(at) || continue
            for i in 1:fieldcount(at)
                ty = fieldtype(at, i)
                if ty isa Union
                    TODO("non-isbitstypes passed 'by-value', cf. issue #46786 and stencils/mwe_union.c")
                end
            end
        end
        ffi_argtypes = [ Cint(ffi_ctype_id(at)) for at in argtypes ]
        push!(mc.gc_roots, ffi_argtypes)
        ffi_rettype = Cint(ffi_ctype_id(rettype, return_type = true))
        # push!(mc.gc_roots, ffi_rettype) # kept alive through FFI_TYPE_CACHE
        sz_ffi_arg = Csize_t(ffi_rettype == -2 ? sizeof(rettype) : sizeof_ffi_arg())
        ffi_retval = Vector{UInt8}(undef, sz_ffi_arg)
        push!(mc.gc_roots, ffi_retval)
        rettype_ptr = pointer_from_objref(rettype)
        cif = Ffi_cif(rettype, tuple(argtypes...))
        push!(mc.gc_roots, cif)
        sz_argtypes = Cint[ ffi_argtypes[i] == -2 ? sizeof(argtypes[i]) : 0 for i in 1:nargs ]
        push!(mc.gc_roots, sz_argtypes)
        continuation = get_continuation(mc, ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CIF", pointer(cif))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_ARGTYPES", pointer(ffi_argtypes))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_SZARGTYPES", pointer(sz_argtypes))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RETTYPE", ffi_rettype)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RETTYPEPTR", rettype_ptr)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_FFIRETVAL", pointer(ffi_retval))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS", nargs)
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :boundscheck)
        continuation = get_continuation(mc, ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :leave)
        hand_n_leave = count(ex.args) do a
            a !== nothing && mc.codeinfo.code[a.id] !== nothing
        end
        continuation = get_continuation(mc, ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_HAND_N_LEAVE", Cint(hand_n_leave))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :pop_exception)
        continuation = get_continuation(mc, ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :the_exception)
        ret = pointer(mc.ssas, ip)
        continuation = get_continuation(mc, ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :throw_undef_if_not)
        continuation = get_continuation(mc, ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif any(
            s -> Base.isexpr(ex, s),
            (
                :meta, :coverageeffect, :inbounds, :loopinfo, :aliasscope, :popaliasscope,
                :inline, :noinline, :gc_preserve_begin, :gc_preserve_end,
            )
        )
        if Base.isexpr(ex, :gc_preserve_begin)
            # :gc_preserve_begin is a no-op if everything is pushed to frame *F (which is GC rooted)
            @assert all(s -> s isa Union{Core.SSAValue, Core.Argument}, ex.args)
        end
        continuation = get_continuation(mc, ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    else
        TODO(ex.head)
    end
    return
end
function ffi_ctype_id(t; return_type = false)
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
