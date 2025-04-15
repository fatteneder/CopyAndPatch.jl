function jit(@nospecialize(fn), @nospecialize(argtypes::Tuple))
    optimize = true
    codeinfo, rettype = only(Base.code_typed(fn, argtypes; optimize))
    # @show codeinfo
    return jit(codeinfo, fn, rettype, argtypes)
end
function jit(codeinfo::Core.CodeInfo, @nospecialize(fn), @nospecialize(rettype), @nospecialize(argtypes))
    ctx = Context(codeinfo)
    # compute total number of bytes and stencil offsets
    # abi stencil is handled separately from the AST instructions
    st = get_stencil("abi")
    code_size = length(only(st.md.code.body))
    instr_stencil_starts = zeros(Int64, ctx.nssas)
    load_stencil_starts = Vector{Vector{Int64}}(undef, ctx.nssas)
    for (ip, ex) in enumerate(codeinfo.code)
        ctx.ip = ip
        select_stencils!(ctx, ex)
        inputs = ctx.inputs[ip]
        roots = ctx.roots[ip]
        ctx.ntmps = max(ctx.ntmps, length(inputs))
        ctx.nroots = max(ctx.nroots, length(roots))
        load_stencils = ctx.load_stencils[ip]
        load_stencil_starts[ip] = zeros(Int64, length(inputs))
        for (i, st) in enumerate(load_stencils)
            load_stencil_starts[ip][i] = 1 + code_size
            code_size += length(only(st.md.code.body))
        end
        st = ctx.instr_stencils[ip]
        instr_stencil_starts[ip] = 1 + code_size
        code_size += length(only(st.md.code.body))
    end

    mc = MachineCode(
        code_size, fn, rettype, argtypes, codeinfo,
        instr_stencil_starts, load_stencil_starts
    )

    emit_abi!(mc, ctx)
    for (ip, ex) in enumerate(codeinfo.code)
        ctx.ip = ip
        emit_loads!(mc, ctx, ex)
        emit_instr!(mc, ctx, ex)
    end
    return mc
end


mutable struct Context
    codeinfo::Core.CodeInfo
    ip::Int64 # current instruction pointer (F->ssa), 1-based
    i::Int64 # current push instruction pointer (F->tmps), 1-based
    nssas::Int64 # number of ssa statements
    ntmps::Int64 # max number of tmp variables across all stencils
    nroots::Int64 # max number of root variables across all stencils
    # filled in select_stencils!
    inputs::Vector{Vector{Any}}
    roots::Vector{Vector{Any}}
    load_stencils::Vector{Vector{StencilData}}
    instr_stencils::Vector{StencilData}
end
function Context(codeinfo::Core.CodeInfo)
    nssas = length(codeinfo.code)
    ip, i, ntmps, nroots = 0, 0, 0, 0
    inputs = Vector{Any}[ Any[] for _ in 1:nssas ]
    roots = Vector{Any}[ Any[] for _ in 1:nssas ]
    load_stencils = Vector{StencilData}[ StencilData[] for _ in 1:nssas ]
    instr_stencils = Vector{StencilData}(undef, nssas)
    return Context(
        codeinfo, ip, i, nssas, ntmps, nroots,
        inputs, roots, load_stencils, instr_stencils
    )
end


# decorator-like type to capture value_pointer(val) where val is rooted *in* ex
# said differently: can take a pointer to an immutable object contained in ex
struct WithValuePtr{T}
    ptr::Ptr{Cvoid}
    val::T
    ex::Any
end


requires_value_pointer(::Any) = true
# We can address inputs of these kinds without value_pointer shenanigans
requires_value_pointer(::Boxable) = false
requires_value_pointer(::UndefInput) = false
requires_value_pointer(::Core.Argument) = false
requires_value_pointer(::Core.SSAValue) = false


