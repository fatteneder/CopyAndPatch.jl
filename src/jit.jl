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
        ntmps = max(ntmps, length(inputs)-ngcroots(ex))
        nroots = max(nroots, ngcroots(ex))
        inputs_stencil[ip] = inputs
        inputs_stencil_starts[ip] = zeros(Int64, length(inputs))
        for (i, input) in enumerate(inputs)
            # some inputs require value_pointers referencing codeinfo.code
            # TODO Move this stuff into separate function
            # input = maybe_requires_value_pointer(input, ex, codeinfo)
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
                    nroots = max(nroots, ngcroots(ex)+1)
                end
            elseif requires_value_pointer(input)
                if input isa ExprOf
                    id = input.ssa.id
                    stmt = codeinfo.code[id]
                    input = WithValuePtr{ExprOf}(value_pointer(stmt), input, stmt)
                elseif ex isa GlobalRef
                    input = WithValuePtr{GlobalRef}(value_pointer(codeinfo.code[ip]), input, ex)
                else
                    # TODO Remove WithValuePtr constructor
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

    mc = MachineCode(code_size, fn, rettype, argtypes, codeinfo,
                     ssa_stencil_starts, inputs_stencil_starts)

    ctx = Context(ntmps, nroots)
    emitabi!(mc, ctx)
    for ex in codeinfo.code
        ctx.ip += 1
        emitpushes!(mc, ctx, ex, inputs_stencil[ctx.ip])
        emitcode!(mc, ctx.ip, ex)
    end
    return mc
end


ngcroots(ex::Any) = 0
function ngcroots(ex::Expr)
    Base.isexpr(ex, :foreigncall) || return 0
    return length(ex.args)-(6+length(ex.args[3]))+1
end

mutable struct Context
    ip::Int64 # current instruction pointer (F->ssa), 1-based
    i::Int64 # current push instruction pointer (F->tmps), 1-based
    ntmps::Int64 # max number of tmps needed
    nroots::Int64 # max nunmber of gcroots needed
end
Context(ntmps::Int64, nroots::Int64) = Context(0, 0, ntmps, nroots)


function convert_cconv(lhd::Symbol)
    if lhd === :stdcall
        return :x86_stdcall, false
    elseif lhd === :cdecl || lhd === :ccall
        # `ccall` calling convention is a placeholder for when there isn't one provided
        # it is not by itself a valid calling convention name to be specified in the surface
        # syntax.
        return :cconv_c, false
    elseif lhd === :fastcall
        return :x86_fastcall, false
    elseif lhd === :thiscall
        return :x86_thiscall, false
    elseif lhd === :llvmcall
        error("ccall: CopyAndPatch can't perform llvm calls")
        return :cconv_c, true
    end
    error("ccall: invalid calling convetion $lhd")
end


Base.@kwdef mutable struct NativeSymArg
    jl_ptr::Any = nothing
    fptr::Ptr = C_NULL
    f_name::String = "" # if the symbol name is known
    f_lib::String = "" # if a library name is specified
    lib_expr::Ptr = C_NULL # expression to compute library path lazily
    gcroot::Any = nothing
end


