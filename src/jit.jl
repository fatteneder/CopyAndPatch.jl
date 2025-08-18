function jit(@nospecialize(fn), @nospecialize(argtypes::Tuple))
    optimize = true
    # TODO: utilize our interpreter to profit from transform_ir_for_cpjit
    codeinfo, rettype = only(Base.code_typed(fn, argtypes; optimize))
    return jit(codeinfo, fn, rettype, argtypes)
end
function jit(codeinfo::Core.CodeInfo, @nospecialize(fn), @nospecialize(rettype), @nospecialize(argtypes))
    ctx = Context(codeinfo)
    # compute total number of bytes and stencil offsets
    # abi stencil is handled separately from the AST instructions
    st = get_stencil("abi")
    code_size = length(st.md.code.body)
    instr_stencil_starts = zeros(Int64, ctx.nssas)
    load_stencil_starts = Vector{Vector{Int64}}(undef, ctx.nssas)
    store_stencil_starts = Dict{Int64, Int64}() # ip -> start
    for (ip, ex) in enumerate(codeinfo.code)
        select_stencils!(ctx, ex, ip)
        load_stencils = ctx.load_stencils[ip]
        load_stencil_starts[ip] = zeros(Int64, length(load_stencils))
        for (il, st) in enumerate(load_stencils)
            load_stencil_starts[ip][il] = 1 + code_size
            code_size += length(st.md.code.body)
        end
        st = ctx.instr_stencils[ip]
        instr_stencil_starts[ip] = 1 + code_size
        code_size += length(st.md.code.body)
        if haskey(ctx.store_stencils, ip)
            st = ctx.store_stencils[ip]
            store_stencil_starts[ip] = 1 + code_size
            code_size += length(st.md.code.body)
        end
    end

    mc = MachineCode(
        code_size, fn, rettype, argtypes, codeinfo,
        instr_stencil_starts, load_stencil_starts, store_stencil_starts,
        ctx.instr_stencils, ctx.load_stencils, ctx.store_stencils
    )

    emit_abi!(mc, ctx)
    for (ip, ex) in enumerate(codeinfo.code)
        emit_loads!(mc, ctx, ex, ip)
        emit_instr!(mc, ctx, ex, ip)
        emit_store!(mc, ctx, ex, ip)
    end
    return mc
end


mutable struct ContextForeigncall
    cif::Ffi_cif
    cargs_starts::Vector{Int64}
    sz_cargs::Int64
end
mutable struct Context
    codeinfo::Core.CodeInfo
    ip::Int64 # current instruction pointer, 1-based
    il::Int64 # current load instruction pointer, 1-based
    nssas::Int64 # number of ssa statements
    # filled by select_stencils!
    ntmps::Int64 # max number of tmp variables across all stencils
    nroots::Int64 # max number of root variables across all stencils
    ncargs::Int64 # max number of carg (:foreigncall) variables across all stencils
    inputs::Vector{Vector{Any}}
    roots::Vector{Vector{Any}}
    load_stencils::Vector{Vector{StencilData}}
    instr_stencils::Vector{StencilData}
    store_stencils::Dict{Int64, StencilData} # ip -> stencil
    ctxs_foreigncall::Dict{Int64, ContextForeigncall}
end
function Context(codeinfo::Core.CodeInfo)
    nssas = length(codeinfo.code)
    ip, il, ntmps, nroots, ncargs = 0, 0, 0, 0, 0
    inputs = Vector{Any}[ Any[] for _ in 1:nssas ]
    roots = Vector{Any}[ Any[] for _ in 1:nssas ]
    load_stencils = Vector{StencilData}[ StencilData[] for _ in 1:nssas ]
    instr_stencils = Vector{StencilData}(undef, nssas)
    store_stencils = Dict{Int64, StencilData}()
    ctxs_foreigncall = Dict{Int64, ContextForeigncall}()
    return Context(
        codeinfo, ip, il, nssas, ntmps, nroots, ncargs,
        inputs, roots, load_stencils, instr_stencils, store_stencils,
        ctxs_foreigncall
    )
