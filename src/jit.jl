const stencils = Dict{String,Any}()
const MAGICNR = 0x8070605040302010


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
            bvec_data = if !isempty(s.data.body)
                ByteVector(UInt8.(only(s.data.body)))
            else
                ByteVector(0)
            end
            patch_default_deps!(bvec, bvec_data, s)
            for h in s.code.relocations
                @assert h.kind == "R_X86_64_64"
                bvec[h.offset+1] = MAGICNR
            end
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
    patched = Hole[]
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
        push!(patched, h)
    end
    filter!(holes) do h
        !(h in patched)
    end
end


function jit(@nospecialize(fn::Function), @nospecialize(args))

    # this here does the linking of all non-copy-patched parts
    # this includes setting up the data part too, which is important because below
    # we separate code and data parts in memory
    init_stencils()

    optimize = true
    codeinfo, rettype = only(code_typed(fn, args; optimize))
    argtypes = length(codeinfo.slottypes) > 0 ? Tuple(codeinfo.slottypes[2:end]) : ()

    # @show codeinfo
    # @show propertynames(codeinfo)
    # @show codeinfo.code
    # @show codeinfo.slottypes
    # @show codeinfo.ssavaluetypes
    # @show propertynames(codeinfo)

    nslots = length(codeinfo.slottypes)
    nssas = length(codeinfo.ssavaluetypes)
    # We use twice the number of slots here so that we can add another indirection layer
    # for faster setup of slots when calling later. This is similar to how its done for ffi_call.
    slots = Ptr{UInt64}[ C_NULL for _ in 1:2*nslots ]
    # TODO we use this assumption to save return values into ssa array
    @assert nssas == length(codeinfo.code)
    ssas = Ptr{UInt64}[ C_NULL for _ in 1:nssas ]
    used_rets = find_used(codeinfo)
    static_prms = Ptr{UInt64}[]

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
    # TODO If we store stencil_starts and codeinfo.code here then
    # we can later relocate the stencils with statements in code_native
    mc = MachineCode(code_size, rettype, argtypes)
    memory, gc_roots = mc.buf, mc.gc_roots
    push!(gc_roots, slots, ssas, static_prms)
    mc.stencil_starts = stencil_starts
    mc.codeinfo = codeinfo
    @show stencil_starts
    # bvec_code = view(mc.buf, 1:code_size)
    # bvec_data = view(mc.buf, code_size+1:code_size+data_size)
    for (ip,ex) in enumerate(codeinfo.code)
        emitcode!(memory, stencil_starts, ip, slots, ssas, static_prms, gc_roots, used_rets, ex)
    end

    return mc
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
            return stencils["ast_call"]
        else
            TODO(fn)
        end
    elseif isexpr(ex, :invoke)
        return stencils["ast_invoke"]
    elseif isexpr(ex, :new)
        return stencils["ast_new"]
    elseif isexpr(ex, :foreigncall)
        return stencils["ast_foreigncall"]
    else
        TODO("Stencil not implemented yet:", ex)
    end
end
get_stencil(ex::Core.ReturnNode) = stencils["ast_returnnode"]
get_stencil(ex::Core.GotoIfNot)  = stencils["ast_gotoifnot"]
get_stencil(ex::Core.GotoNode)   = stencils["ast_goto"]
get_stencil(ex::Core.PhiNode)    = stencils["ast_phinode"]
get_stencil(ex::Nothing)         = stencils["ast_goto"]