function extract_inputs!(ctx::Context, ex::Any)
    ctx.inputs[ctx.ip] = get_inputs(ctx.codeinfo.code, ctx.ip)
    # extract value_pointers for immutable inputs rooted in ctx.codeinfo.code
    for (i, input) in enumerate(ctx.inputs[ctx.ip])
        ctx.i = i
        if requires_value_pointer(input)
            if input isa ExprOf
                id = input.ssa.id
                stmt = ctx.codeinfo.code[id]
                input = WithValuePtr(value_pointer(stmt), input, stmt)
            elseif ex isa GlobalRef
                input = WithValuePtr(value_pointer(ctx.codeinfo.code[ctx.ip]), input, ex)
            elseif ex isa Expr
                idx = something(findfirst(a -> a === input, ex.args))
                input = WithValuePtr(value_pointer(ex.args[idx]), input, ex)
            elseif ex isa Core.PhiNode
                idx = something(findfirst(a -> a === input, ex.values))
                input = WithValuePtr(value_pointer(ex.values[idx]), input, ex)
            elseif ex isa Union{Core.UpsilonNode, Core.PiNode, Core.ReturnNode}
                @assert isdefined(ex, :val)
                input = WithValuePtr(value_pointer(ex.val), input, ex)
            end
        end
        ctx.inputs[ctx.ip][ctx.i] = input
    end
    return
end


function get_stencil(name::String)
    if !haskey(STENCILS[], name)
        error("no stencil named '$name'")
    end
    return STENCILS[][name]
end


load_stencil_generic_name(arg::Any) = "jl_push_any"
load_stencil_generic_name(arg::Core.Argument) = "jl_push_slot"
load_stencil_generic_name(arg::Core.SSAValue) = "jl_push_ssa"
load_stencil_generic_name(arg::Core.Const) = get_stencil_name(c.val)
function load_stencil_generic_name(arg::Boxable)
    typename = lowercase(string(typeof(arg)))
    return "jl_box_and_push_$typename"
end
load_stencil_generic_name(arg::GlobalRef) = "jl_eval_and_push_globalref"
load_stencil_generic_name(arg::QuoteNode) = "jl_push_quotenode_value"
load_stencil_generic_name(arg::Ptr{UInt8}) = "jl_box_uint8pointer"
load_stencil_generic_name(@nospecialize(arg::Ptr)) = "jl_box_and_push_voidpointer"
load_stencil_generic_name(@nospecialize(arg::WithValuePtr)) = load_stencil_generic_name(arg.val)
function load_stencil_generic_name(arg::NativeSymArg)
    if arg.jl_ptr isa Core.SSAValue
        return "jl_push_deref_ssa"
    elseif arg.jl_ptr isa Core.Argument
        return "jl_push_deref_slot"
    elseif arg.jl_ptr !== nothing
        TOOD(arg.jl_ptr)
    end
    arg.fptr !== C_NULL && return "jl_push_literal_voidpointer"
    # @assert !isempty(arg.f_name)
    arg.lib_expr !== C_NULL && return "jl_push_runtime_sym_lookup"
    # TODO Vararg?
    return "jl_push_plt_voidpointer"
end
function select_load_stencil_generic(ex)
    name = load_stencil_generic_name(ex)
    if !haskey(STENCILS[], name)
        error("no stencil named '$name' found for expression $ex")
    end
    return STENCILS[][name]
end


function emit_abi!(mc::MachineCode, ctx::Context)
    st = get_stencil("abi")
    copyto!(mc.buf, 1, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, 1, st.md.code, "_JIT_NARGS", Cint(length(mc.argtypes)))
    patch!(mc.buf, 1, st.md.code, "_JIT_NSSAS", Cint(length(mc.codeinfo.code)))
    patch!(mc.buf, 1, st.md.code, "_JIT_NTMPS", Cint(ctx.ntmps))
    patch!(mc.buf, 1, st.md.code, "_JIT_NGCROOTS", Cint(ctx.nroots))
    next = if length(mc.inputs_stencil_starts) > 0 && length(first(mc.inputs_stencil_starts)) > 0
        first(first(mc.inputs_stencil_starts))
    else
        first(mc.stencil_starts)
    end
    patch!(mc.buf, 1, st.md.code, "_JIT_STENCIL", pointer(mc.buf, next))
    return
end