end


# decorator-like type to capture value_pointer(val) where val is rooted *in* ex
# said differently: can take a pointer to an immutable object contained in ex
struct WithValuePtr{T}
    ptr::Ptr{Cvoid}
    val::T
    ex::Any
end


function Base.show(io::IO, ::MIME"text/plain", @nospecialize(p::WithValuePtr))
    print(io, "$(typeof(p))($(p.val) in $(p.ex))")
    return
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
    for (il, input) in enumerate(ctx.inputs[ctx.ip])
        ctx.il = il
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
        ctx.inputs[ctx.ip][ctx.il] = input
    end
    return
end


function get_stencil(name::String)
    if !haskey(STENCILS[], name)
        error("no stencil named '$name'")
    end
    return STENCILS[][name]
end


stencil_name_load_generic(arg::Any) = "jl_push_any"
stencil_name_load_generic(arg::Core.Argument) = "jl_push_slot"
stencil_name_load_generic(arg::Core.SSAValue) = "jl_push_ssa"
stencil_name_load_generic(arg::Core.Const) = get_stencil_name(c.val)
function stencil_name_load_generic(arg::Boxable)
    typename = lowercase(string(typeof(arg)))
    return "jl_box_and_push_$typename"
end
stencil_name_load_generic(arg::GlobalRef) = "jl_eval_and_push_globalref"
stencil_name_load_generic(arg::QuoteNode) = "jl_push_quotenode_value"
stencil_name_load_generic(arg::Ptr{UInt8}) = "jl_box_uint8pointer"
stencil_name_load_generic(@nospecialize(arg::Ptr)) = "jl_box_and_push_voidpointer"
stencil_name_load_generic(@nospecialize(arg::WithValuePtr)) = stencil_name_load_generic(arg.val)
function stencil_name_load_generic(arg::NativeSymArg)
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
    name = stencil_name_load_generic(ex)
    if !haskey(STENCILS[], name)
        error("no stencil named '$name' found for expression $ex")
    end
    return STENCILS[][name]
end


stencil_name_foreigncall_load_store(::Type{Bool}, kind::String) = "ast_foreigncall_$(kind)_bool"
stencil_name_foreigncall_load_store(::Type{Int8}, kind::String) = "ast_foreigncall_$(kind)_int8" # Cchar
stencil_name_foreigncall_load_store(::Type{UInt8}, kind::String) = "ast_foreigncall_$(kind)_uint8" # Cuchar
stencil_name_foreigncall_load_store(::Type{Int16}, kind::String) = "ast_foreigncall_$(kind)_int16" # Cshort
stencil_name_foreigncall_load_store(::Type{UInt16}, kind::String) = "ast_foreigncall_$(kind)_uint16" # Cushort
stencil_name_foreigncall_load_store(::Type{Int32}, kind::String) = "ast_foreigncall_$(kind)_int32" # Cint
stencil_name_foreigncall_load_store(::Type{UInt32}, kind::String) = "ast_foreigncall_$(kind)_uint32" # Cuint
stencil_name_foreigncall_load_store(::Type{Int64}, kind::String) = "ast_foreigncall_$(kind)_int64" # Clong
stencil_name_foreigncall_load_store(::Type{UInt64}, kind::String) = "ast_foreigncall_$(kind)_uint64" # Culong
stencil_name_foreigncall_load_store(::Type{Float32}, kind::String) = "ast_foreigncall_$(kind)_float32" # Cfloat
stencil_name_foreigncall_load_store(::Type{Float64}, kind::String) = "ast_foreigncall_$(kind)_float64" # Cdouble
stencil_name_foreigncall_load_store(::Type{Ptr{UInt8}}, kind::String) = "ast_foreigncall_$(kind)_uint8pointer" # Ptr{Cuchar}
stencil_name_foreigncall_load_store(::Type{<:Ptr}, kind::String) = "ast_foreigncall_$(kind)_voidpointer" # Ptr{Cvoid}
function stencil_name_foreigncall_load_store(t::Type{<:Ref}, kind::String)
    return if kind == "store"
        "ast_foreigncall_$(kind)_any"
    else
        stencil_name_foreigncall_load_store(Ptr, kind)
    end