# TODO About box: From https://docs.julialang.org/en/v1/devdocs/object/
#   > A value may be stored "unboxed" in many circumstances
#     (just the data, without the metadata, and possibly not even stored but
#     just kept in registers), so it is unsafe to assume that the address of
#     a box is a unique identifier.
#     ...
#   > Note that modification of a jl_value_t pointer in memory is permitted
#     only if the object is mutable. Otherwise, modification of the value may
#     corrupt the program and the result will be undefined.
# Boxed stuff should be irrelevant too iff they have a stable memory address.
# TODO Need to collect the a's which need to be GC.@preserved when their pointers are used.
# - Anything to which we apply pointer_from_objref or pointer needs to be preserved when used.
# - Also slots and ssas need to be kept alive till the function is finished.
# - What about boxed stuff?
function box_arg(a, slots, ssas, static_prms)
    if a isa Core.Argument
        return pointer(slots, a.n)
    elseif a isa Core.SSAValue
        return pointer(ssas, a.id)
    else
        if a isa String
            push!(static_prms, pointer_from_objref(a))
        elseif a isa Number
            push!(static_prms, box(a))
        elseif a isa Type
            push!(static_prms, pointer_from_objref(a))
        elseif a isa GlobalRef
            # do it similar to src/interpreter.c:jl_eval_globalref
            p = @ccall jl_get_globalref_value(a::Any)::Ptr{Cvoid}
            p === C_NULL && throw(UndefVarError(a.name,a.mod))
            push!(static_prms, p)
        elseif typeof(a) <: Boxable
            push!(static_prms, box(a))
        elseif a isa MethodInstance
            push!(static_prms, pointer_from_objref(a))
        elseif a isa Nothing
            push!(static_prms, dlsym(libjulia[], :jl_nothing))
        elseif a isa Tuple
            push!(static_prms, value_pointer(a))
            @show a, static_prms[end]
        else
            TODO(a)
        end
        return pointer(static_prms, length(static_prms))
    end
end
function box_args(ex_args::AbstractVector, slots, ssas, static_prms)
    # TODO Need to cast to Ptr{UInt64} here?
    # return Ptr{Ptr{Cvoid}}[ box_arg(a, slots, ssas) for a in ex_args ]
    return Ptr{Cvoid}[ box_arg(a, slots, ssas, static_prms) for a in ex_args ]
end


# Based on base/compiler/ssair/ir.jl
# JuliaInterpreter.jl implements its own version of scan_ssa_use!, not sure why though.
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
emitcode!(memory, stencil_starts, ip, slots, ssas, preserve, used_rets, ex) = TODO(typeof(ex))
function emitcode!(memory, stencil_starts, ip, slots, ssas, static_prms, preserve, used_rets, ex::Nothing)
    st, bvec, _ = stencils["ast_goto"]
    copyto!(memory, stencil_starts[ip], bvec, 1, length(bvec))
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_IP",   ip)
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CONT", pointer(memory, stencil_starts[ip+1]))
end
function emitcode!(memory, stencil_starts, ip, slots, ssas, static_prms, preserve, used_rets, ex::Core.ReturnNode)
    st, bvec, _ = stencils["ast_returnnode"]
    retbox = isdefined(ex,:val) ? box_arg(ex.val, slots, ssas, static_prms) : C_NULL
    copyto!(memory, stencil_starts[ip], bvec, 1, length(bvec))
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RET", retbox)
end
function emitcode!(memory, stencil_starts, ip, slots, ssas, static_prms, preserve, used_rets, ex::Core.GotoNode)
    st, bvec, _ = stencils["ast_goto"]
    copyto!(memory, stencil_starts[ip], bvec, 1, length(bvec))
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_IP",   ip)
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CONT", pointer(memory, stencil_starts[ex.label]))
end
function emitcode!(memory, stencil_starts, ip, slots, ssas, static_prms, preserve, used_rets, ex::Core.GotoIfNot)
    st, bvec, _ = stencils["ast_gotoifnot"]
    copyto!(memory, stencil_starts[ip], bvec, 1, length(bvec))
    test = pointer(ssas, ex.cond.id) # TODO Can this also be a slot?
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_IP",    ip)
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_TEST",  test)
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CONT1", pointer(memory, stencil_starts[ex.dest]))
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CONT2", pointer(memory, stencil_starts[ip+1]))
end
function emitcode!(memory, stencil_starts, ip, slots, ssas, static_prms, preserve, used_rets, ex::Core.PhiNode)
    st, bvec, _ = stencils["ast_phinode"]
    copyto!(memory, stencil_starts[ip], bvec, 1, length(bvec))
    nedges = length(ex.edges)
    append!(preserve, ex.edges)
    vals_boxes = box_args(ex.values, slots, ssas, static_prms)
    append!(preserve, vals_boxes)
    retbox = ip in used_rets ? pointer(ssas, ip) : C_NULL
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_EDGES",   pointer(ex.edges))
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_IP",      ip)
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_NEDGES",  nedges)
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RET",     retbox)
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RETUSED", Cint(ip in used_rets))
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_VALS",    pointer(vals_boxes))
    patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CONT",    pointer(memory, stencil_starts[ip+1]))