function emit_loads_generic!(mc::MachineCode, ctx::Context)
    ctx.i = 0
    for input in ctx.inputs[ctx.ip]
        ctx.i += 1
        continuation = if ctx.i < length(ctx.inputs[ctx.ip])
            pointer(mc.buf, mc.inputs_stencil_starts[ctx.ip][ctx.i + 1])
        else
            pointer(mc.buf, mc.stencil_starts[ctx.ip])
        end
        emit_load_generic!(mc, ctx, continuation, input)
    end
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Boxable
    )
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_X", input)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Ptr{UInt8}
    )
    # special case jl_box_and_push_uint8pointer
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", input)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        @nospecialize(input::Ptr)
    )
    # special case for jl_box_and_push_voidpointer
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", Ptr{Cvoid}(input))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::UndefInput
    )
    # C_NULL != jl_box_voidpointer(NULL)
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", Ptr{Cvoid}(C_NULL))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Core.Argument
    )
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_N", Cint(input.n))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Core.SSAValue
    )
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_ID", Cint(input.id))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{ExprOf}
    )
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", input.ptr)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        @nospecialize(input::WithValuePtr{<:Any})
    )
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", input.ptr)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{GlobalRef}
    )
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_GR", input.ptr)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{QuoteNode}
    )
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_Q", input.ptr)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::NativeSymArg
    )
    st = ctx.load_stencils[ctx.ip][ctx.i]
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    if input.jl_ptr isa Core.SSAValue
        # TODO emit cpointer check
        patch!(mc.buf, stencil_start, st.md.code, "_JIT_ID", Cint(input.jl_ptr.id))
    elseif input.jl_ptr isa Core.Argument
        # TODO emit cpointer check
        patch!(mc.buf, stencil_start, st.md.code, "_JIT_N", Cint(input.jl_ptr.n))
    elseif input.jl_ptr !== nothing
        TOOD(input.jl_ptr)
    elseif input.fptr !== C_NULL
        TODO()
    elseif input.lib_expr !== C_NULL
        i_gc = ctx.nroots # root lib_expr result at the end of F->gcroots
        mi = mc.codeinfo.parent
        ptr_mod = mi.def isa Method ? value_pointer(mi.def.module) : value_pointer(mi.def)
        patch!(mc.buf, stencil_start, st.md.code, "_JIT_I_GC", Cint(i_gc))
        patch!(mc.buf, stencil_start, st.md.code, "_JIT_MOD", ptr_mod)
        patch!(mc.buf, stencil_start, st.md.code, "_JIT_LIB_EXPR", input.lib_expr)
        patch!(mc.buf, stencil_start, st.md.code, "_JIT_F_NAME", pointer(input.f_name))
    else
        # TODO Vararg?
        h = Libdl.dlopen(input.f_lib)
        p = Libdl.dlsym(h, input.f_name)
        patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", p)
    end
    return
end


# Codegen interface
select_stencils!(ctx::Context, ex::Any) = TODO("select_stencils! for $ex")
emit_loads!(ctx::Context, ex::Any) = TODO("emit_loads! for $ex")
emit_instr!(mc::MachineCode, ctx::Context, ex::Any) = TODO("emit_instr! for $ex")


# Nothing
function select_stencils!(ctx::Context, ex::Nothing)
    extract_inputs!(ctx, ex)
    @assert length(ctx.inputs[ctx.ip]) == 0
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_goto")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Nothing) = nothing
function emit_instr!(mc::MachineCode, ctx::Context, ex::Nothing)
    st = ctx.instr_stencils[ctx.ip]
    continuation = get_continuation(mc, ctx.ip + 1)
    copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# GlobalRef
function select_stencils!(ctx::Context, ex::GlobalRef)
    extract_inputs!(ctx, ex)
    @assert length(ctx.inputs[ctx.ip]) == 1
    # ctx.load_stencils[ctx.ip] = [ select_load_stencil_generic("jl_eval_and_push_globalref") ]
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_globalref")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::GlobalRef) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::GlobalRef)
    st = ctx.instr_stencils[ctx.ip]
    continuation = get_continuation(mc, ctx.ip + 1)
    copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Core.EnterNode
function select_stencils!(ctx::Context, ex::Core.EnterNode)
    extract_inputs!(ctx, ex)
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_enternode")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.EnterNode) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.EnterNode)
    st = ctx.instr_stencils[ctx.ip]
    catch_ip = ex.catch_dest
    leave_ip = catch_ip - 1
    call = get_continuation(mc, ctx.ip + 1)
    continuation_leave = get_continuation(mc, leave_ip)
    continuation_catch = get_continuation(mc, catch_ip)
    copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CALL", call)
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT_LEAVE", continuation_leave)
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT_CATCH", continuation_catch)
    return