end
function stencil_name_foreigncall_load_store(t::Type{<:Any}, kind::String)
    return if isconcretetype(t)
        "ast_foreigncall_$(kind)_concretetype"
    else
        "ast_foreigncall_$(kind)_any"
    end
end
function select_load_store_foreigncall_stencil(ty, kind)
    name = stencil_name_foreigncall_load_store(ty, kind)
    if !haskey(STENCILS[], name)
        error("no stencil named '$name' found for type $ty")
    end
    return STENCILS[][name]
end
select_load_foreigncall_stencil(arg) = select_load_store_foreigncall_stencil(arg, "load")
select_store_foreigncall_stencil(arg) = select_load_store_foreigncall_stencil(arg, "store")


function emit_abi!(mc::MachineCode, ctx::Context)
    st = get_stencil("abi")
    copyto!(mc.buf, 1, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, 1, st.md.code, "_JIT_NARGS", Cint(length(mc.argtypes)), optional = true)
    patch!(mc.buf, 1, st.md.code, "_JIT_NSSAS", Cint(length(mc.codeinfo.code)))
    patch!(mc.buf, 1, st.md.code, "_JIT_NTMPS", Cint(ctx.ntmps))
    patch!(mc.buf, 1, st.md.code, "_JIT_NGCROOTS", Cint(ctx.nroots))
    patch!(mc.buf, 1, st.md.code, "_JIT_NCARGS", Cint(ctx.ncargs))
    next = if length(mc.load_stencils_starts) > 0 && length(first(mc.load_stencils_starts)) > 0
        first(first(mc.load_stencils_starts))
    else
        first(mc.instr_stencil_starts)
    end
    patch!(mc.buf, 1, st.md.code, "_JIT_STENCIL", pointer(mc.buf, next))
    return
end


function emit_loads_generic!(mc::MachineCode, ctx::Context)
    ctx.il = 0
    for input in ctx.inputs[ctx.ip]
        ctx.il += 1
        continuation = if ctx.il < length(ctx.load_stencils[ctx.ip])
            get_continuation_load(mc, ctx.ip, ctx.il + 1)
        else
            get_continuation_instr(mc, ctx.ip)
        end
        emit_load_generic!(mc, ctx, continuation, input)
    end
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Boxable
    )
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_X", input)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Ptr{UInt8}
    )
    # special case jl_box_and_push_uint8pointer
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", input)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        @nospecialize(input::Ptr)
    )
    # special case for jl_box_and_push_voidpointer
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", Ptr{Cvoid}(input))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::UndefInput
    )
    # C_NULL != jl_box_voidpointer(NULL)
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", Ptr{Cvoid}(C_NULL))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Core.Argument
    )
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_N", Cint(input.n))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::Core.SSAValue
    )
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_ID", Cint(input.id))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{ExprOf}
    )
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", input.ptr)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        @nospecialize(input::WithValuePtr{<:Any})
    )
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_P", input.ptr)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{GlobalRef}
    )
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_GR", input.ptr)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::WithValuePtr{QuoteNode}
    )
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_Q", input.ptr)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_CONT", continuation)
    return
end
function emit_load_generic!(
        mc::MachineCode, ctx::Context, continuation::Ptr,
        input::NativeSymArg
    )
    st = ctx.load_stencils[ctx.ip][ctx.il]
    stencil_start = mc.load_stencils_starts[ctx.ip][ctx.il]
    copyto!(mc.buf, stencil_start, st.bvec, 1, length(st.bvec))
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, stencil_start, st.md.code, "_JIT_I", Cint(ctx.il))
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