end
function emitcode!(memory, stencil_starts, ip, slots, ssas, static_prms, preserve, used_rets, ex::Expr)
    if isexpr(ex, :call)
        g = ex.args[1]
        @assert g isa GlobalRef
        fn = unwrap(g)
        if fn isa Core.IntrinsicFunction
            ex_args = @view ex.args[2:end]
            nargs = length(ex_args)
            boxes = box_args(ex_args, slots, ssas, static_prms)
            append!(preserve, boxes)
            retbox = ip in used_rets ? pointer(ssas, ip) : C_NULL
            @assert retbox !== C_NULL
            name = string("jl_", Symbol(fn))
            st, bvec, bvec2 = get(stencils, name) do
                error("don't know how to handle intrinsic $name")
            end
            @assert length(bvec2) == 0
            copyto!(memory, stencil_starts[ip], bvec, 1, length(bvec))
            patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_IP", ip)
            for n in 1:nargs
                patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_A$n", boxes[n])
            end
            patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RET",  retbox)
            patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CONT", pointer(memory, stencil_starts[ip+1]))
        elseif iscallable(fn)
            nargs = length(ex.args)
            boxes = box_args(ex.args, slots, ssas, static_prms)
            append!(preserve, boxes)
            retbox = ip in used_rets ? pointer(ssas, ip) : C_NULL
            st, bvec, _ = stencils["ast_call"]
            copyto!(memory, stencil_starts[ip], bvec, 1, length(bvec))
            patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_ARGS",    pointer(boxes))
            patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_IP",      ip)
            patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_NARGS",   nargs)
            patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RET",     retbox)
            patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RETUSED", Int64(ip in used_rets))
            patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CONT",    pointer(memory, stencil_starts[ip+1]))
        else
            TODO(fn)
        end
    elseif isexpr(ex, :invoke)
        mi, g = ex.args[1], ex.args[2]
        @assert mi isa MethodInstance
        @assert g isa GlobalRef
        ex_args = ex.args
        boxes = box_args(ex_args, slots, ssas, static_prms)
        append!(preserve, boxes)
        nargs = length(boxes)
        retbox = ip in used_rets ? pointer(ssas, ip) : C_NULL
        st, bvec, bvec2 = stencils["ast_invoke"]
        copyto!(memory, stencil_starts[ip], bvec, 1, length(bvec))
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_ARGS",    pointer(boxes))
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_IP",      ip)
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_NARGS",   nargs)
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RET",     retbox)
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RETUSED", Cint(ip in used_rets))
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CONT",    pointer(memory, stencil_starts[ip+1]))
    elseif isexpr(ex, :new)
        ex_args = ex.args
        boxes = box_args(ex_args, slots, ssas, static_prms)
        append!(preserve, boxes)
        nargs = length(boxes)
        retbox = ip in used_rets ? pointer(ssas, ip) : C_NULL
        st, bvec, bvec2 = stencils["ast_new"]
        @assert length(bvec2) == 0
        copyto!(memory, stencil_starts[ip], bvec, 1, length(bvec))
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_ARGS",    pointer(boxes))
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_IP",      ip)
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_NARGS",   nargs)
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RET",     retbox)
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RETUSED", Cint(ip in used_rets))
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CONT",    pointer(memory, stencil_starts[ip+1]))
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
        boxes = box_args(args, slots, ssas, static_prms)
        append!(preserve, boxes)
        nargs = length(boxes)
        retbox = if ip in used_rets
            pointer(ssas, ip)
        else
            # ffi_call asks for an address for the return value,
            # and because clang optimizes our `int retused` away we can't just pass a NULL
            push!(static_prms, C_NULL)
            pointer(static_prms, length(static_prms))
        end
        # TODO Can we not move the allocation here into C? How can we teach the GC that
        # there is a new variable?
        retval = Ref{rettype}()
        ssas[ip] = Base.unsafe_convert(Ptr{Cvoid}, retval)
        push!(preserve, retval)
        cif = Ffi_cif(rettype, argtypes)
        st, bvec, bvec2 = stencils["ast_foreigncall"]
        @assert length(bvec2) == 0
        handle = dlopen(libname[])
        fptr = dlsym(handle, fname)
        copyto!(memory, stencil_starts[ip], bvec, 1, length(bvec))
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_IP",      ip)
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CIF",     pointer(cif))
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_F",       fptr)
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_ARGS",    pointer(boxes))
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_NARGS",   nargs)
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_RET",     retbox)
        patch!(memory, stencil_starts[ip]-1, st.code, "_JIT_CONT",    pointer(memory, stencil_starts[ip+1]))
    else
        TODO(ex.head)
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
        ioc = IOContext(io, stdout) # to kepp the colors!!
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
    rng = starts[i]:(i < nstarts ? starts[i+1] : length(mc.buf))
    stencil = view(mc.buf, rng)
    ex = mc.codeinfo.code[i]
    _code_native!(io, ex, stencil, i; syntax, color, hex_for_imm)