# based on julia/src/{codegen,ccall}.cpp
function interpret_func_symbol(ex, cinfo::Core.CodeInfo)
    symarg = NativeSymArg()
    ptr = static_eval(ex, cinfo)
    if ptr === nothing
        if ex isa Expr && Base.isexpr(ex, :call) && length(ex.args) == 3 &&
                ex.args[1] isa GlobalRef && ex.args[1].mod == Core && ex.args[1].name == :tuple
            # attempt to interpret a non-constant 2-tuple expression as (func_name, lib_name()), where
            # `lib_name()` will be executed when first used.
            name_val = static_eval(ex.args[2], cinfo)
            if name_val isa Symbol
                symarg.f_name = string(name_val)
                symarg.lib_expr = value_pointer(ex.args[3])
                return symarg
            elseif name_val isa String
                symarg.f_name = string(name_val)
                symarg.gcroot = [name_val]
                symarg.lib_expr = value_pointer(ex.args[3])
                return symarg
            end
        end
        if ex isa Core.SSAValue || ex isa Core.Argument
            symarg.jl_ptr = ex
        else
            TODO(ex)
        end
    else
        symarg.gcroot = ptr
        if ptr isa Tuple && length(ptr) == 1
            ptr = ptr[1]
        end
        if ptr isa Symbol
            symarg.f_name = string(ptr)
        elseif ptr isa String
            symarg.f_name = ptr
        end
        if !isempty(symarg.f_name)
            # @assert !llvmcall
            iname = string("i", symarg.f_name)
            if Libdl.dlsym(LIBJULIAINTERNAL[], iname, throw_error=false) !== nothing
                symarg.f_lib = Libdl.dlpath("libjulia-internal.so")
                symarg.f_name = iname
            else
                symarg.f_lib = Libdl.find_library(iname)
            end
        elseif ptr isa Ptr
            TODO()
            symarg.f = value_pointer(ptr)
            # else if (jl_is_cpointer_type(jl_typeof(ptr))) {
            #     fptr = *(void(**)(void))jl_data_ptr(ptr);
            # }
        elseif ptr isa Tuple && length(ptr) > 1
            t1 = ptr[1]
            if t1 isa Symbol
                symarg.f_name = string(t1)
            elseif t1 isa String
                symarg.f_name = t1
            end
            t2 = ptr[2]
            if t2 isa Symbol
                symarg.f_lib = string(t2)
            elseif t2 isa String
                symarg.f_lib = t2
            else
                TODO()
                symarg.lib_expr = t2
            end
        end
    end
    return symarg
end

function walk_binding_partitions_all(bpart::Union{Nothing,Core.BindingPartition},
        min_world::UInt64, max_world::UInt64)
    while true
        if bpart === nothing
            return bpart
        end
        bkind = Base.binding_kind(bpart)
        if !Base.is_some_imported(bkind)
            return bpart
        end
        bnd = bpart.restriction
        bpart = bnd.partitions
    end
end

static_eval(arg::Any, cinfo::Core.CodeInfo) = arg
static_eval(arg::Union{Core.Argument,Core.SlotNumber,Core.MethodInstance}, cinfo::Core.CodeInfo) = nothing
static_eval(arg::QuoteNode, cinfo::Core.CodeInfo) = getfield(arg, 1)
function static_eval(arg::Symbol, cinfo::Core.CodeInfo)
    TODO()
    method = cinfo.parent.def
    mod = method.var"module"
    bnd, bpart, bkind = get_binding_and_partition_and_kind(mod, arg, cinfo.min_world, cinfo.max_world)
    bkind_is_const = @ccall jl_bkind_is_some_constant(bkind::UInt8)::Cint
    if bpart != C_NULL && Bool(bkind_is_const)
        return bpart[].restriction
    end
    return nothing
end
function static_eval(arg::Core.SSAValue, cinfo::Core.CodeInfo)
    # TODO What to do here?
    return nothing
    # ssize_t idx = ((jl_ssavalue_t*)ex)->id - 1;
    # assert(idx >= 0);
    # if (ctx.ssavalue_assigned[idx]) {
    #     return ctx.SAvalues[idx].constant;
    # }
    # return NULL;
end
function static_eval(arg::GlobalRef, cinfo::Core.CodeInfo)
    mod, name = arg.mod, arg.name
    bnd = convert(Core.Binding, arg)
    bpart = walk_binding_partitions_all(bnd.partitions, cinfo.min_world, cinfo.max_world)
    bkind = bpart.kind
    bkind = Base.binding_kind(bpart)
    bkind_is_const = Base.is_some_const_binding(bkind)
    if bpart !== nothing && bkind_is_const
        v = bpart.restriction
        # TODO Deprecation warning
        return v
    end
    return nothing