# The codegen interface to use
function select_stencils!(ctx::Context, ex, ip::Int64)
    ctx.ip = ip
    extract_inputs!(ctx, ex)
    select_stencils!(ctx, ex)
    ctx.ntmps = max(ctx.ntmps, length(ctx.inputs[ctx.ip]))
    ctx.nroots = max(ctx.nroots, length(ctx.roots[ctx.ip]))
    if Base.isexpr(ex, :foreigncall)
        # setup ContextForeigncall and update ctx.ncargs
        rettype = foreigncall_rettype(ex)
        argtypes = foreigncall_argtypes(ex)
        for at in argtypes
            isconcretetype(at) || continue
            for il in 1:fieldcount(at)
                ty = fieldtype(at, il)
                if ty isa Union
                    TODO("can't pass non-isbitstypes 'by-value', cf. issue #46786 and stencils/mwe_union.c")
                end
            end
        end
        conv = foreigncall_conv(ex)
        @assert conv isa QuoteNode
        @assert conv.value === :ccall || first(conv.value) === :ccall
        nreq = foreigncall_nreq(ex)
        @assert length(argtypes) ≥ nreq
        nargs = foreigncall_nargs(ex)
        # offsets for F->cargs usage in ast_foreigncall.c:
        # F->cargs[0:nargs-1] is the cargs array for ffi_call
        # F->cargs[nargs] is the return value
        # F->cargs[nargs + 1:2*nargs] is the memory to which elements of F->cargs[0:nargs-1] point
        n_cargs = 2 * nargs + 1
        cargs_starts = Vector{Int64}(undef, n_cargs)
        sz_ptr = sizeof(Ptr{Cvoid})
        sz_cargs = 0
        for i in 1:nargs
            at = argtypes[i]
            cargs_starts[i] = 1 + sz_cargs ÷ sz_ptr
            sz_cargs += sz_ptr
        end
        sz = Base.LLT_ALIGN(ffi_sizeof_rettyp(rettype), sz_ptr)
        cargs_starts[nargs + 1] = 1 + sz_cargs ÷ sz_ptr
        sz_cargs += sz
        for i in 1:nargs
            at = argtypes[i]
            cargs_starts[nargs + 1 + i] = 1 + sz_cargs ÷ sz_ptr
            sz = Base.LLT_ALIGN(ffi_sizeof_argtype(at), sz_ptr)
            sz_cargs += sz
        end
        cif = Ffi_cif(rettype, tuple(argtypes...))
        ctxf = ContextForeigncall(cif, cargs_starts, sz_cargs)
        ctx.ctxs_foreigncall[ip] = ctxf
        # TODO Replace ctx.ncargs with sz_cargs
        ctx.ncargs = max(ctx.ncargs, sz_cargs ÷ sz_ptr)
    end
    return
end
function emit_loads!(mc::MachineCode, ctx::Context, ex, ip::Int64)
    ctx.ip = ip
    emit_loads!(mc, ctx, ex)
    return
end
function emit_instr!(mc::MachineCode, ctx::Context, ex, ip::Int64)
    ctx.ip = ip
    emit_instr!(mc, ctx, ex)
    return
end
function emit_store!(mc::MachineCode, ctx::Context, ex, ip::Int64)
    ctx.ip = ip
    if haskey(ctx.store_stencils, ip)
        emit_store!(mc, ctx, ex)
    end
    return
end


# The codegen interface to implement for AST elements
select_stencils!(ctx::Context, ex::Any) = TODO("select_stencils! for $ex")
emit_loads!(mc::MachineCode, ctx::Context, ex::Any) = TODO("emit_loads! for $ex")
emit_instr!(mc::MachineCode, ctx::Context, ex::Any) = TODO("emit_instr! for $ex")
emit_store!(mc::MachineCode, ctx::Context, ex::Any) = nothing # optional


# Nothing
function select_stencils!(ctx::Context, ex::Nothing)
    @assert length(ctx.inputs[ctx.ip]) == 0
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_goto")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Nothing) = nothing
function emit_instr!(mc::MachineCode, ctx::Context, ex::Nothing)
    st = ctx.instr_stencils[ctx.ip]
    continuation = get_continuation(mc, ctx.ip + 1)
    copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# GlobalRef