end
@inline function _code_native!(io::IO, ex, stencil, i;
                               syntax::Symbol=:intel, color::Bool=true, hex_for_imm::Bool=true)
    printstyled(io, i, ' ', ex, '\n', bold=true, color=:green)
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
    nheader = 0
    print_relocs = true
    menu = CopyAndPatchMenu(mc, syntax, hex_for_imm, options, 1, pagesize, pageoffset,
                            ip_col_width, ip_fmt, nheader, print_relocs, config)
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
    if menu.print_relocs
        # this is a hacky way to relocate the _JIT_* patches in the native code output
        # we are given formatted and colored native code of a patched stencil: code
        # we compute the native code of an unpatched stencil (only _JIT_* args are unpatched): unpatched_code
        # we compare code vs unpatched_code line by line, and every mismatch is a line where we patched
        stencilinfo, buf, _ = get_stencil(menu.mc.codeinfo.code[cursor])
        relocs = stencilinfo.code.relocations
        ex = menu.mc.codeinfo.code[cursor]
        # we use uncolored code_native output to ignore ansii color codes, needed for
        # correct computation of max line width
        _code_native!(ioc, ex, buf, cursor; syntax=menu.syntax, color=false, hex_for_imm=menu.hex_for_imm)
        unpatched_code = String(take!(io))
        _code_native!(ioc, menu.mc, cursor; syntax=menu.syntax, color=false, hex_for_imm=menu.hex_for_imm)
        uncolored_code = String(take!(io))
        max_w = maximum(split(uncolored_code,'\n')[2:end]) do line
            # ignore first line which contains the SSA expression
            ncodeunits(repr(line))
        end
        nreloc = 0
        for (i,(uc_line, line, up_line)) in enumerate(zip(eachline(IOBuffer(uncolored_code)),
                                                          eachline(IOBuffer(code)),
                                                          eachline(IOBuffer(unpatched_code))))
            w = length(uc_line)
            Δw = max_w - w
            print(ioc, line)
            if uc_line == up_line
                print(ioc, '\n')
            else
                nreloc += 1
                if nreloc <= length(relocs)
                    printstyled(ioc, ' '^Δw, "    # $(relocs[nreloc].symbol)\n", color=:light_blue)
                else
                    println(ioc)
                end
            end
        end
        if nreloc != length(relocs)
            s = SimpleLogger(ioc)
            with_logger(s) do
                println(ioc)
                @error "relocation is wrong, found $nreloc but expected $(length(relocs))"
            end
        end
        code = String(take!(io))
    end
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
       ip$('n'^(menu.ip_col_width-2)) | SSA
    """
end

function TerminalMenus.writeline(buf::IOBuffer, menu::CopyAndPatchMenu, idx::Int, iscursor::Bool)
    ioc = IOContext(buf, stdout)
    sidx = format(menu.ip_fmt, idx)
    if iscursor
        printstyled(ioc, sidx, " | ", menu.options[idx], bold=true, color=:green)
    else
        print(ioc, sidx, " | ", menu.options[idx])
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