end
function static_eval(ex::Expr, cinfo::Core.CodeInfo)
    min_world, max_world = cinfo.min_world, cinfo.max_world
    if Base.isexpr(ex, :call)
        f = static_eval(ex.args[1], cinfo)
        if f != nothing
            if length(ex.args) == 3 && (f == Core.getfield || f == Core.getglobal)
                m = static_eval(ex.args[2], cinfo)
                if m != nothing || !(m isa Module)
                    return nothing
                end
                s = static_eval(ex.args[3], cinfo)
                if s != nothing && s isa Symbol
                    bnd, bpart, bkind = get_binding_and_partition_and_kind(m, s, min_world, max_world)
                end
                if bpart != C_NULL && Bool(bkind_is_const)
                    v = bpart[].restriction
                    if v != nothing
                        @ccall jl_binding_deprecation_warning(mod::Ref{Module}, name::Symbol, bnd::Ref{Core.Binding})::Cvoid
                        println(stderr)
                    end
                    return v
                end
            elseif f == Core.Tuple || f == Core.apply_type
                n = length(ex.args)-1
                if n == 0 && f == Core.Tuple
                    return ()
                end
                v = Vector{Any}(undef, n+1)
                v[1] = f
                for i in 1:n
                    v[i+1] = static_eval(ex.args[i+1])
                    if v[i+1] == nothing
                        return nothing
                    end
                end
            end
            return try
                Base.invoke_in_world(1, v, n+1)
            catch
                nothing
            end
        end
    elseif Base.isexpr(ex, :static_parameter)
        idx = ex.args[1]
        mi = cinfo.parent
        if idx <= length(mi.sparam_vals)
            e = mi.sparam_vals[idx]
            return e isa TypeVar ? nothing : e
        end
    end
    return nothing
end


struct WithValuePtr{T}
    ptr::Ptr{Cvoid}
    val::T
    ex::Any
end

function WithValuePtr(val, ex)
    TODO((val,ex))
end
function WithValuePtr(val, ex::Expr)
    i = something(findfirst(a -> a===val, ex.args))
    return WithValuePtr(value_pointer(ex.args[i]), val, ex)
end
function WithValuePtr(val, ex::Core.PhiNode)
    i = something(findfirst(a -> a===val, ex.values))
    return WithValuePtr(value_pointer(ex.values[i]), val, ex)
end
function WithValuePtr(val, ex::Union{Core.UpsilonNode,Core.PiNode,Core.ReturnNode})
    return WithValuePtr(value_pointer(ex.val), val, ex)
end


function get_stencil_name(ex::Expr)
    if Base.isexpr(ex, :call)
        # g = ex.args[1]
        # fn = g isa GlobalRef ? unwrap(g) : g
        # if fn isa Core.IntrinsicFunction
        #     return string("jl_", Symbol(fn))
        # else
            return "ast_call"
        # end
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


requires_value_pointer(::Any) = true
# We can address inputs of these kinds without value_pointer shenanigans
requires_value_pointer(::Boxable) = false
requires_value_pointer(::UndefInput) = false
requires_value_pointer(::Core.Argument) = false
requires_value_pointer(::Core.SSAValue) = false


function emitpushes!(mc::MachineCode, ctx::Context, ex, inputs::Vector{Any})
    nroots = ngcroots(ex)
    ninputs = length(inputs)
    ntmps = ninputs-nroots
    ctx.i = 0
    for input in inputs
        ctx.i += 1
        continuation = if ctx.i < length(inputs)
            pointer(mc.buf, mc.inputs_stencil_starts[ctx.ip][ctx.i+1])
        else
            pointer(mc.buf, mc.stencil_starts[ctx.ip])
        end
        emitpush!(mc, ctx, continuation, input)
    end
end