end


# Core.ReturnNode
function select_stencils!(ctx::Context, ex::Core.ReturnNode)
    extract_inputs!(ctx, ex)
    @assert length(ctx.inputs[ctx.ip]) ≤ 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_returnnode")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.ReturnNode) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.ReturnNode)
    # TODO :unreachable nodes are also of type Core.ReturnNode. Anything to do here?
    st = ctx.instr_stencils[ctx.ip]
    copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
    return
end


# Core.GotoIfNot
function select_stencils!(ctx::Context, ex::Core.GotoNode)
    extract_inputs!(ctx, ex)
    @assert length(ctx.inputs[ctx.ip]) == 0
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_goto")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.GotoNode) = nothing
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.GotoNode)
    st = ctx.instr_stencils[ctx.ip]
    continuation = get_continuation(mc, ex.label)
    copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Core.GotoIfNot
function select_stencils!(ctx::Context, ex::Core.GotoIfNot)
    extract_inputs!(ctx, ex)
    @assert length(ctx.inputs[ctx.ip]) == 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_gotoifnot")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.GotoIfNot) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.GotoIfNot)
    st = ctx.instr_stencils[ctx.ip]
    copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    continuation1 = get_continuation(mc, ex.dest)
    continuation2 = get_continuation(mc, ctx.ip + 1)
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT1", continuation1)
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT2", continuation2)
    return
end


# Core.PhiNode
function select_stencils!(ctx::Context, ex::Core.PhiNode)
    extract_inputs!(ctx, ex)
    @assert length(ctx.inputs[ctx.ip]) ≥ 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_phinode")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.PhiNode) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.PhiNode)
    st = ctx.instr_stencils[ctx.ip]
    copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    nedges = length(ex.edges)
    n = length(mc.codeinfo.code)
    local nphis
    if ctx.ip + 1 >= n
        nphis = 1
    else
        nphis = findfirst(mc.codeinfo.code[(ctx.ip + 1):end]) do e
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
            nphis = n - ctx.ip + 1
        end
    end
    ip_blockend = ctx.ip + nphis - 1
    continuation = get_continuation(mc, ctx.ip + 1)
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_EDGES_FROM", pointer(ex.edges))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP_BLOCKEND", Cint(ip_blockend))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_NEDGES", nedges)
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Core.PhiCNode
function select_stencils!(ctx::Context, ex::Core.PhiCNode)
    extract_inputs!(ctx, ex)
    # @assert length(ctx.inputs[ctx.ip]) ≥ 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_phicnode")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.PhiCNode) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.PhiCNode)
    st = ctx.instr_stencils[ctx.ip]
    continuation = get_continuation(mc, ctx.ip + 1)
    copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Core.PiNode
function select_stencils!(ctx::Context, ex::Core.PiNode)
    extract_inputs!(ctx, ex)
    @assert length(ctx.inputs[ctx.ip]) == 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_pinode")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.PiNode) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.PiNode)
    # https://docs.julialang.org/en/v1/devdocs/ssair/#Phi-nodes-and-Pi-nodes
    # PiNodes are ignored in the interpreter, so ours also only copy values into ssas[ip]
    st = ctx.instr_stencils[ctx.ip]
    copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    continuation = get_continuation(mc, ctx.ip + 1)
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Core.UpsilonNode
function select_stencils!(ctx::Context, ex::Core.UpsilonNode)
    extract_inputs!(ctx, ex)
    @assert length(ctx.inputs[ctx.ip]) == 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_upsilonnode")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.UpsilonNode) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.UpsilonNode)
    st = ctx.instr_stencils[ctx.ip]
    ssa_ip = Core.SSAValue(ctx.ip)
    ret_ip = findfirst(mc.codeinfo.code[(ctx.ip + 1):end]) do e
        e isa Core.PhiCNode && ssa_ip in e.values
    end
    if ret_ip === nothing
        # no use of this store, so it is safe to delete/ignore it
        # cf. https://docs.julialang.org/en/v1/devdocs/ssair/#PhiC-nodes-and-Upsilon-nodes
        ret_ip = 0
    else
        ret_ip += ctx.ip
    end
    continuation = get_continuation(mc, ctx.ip + 1)
    copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_RET_IP", Cint(ret_ip))
    patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Expr