function select_stencils!(ctx::Context, ex::GlobalRef)
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
    copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Core.EnterNode
function select_stencils!(ctx::Context, ex::Core.EnterNode)
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
    copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CALL", call)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT_LEAVE", continuation_leave)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT_CATCH", continuation_catch)
    return
end


# Core.ReturnNode
function select_stencils!(ctx::Context, ex::Core.ReturnNode)
    @assert length(ctx.inputs[ctx.ip]) ≤ 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_returnnode")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.ReturnNode) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.ReturnNode)
    # TODO :unreachable nodes are also of type Core.ReturnNode. Anything to do here?
    st = ctx.instr_stencils[ctx.ip]
    copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    return
end


# Core.GotoNode
function select_stencils!(ctx::Context, ex::Core.GotoNode)
    @assert length(ctx.inputs[ctx.ip]) == 0
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_goto")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.GotoNode) = nothing
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.GotoNode)
    st = ctx.instr_stencils[ctx.ip]
    continuation = get_continuation(mc, ex.label)
    copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Core.GotoIfNot
function select_stencils!(ctx::Context, ex::Core.GotoIfNot)
    @assert length(ctx.inputs[ctx.ip]) == 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_gotoifnot")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.GotoIfNot) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.GotoIfNot)
    st = ctx.instr_stencils[ctx.ip]
    copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    continuation1 = get_continuation(mc, ex.dest)
    continuation2 = get_continuation(mc, ctx.ip + 1)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT1", continuation1)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT2", continuation2)
    return
end


# Core.PhiNode
function select_stencils!(ctx::Context, ex::Core.PhiNode)
    @assert length(ctx.inputs[ctx.ip]) ≥ 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_phinode")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.PhiNode) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.PhiNode)
    st = ctx.instr_stencils[ctx.ip]
    copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
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
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_EDGES_FROM", pointer(ex.edges))
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP_BLOCKEND", Cint(ip_blockend))
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_NEDGES", nedges)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Core.PhiCNode
function select_stencils!(ctx::Context, ex::Core.PhiCNode)
    # @assert length(ctx.inputs[ctx.ip]) ≥ 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_phicnode")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.PhiCNode) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.PhiCNode)
    st = ctx.instr_stencils[ctx.ip]
    continuation = get_continuation(mc, ctx.ip + 1)
    copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Core.PiNode
function select_stencils!(ctx::Context, ex::Core.PiNode)
    @assert length(ctx.inputs[ctx.ip]) == 1
    ctx.load_stencils[ctx.ip] = select_load_stencil_generic.(ctx.inputs[ctx.ip])
    ctx.instr_stencils[ctx.ip] = get_stencil("ast_pinode")
    return
end
emit_loads!(mc::MachineCode, ctx::Context, ex::Core.PiNode) = emit_loads_generic!(mc, ctx)
function emit_instr!(mc::MachineCode, ctx::Context, ex::Core.PiNode)
    # https://docs.julialang.org/en/v1/devdocs/ssair/#Phi-nodes-and-Pi-nodes
    # PiNodes are ignored in the interpreter, so ours also only copy values into F->ssas[ip-1]
    st = ctx.instr_stencils[ctx.ip]
    copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    continuation = get_continuation(mc, ctx.ip + 1)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


# Core.UpsilonNode
function select_stencils!(ctx::Context, ex::Core.UpsilonNode)
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
    copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_RET_IP", Cint(ret_ip))
    patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    return
end


foreigncall_rettype(ex::Expr) = ex.args[2]
foreigncall_argtypes(ex::Expr) = ex.args[3]
foreigncall_argtypes(ex::Expr, i::Integer) = ex.args[3][i]
foreigncall_nreq(ex::Expr) = ex.args[4]
foreigncall_conv(ex::Expr) = ex.args[5]
foreigncall_args(ex::Expr) = ex.args[6:(5 + length(ex.args[3]))]
foreigncall_args(ex::Expr, i::Integer) = ex.args[6:(5 + length(ex.args[3]))][i]
foreigncall_nargs(ex::Expr) = length(6:(5 + length(ex.args[3])))