function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Boxable)
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_X", input)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
end
function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Ptr{UInt8})
    # special case jl_box_and_push_uint8pointer
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_P", input)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
end
function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        @nospecialize(input::Ptr))
    # special case for jl_box_and_push_voidpointer
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_P", Ptr{Cvoid}(input))
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
end
function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        input::UndefInput)
    # C_NULL != jl_box_voidpointer(NULL)
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_P", Ptr{Cvoid}(C_NULL))
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
end
function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Core.Argument)
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_N", Cint(input.n))
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
end
function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Core.SSAValue)
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_ID", Cint(input.id))
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
end
function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{ExprOf})
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_P", input.ptr)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
end
function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        @nospecialize(input::WithValuePtr{<:Any}))
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_P", input.ptr)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
end
function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{GlobalRef})
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_GR", input.ptr)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
end
function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{QuoteNode})
    st, bvec, _ = get_push_stencil(input)
    stencil_start = mc.inputs_stencil_starts[ctx.ip][ctx.i]
    copyto!(mc.buf, stencil_start, bvec, 1, length(bvec))
    patch!(mc.buf, stencil_start, st.code, "_JIT_IP", Cint(ctx.ip))
    patch!(mc.buf, stencil_start, st.code, "_JIT_I", Cint(ctx.i))
    patch!(mc.buf, stencil_start, st.code, "_JIT_Q", input.ptr)
    patch!(mc.buf, stencil_start, st.code, "_JIT_CONT", continuation)
end
function emitpush!(mc::MachineCode, ctx::Context, continuation::Ptr,
        input::NativeSymArg)
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
    continuation = get_continuation(mc, ip+1)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::GlobalRef)
    st, bvec, _ = get_stencil(ex)
    continuation = get_continuation(mc, ip+1)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::Core.EnterNode)
    st, bvec, _ = get_stencil(ex)
    catch_ip = ex.catch_dest
    leave_ip = catch_ip - 1
    call = get_continuation(mc, ip+1)
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
    continuation2 = get_continuation(mc, ip+1)
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
    continuation = get_continuation(mc, ip+1)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_EDGES_FROM", pointer(ex.edges))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP_BLOCKEND", Cint(ip_blockend))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NEDGES", nedges)
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::Core.PhiCNode)
    st, bvec, _ = get_stencil(ex)
    continuation = get_continuation(mc, ip+1)
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
    continuation = get_continuation(mc, ip+1)
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
    continuation = get_continuation(mc, ip+1)
    copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET_IP", Cint(ret_ip))
    patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    return
end
function emitcode!(mc, ip, ex::Expr)
    st, bvec, _ = get_stencil(ex)
    if Base.isexpr(ex, :call)
        # g = ex.args[1]
        # fn = g isa GlobalRef ? unwrap(g) : g
        # if fn isa Core.IntrinsicFunction
        #     nargs = length(ex.args)-1
        #     name = string("jl_", Symbol(fn))
        #     st, bvec, _ = get(STENCILS[], name) do
        #         error("don't know how to handle intrinsic $name")
        #     end
        #     continuation = get_continuation(mc, ip+1)
        #     copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        #     patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        #     patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
        # elseif iscallable(fn) || g isa Core.SSAValue
            nargs = length(ex.args)
            continuation = get_continuation(mc, ip+1)
            copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS", UInt32(nargs))
            patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
        # else
        #     TODO(fn)
        # end
    elseif Base.isexpr(ex, :invoke)
        mi, g = ex.args[1], ex.args[2]
        @assert mi isa Core.MethodInstance || mi isa Base.CodeInstance
        nargs = length(ex.args)
        continuation = get_continuation(mc, ip+1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS", UInt32(nargs))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :new)
        nargs = length(ex.args)
        continuation = get_continuation(mc, ip+1)
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
        continuation = get_continuation(mc, ip+1)
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
        continuation = get_continuation(mc, ip+1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :leave)
        hand_n_leave = count(ex.args) do a
            a !== nothing && mc.codeinfo.code[a.id] !== nothing
        end
        continuation = get_continuation(mc, ip+1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_HAND_N_LEAVE", Cint(hand_n_leave))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :pop_exception)
        continuation = get_continuation(mc, ip+1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :the_exception)
        ret = pointer(mc.ssas, ip)
        continuation = get_continuation(mc, ip+1)
        copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip))
        patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", continuation)
    elseif Base.isexpr(ex, :throw_undef_if_not)
        continuation = get_continuation(mc, ip+1)
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
            @assert all(s -> s isa Union{Core.SSAValue,Core.Argument}, ex.args)
        end
        continuation = get_continuation(mc, ip+1)
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