function select_stencils!(ctx::Context, ex::Expr)
    extract_inputs!(ctx, ex)
    if Base.isexpr(ex, :foreigncall) && length(ctx.inputs[ctx.ip]) ≥ 1
        fn = ctx.inputs[ctx.ip][1]
        fn = if fn isa WithValuePtr
            fn.val
        elseif fn isa Core.SSAValue || fn isa Core.Argument
            fn
        else
            TODO(fn)
        end
        fn = interpret_func_symbol(fn, ctx.codeinfo)
        if fn.jl_ptr === nothing && fn.fptr === C_NULL && isempty(fn.f_name)
            if fn.gcroot === nothing
                error("ccall: first argument not a pointer or valid constant expression")
            else
                error("ccall: null function pointer")
            end
        end
        if fn.lib_expr !== C_NULL
            roots = ctx.roots[ctx.ip]
            ctx.nroots = max(ctx.nroots, length(roots) + 1)
        end
        ctx.inputs[ctx.ip][1] = fn
    end
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    # runic: off
    name = if Base.isexpr(ex, :call); "ast_call"
    elseif Base.isexpr(ex, :invoke); "ast_invoke"
    elseif Base.isexpr(ex, :new); "ast_new"
    elseif Base.isexpr(ex, :foreigncall); "ast_foreigncall"
    elseif Base.isexpr(ex, :boundscheck); "ast_boundscheck"
    elseif Base.isexpr(ex, :leave); "ast_leave"
    elseif Base.isexpr(ex, :pop_exception); "ast_pop_exception"
    elseif Base.isexpr(ex, :the_exception); "ast_the_exception"
    elseif Base.isexpr(ex, :throw_undef_if_not); "ast_throw_undef_if_not"
    elseif Base.isexpr(ex, :meta); "ast_meta"
    elseif Base.isexpr(ex, :coverageeffect); "ast_coverageeffect"
    elseif Base.isexpr(ex, :inbounds); "ast_inbounds"
    elseif Base.isexpr(ex, :loopinfo); "ast_loopinfo"
    elseif Base.isexpr(ex, :aliasscope); "ast_aliasscope"
    elseif Base.isexpr(ex, :popaliasscope); "ast_popaliasscope"
    elseif Base.isexpr(ex, :inline); "ast_inline"
    elseif Base.isexpr(ex, :noinline); "ast_noinline"
    elseif Base.isexpr(ex, :gc_preserve_begin); "ast_gc_preserve_begin"
    elseif Base.isexpr(ex, :gc_preserve_end); "ast_gc_preserve_end"
    else TODO("Stencil not implemented yet:", ex) end
    # runic: on
    return ctx.instr_stencils[ctx.ip] = get_stencil(name)
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Expr) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Expr)
    st = ctx.instr_stencils[ctx.ip]
    if Base.isexpr(ex, :call)
        nargs = length(ex.args)
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_NARGS", UInt32(nargs))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :invoke)
        mi, g = ex.args[1], ex.args[2]
        @assert mi isa Core.MethodInstance || mi isa Base.CodeInstance
        nargs = length(ex.args)
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_NARGS", UInt32(nargs))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :new)
        nargs = length(ex.args)
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_NARGS", UInt32(nargs))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
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
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CIF", pointer(cif))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_ARGTYPES", pointer(ffi_argtypes))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_SZARGTYPES", pointer(sz_argtypes))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_RETTYPE", ffi_rettype)
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_RETTYPEPTR", rettype_ptr)
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_FFIRETVAL", pointer(ffi_retval))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_NARGS", nargs)
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :boundscheck)
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :leave)
        hand_n_leave = count(ex.args) do a
            a !== nothing && mc.codeinfo.code[a.id] !== nothing
        end
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_HAND_N_LEAVE", Cint(hand_n_leave))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :pop_exception)
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :the_exception)
        ret = pointer(mc.ssas, ctx.ip)
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :throw_undef_if_not)
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
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
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip))
        patch!(mc.buf, mc.stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
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