# Expr
function select_stencils!(ctx::Context, ex::Expr)
    if Base.isexpr(ex, :foreigncall)
        # special handling of :foreigncall f arg
        @assert length(ctx.inputs[ctx.ip]) ≥ 1
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
    if Base.isexpr(ex, :foreigncall)
        # select load stencils to unbox F->tmps[1:nargs] into F->cargs[0:nargs-1]
        nloads = length(ctx.inputs[ctx.ip]) # length of F->tmps
        nargs = foreigncall_nargs(ex)
        resize!(ctx.load_stencils[ctx.ip], nloads + nargs)
        for i in 1:nargs
            at = foreigncall_argtypes(ex, i)
            ctx.load_stencils[ctx.ip][nloads + i] = select_load_foreigncall_stencil(at)
        end
        # select store stencils to box the result F->cargs[nargs] into F->ssas[ip-1]
        rettype = foreigncall_rettype(ex)
        ctx.store_stencils[ctx.ip] = select_store_foreigncall_stencil(rettype)
    end
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
    elseif Base.isexpr(ex, :copyast); "ast_copyast"
    else TODO("Stencil not implemented yet:", ex) end
    # runic: on
    ctx.instr_stencils[ctx.ip] = get_stencil(name)
    return
end
function emit_loads!(mc::MachineCode, ctx::Context, ex::Expr)
    if Base.isexpr(ex, :copyast)
        # TODO julia/src/interpreter.c applys eval_value to copyast input first
        # eval_value handles: SSAValue, Argument/Slot, QuoteNode, GlobalRef, Symbol,
        # which should be covered by emit_loads_generic
        # the remaining cases are as follows and would require a different solution:
        # PiNode, jl_call_sym, jl_invoke_sym, jl_invoke_modify_sym, jl_isdefined_sym,
        # jl_throw_undef_if_not_sym, jl_new_sym, jl_splatnew_sym, jl_new_opaque_closure_sym,
        # jl_static_parameter_sym, jl_copy_ast_sym, jl_exc_sym, jl_boundscheck_sym,
        # jl_meta_sym, jl_coverageeffect_sym, jl_inbounds_sym, jl_loopinfo_sym,
        # jl_aliasscope_sym, jl_popaliasscope_sym, jl_inline_sym, jl_noinline_sym,
        # jl_gc_preserve_begin_sym, jl_gc_preserve_end_sym, jl_method_sym
        arg = only(ex.args)
        if arg isa Expr || arg isa Core.PiNode
            TODO("ast_copyast does not handle $(ex.args) yet")
        end
    end
    if Base.isexpr(ex, :foreigncall)
        emit_loads_generic!(mc, ctx)
        ntmps = length(ctx.inputs[ctx.ip]) # length of F->tmps
        nargs = foreigncall_nargs(ex)
        for i in 1:nargs
            il = i + ntmps # index load stencil
            argtype = foreigncall_argtypes(ex, i)
            continuation = if i < nargs
                get_continuation_load(mc, ctx.ip, il + 1)
            else
                get_continuation_instr(mc, ctx.ip)
            end
            st = ctx.load_stencils[ctx.ip][il]
            start = mc.load_stencils_starts[ctx.ip][il]
            ctxf = ctx.ctxs_foreigncall[ctx.ip]
            # mem addr in F->cargs, nargs to skip ffi arg vec, + 1 to skip ret val
            i_mem = ctxf.cargs_starts[nargs + 1 + i]
            copyto!(mc.buf, start, st.bvec, 1, length(st.bvec))
            patch!(mc.buf, start, st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
            patch!(mc.buf, start, st.md.code, "_JIT_I_TMPS", Cint(i + 1)) # + 1 to skip f
            patch!(mc.buf, start, st.md.code, "_JIT_I_CARGS", Cint(i))
            patch!(mc.buf, start, st.md.code, "_JIT_I_MEM", Cint(i_mem), optional = true)
            patch!(mc.buf, start, st.md.code, "_JIT_CONT", continuation)
            name = get_name(st)
            if name == "ast_foreigncall_load_concretetype"
                argtype_ptr = pointer_from_objref(argtype)
                patch!(mc.buf, start, st.md.code, "_JIT_TY", argtype_ptr)
            end
        end
    else
        emit_loads_generic!(mc, ctx)
    end
    return
end
function emit_instr!(mc::MachineCode, ctx::Context, ex::Expr)
    st = ctx.instr_stencils[ctx.ip]
    name = get_name(st)
    if name == "ast_call"
        nargs = length(ex.args)
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_NARGS", UInt32(nargs))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif name == "ast_invoke"
        mi, g = ex.args[1], ex.args[2]
        @assert mi isa Core.MethodInstance || mi isa Base.CodeInstance
        nargs = length(ex.args)
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_NARGS", UInt32(nargs))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif name == "ast_new"
        nargs = length(ex.args)
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_NARGS", UInt32(nargs))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif name == "ast_foreigncall"
        ctxf = ctx.ctxs_foreigncall[ctx.ip]
        cif = ctxf.cif
        push!(mc.gc_roots, cif)
        nargs = foreigncall_nargs(ex)
        i_retval = ctxf.cargs_starts[nargs + 1]
        continuation = get_continuation_store(mc, ctx.ip)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CIF", pointer(ctxf.cif))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_I_RETVAL", Cint(i_retval))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif name == "ast_boundscheck"
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif name == "ast_leave"
        hand_n_leave = count(ex.args) do a
            a !== nothing && mc.codeinfo.code[a.id] !== nothing
        end
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_HAND_N_LEAVE", Cint(hand_n_leave))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif name == "ast_pop_exception"
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif name == "ast_the_exception"
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif name == "ast_throw_undef_if_not"
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif name === "ast_copyast"
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    elseif any(
            n -> name == "ast_$n",
            (
                :meta, :coverageeffect, :inbounds, :loopinfo, :aliasscope, :popaliasscope,
                :inline, :noinline, :gc_preserve_begin, :gc_preserve_end,
            )
        )
        # TODO This is no longer holds on fatteneder/julia@cpjit-mmap-v3
        # if Base.isexpr(ex, :gc_preserve_begin)
        #     # :gc_preserve_begin is a no-op if everything is pushed to frame *F (which is GC rooted)
        #     @assert all(s -> s isa Union{Core.SSAValue, Core.Argument}, ex.args)
        # end
        continuation = get_continuation(mc, ctx.ip + 1)
        copyto!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
        patch!(mc.buf, mc.instr_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    else
        TODO(name)
    end
    return
end
function emit_store!(mc::MachineCode, ctx::Context, ex::Expr)
    st = ctx.store_stencils[ctx.ip]
    ctxf = ctx.ctxs_foreigncall[ctx.ip]
    nargs = foreigncall_nargs(ex)
    i_retval = ctxf.cargs_starts[nargs + 1]
    continuation = get_continuation(mc, ctx.ip + 1)
    copyto!(mc.buf, mc.store_stencil_starts[ctx.ip], st.bvec, 1, length(st.bvec))
    patch!(mc.buf, mc.store_stencil_starts[ctx.ip], st.md.code, "_JIT_IP", Cint(ctx.ip), optional = true)
    patch!(mc.buf, mc.store_stencil_starts[ctx.ip], st.md.code, "_JIT_I_RETVAL", Cint(i_retval))
    patch!(mc.buf, mc.store_stencil_starts[ctx.ip], st.md.code, "_JIT_CONT", continuation)
    name = get_name(st)
    if name == "ast_foreigncall_store_concretetype" || name == "ast_foreigncall_store_voidpointer"
        # rettype remains rooted in mc.codeinfo
        rettype = foreigncall_rettype(ex)
        rettype_ptr = pointer_from_objref(rettype)
        patch!(mc.buf, mc.store_stencil_starts[ctx.ip], st.md.code, "_JIT_TY", rettype_ptr)
    end
    return
end
