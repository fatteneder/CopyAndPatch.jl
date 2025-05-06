default_terminal() = REPL.LineEdit.terminal(Base.active_repl)


function code_native(
        mc::MachineCode;
        syntax::Symbol = :intel, interactive::Bool = false, color::Bool = true,
        hex_for_imm::Bool = true
    )
    if interactive
        menu = CopyAndPatchMenu(mc, syntax, hex_for_imm)
        term = default_terminal()
        cursor = 1
        print('\n', annotate_code_native(menu, cursor), '\n')
        TerminalMenus.request(term, menu; cursor)
    else
        code_native(stdout, mc; syntax, interactive, color, hex_for_imm)
    end
    return
end
function code_native(
        io::IO, mc::MachineCode;
        syntax::Symbol = :intel, interactive::Bool = false, color::Bool = true,
        hex_for_imm::Bool = true
    )
    tmp_io = IOBuffer()
    ioc = IOContext(tmp_io, stdout) # to keep the colors!!
    for ip in 0:length(mc.codeinfo.code) # 0 =^= abi stencil
        cpjit_code_native!(ioc, mc, ip; syntax, color, hex_for_imm)
    end
    println(io, String(take!(tmp_io)))
    return
end
function code_native(code::AbstractVector{UInt8}, kwargs...)
    io = IOBuffer()
    ioc = IOContext(io, stdout)
    code_native(ioc, code, kwargs...)
    print(String(take!(io)))
    return
end
function code_native(
        io::IO, code::AbstractVector{UInt8};
        syntax::Symbol = :intel, color::Bool = true, hex_for_imm::Bool = true
    )
    if syntax === :intel
        variant = 1
    elseif syntax === :att
        variant = 0
    else
        throw(ArgumentError("'syntax' must be either :intel or :att"))
    end
    codestr = join(Iterators.map(string, code), ' ')
    out, err = Pipe(), Pipe()
    # TODO src/disasm.cpp also exports a disassembler which is based on llvm-mc
    # jl_value_t *jl_dump_fptr_asm_impl(uint64_t fptr, char emit_mc, const char* asm_variant, const char *debuginfo, char binary)
    # maybe we can repurpose that to avoid the extra llvm-mc dependency?
    if hex_for_imm
        cmd = `llvm-mc --disassemble --output-asm-variant=$variant --print-imm-hex`
    else
        cmd = `llvm-mc --disassemble --output-asm-variant=$variant`
    end
    pipe = pipeline(cmd, stdout = out, stderr = err)
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
    return color ? InteractiveUtils.print_native(io, str_out) : print(io, str_out)
end


@inline function cpjit_code_native!(
        io::IO, title::String, buf::AbstractVector;
        syntax::Symbol = :intel, color::Bool = true, hex_for_imm::Bool = true
    )
    printstyled(io, title, '\n', bold = true, color = :green)
    return code_native(io, buf; syntax, color, hex_for_imm)
end
function cpjit_code_native!(
        io::IO, mc::MachineCode, ip::Int64;
        syntax::Symbol = :intel, color::Bool = true, hex_for_imm::Bool = true
    )
    if ip > 0
        for i in 1:length(mc.load_stencils[ip])
            cpjit_code_native_load_stencil!(io, mc, ip, i; syntax, color, hex_for_imm)
        end
    end
    cpjit_code_native_instr_stencil!(io, mc, ip; syntax, color, hex_for_imm)
    return
end
function cpjit_code_native_load_stencil!(
        io::IO, mc::MachineCode, ip::Int64, i::Int64;
        print_unpatched_stencil::Bool = false, kwargs...
    )
    st = mc.load_stencils[ip][i]
    name = get_name(st)
    title = "$(ip) | $(i) | $(name) | "
    buf = if print_unpatched_stencil
        st.bvec
    else
        start = mc.load_stencils_starts[ip][i]
        stop = if i < length(mc.load_stencils[ip])
            mc.load_stencils_starts[ip][i + 1] - 1
        else
            mc.instr_stencil_starts[ip] - 1
        end
        view(mc.buf, start:stop)
    end
    cpjit_code_native!(io, title, buf; kwargs...)
    return
end
function cpjit_code_native_instr_stencil!(
        io::IO, mc::MachineCode, ip::Int64;
        print_unpatched_stencil::Bool = false, kwargs...
    )
    nstarts = length(mc.instr_stencil_starts)
    @assert nstarts > 0
    if ip == 0
        st = get_stencil("abi")
        name = get_name(st)
        title = "$(ip) | abi | -"
        buf = if print_unpatched_stencil
            st.bvec
        else
            start = 1
            stop = if length(mc.load_stencils_starts[1]) > 0
                mc.load_stencils_starts[1][1] - 1
            else
                mc.instr_stencil_starts[1] - 1
            end
            view(mc.buf, start:stop)
        end
    else
        ex = mc.codeinfo.code[ip]
        st = mc.instr_stencils[ip]
        name = get_name(st)
        title = "$(ip) | $(name) | $(ex)"
        buf = if print_unpatched_stencil
            st.bvec
        else
            start = mc.instr_stencil_starts[ip]
            stop = if ip == nstarts
                length(mc.buf)
            else
                if length(mc.load_stencils_starts[ip + 1]) > 0
                    mc.load_stencils_starts[ip + 1][1] - 1
                else
                    mc.instr_stencil_starts[ip + 1] - 1
                end
            end
            view(mc.buf, start:stop)
        end
    end
    cpjit_code_native!(io, title, buf; kwargs...)
    return
end


mutable struct CopyAndPatchMenu <: TerminalMenus.ConfiguredMenu{TerminalMenus.Config}
    mc::MachineCode
    syntax::Symbol
    hex_for_imm::Bool
    str_ssas::Vector{String}
    selected::Int
    pagesize::Int
    pageoffset::Int
    ip_col_width::Int
    ip_fmt::Printf.Format
    stencil_name_col_width::Int
    stencil_name_fmt::Printf.Format
    nheader::Int
    print_relocs::Bool
    config::TerminalMenus.Config
end
function CopyAndPatchMenu(mc, syntax, hex_for_imm)
    config = TerminalMenus.Config(scroll_wrap = true)
    str_ssas = vcat("", string.(mc.codeinfo.code))
    pagesize = 10
    pageoffset = 0
    ip_col_width = max(ndigits(length(str_ssas)), 2)
    ip_fmt = Printf.Format("%-$(ip_col_width)d")
    stencil_name_col_width = maximum(1:length(mc.codeinfo.code)) do ip
        name = get_name(mc.instr_stencils[ip])
        length(name)
    end
    stencil_name_fmt = Printf.Format("%-$(stencil_name_col_width)s")
    nheader = 0
    print_relocs = true
    menu = CopyAndPatchMenu(
        mc, syntax, hex_for_imm, str_ssas, 1, pagesize, pageoffset,
        ip_col_width, ip_fmt, stencil_name_col_width, stencil_name_fmt,
        nheader, print_relocs, config
    )
    header = TerminalMenus.header(menu)
    menu.nheader = countlines(IOBuffer(header))
    return menu
end


TerminalMenus.options(m::CopyAndPatchMenu) = 1:(length(m.mc.codeinfo.code) + 1)
TerminalMenus.cancel(m::CopyAndPatchMenu) = m.selected = -1
# TODO rename to annotate_cpjit_code_native
function annotate_code_native(menu::CopyAndPatchMenu, cursor::Int64)
    ip = cursor - 1
    io = IOBuffer()
    ioc = IOContext(io, stdout)
    tmpio = IOBuffer()
    tmpioc = IOContext(tmpio, stdout)
    if ip > 0
        for i in 1:length(menu.mc.load_stencils[ip])
            annotate_code_native_load_stencil!(tmpio, tmpioc, menu, ip, i)
            print(ioc, String(take!(tmpio)))
        end
    end
    code = annotate_code_native_instr_stencil!(tmpio, tmpioc, menu, ip)
    print(ioc, String(take!(tmpio)))
    return String(take!(io))
end
function annotate_code_native_load_stencil!(
        io::IOBuffer, ioc::IOContext, menu::CopyAndPatchMenu, ip::Int64, i::Int64
    )
    kwargs = (; syntax = menu.syntax, hex_for_imm = menu.hex_for_imm)
    cpjit_code_native_load_stencil!(ioc, menu.mc, ip, i; kwargs...)
    menu.print_relocs || return
    code = String(take!(io))
    st = menu.mc.load_stencils[ip][i]
    cpjit_code_native_load_stencil!(
        ioc, menu.mc, ip, i; kwargs..., color = false,
        print_unpatched_stencil = true
    )
    unpatched_code = String(take!(io))
    cpjit_code_native_load_stencil!(ioc, menu.mc, ip, i; kwargs..., color = false)
    uncolored_code = String(take!(io))
    annotate_relocs!(io, ioc, code, uncolored_code, unpatched_code, st)
    return
end
function annotate_code_native_instr_stencil!(
        io::IOBuffer, ioc::IOContext, menu::CopyAndPatchMenu, ip::Int64
    )
    kwargs = (; syntax = menu.syntax, hex_for_imm = menu.hex_for_imm)
    cpjit_code_native_instr_stencil!(ioc, menu.mc, ip; kwargs...)
    menu.print_relocs || return
    code = String(take!(io))
    st = if ip == 0
        get_stencil("abi")
    else
        menu.mc.instr_stencils[ip]
    end
    cpjit_code_native_instr_stencil!(
        ioc, menu.mc, ip; kwargs..., color = false,
        print_unpatched_stencil = true
    )
    unpatched_code = String(take!(io))
    cpjit_code_native_instr_stencil!(ioc, menu.mc, ip; kwargs..., color = false)
    uncolored_code = String(take!(io))
    annotate_relocs!(io, ioc, code, uncolored_code, unpatched_code, st)
    return
end
function annotate_relocs!(
        io::IOBuffer, ioc::IOContext,
        code::String, uncolored_code::String, unpatched_code::String,
        stencil::StencilData
    )
    # this is a hacky way to relocate the _JIT_* patches in the native code output
    # we are given
    #   - code: formatted and colored native code output of a patched stencil
    #   - uncolored_code: same as code, but without colors, needed to compute max line widths
    #   - unpatched_code: formatted and colored native code output of an unpatched stencil
    #     (only _JIT_* args are unpatched)
    # below we compare code vs unpatched_code line by line, and every mismatch is a line where we patched
    relocs = stencil.md.code.relocations
    max_w = maximum(split(uncolored_code, '\n')[2:end] #=ignore title on first line=#) do line
        length(repr(line))
    end
    nreloc = 0
    for (n, (uc_line, line, up_line)) in enumerate(
            zip(
                eachline(IOBuffer(uncolored_code)),
                eachline(IOBuffer(code)),
                eachline(IOBuffer(unpatched_code))
            )
        )
        n == 1 && (println(ioc, line); continue) # title
        print(ioc, line)
        if !isempty(line) && uc_line != up_line && nreloc < length(relocs)
            nreloc += 1
            w = length(uc_line)
            Δw = max_w - w
            printstyled(ioc, ' '^Δw, "    # $(relocs[nreloc].symbol)", color = :light_blue)
        end
        println(ioc)
    end
    if nreloc != length(relocs)
        s = Logging.SimpleLogger(ioc)
        Logging.with_logger(s) do
            println(ioc)
            @error "relocation failed, found $nreloc but expected $(length(relocs))"
        end
    end
    return
end


function annotate_code_native_with_newlines(menu::CopyAndPatchMenu, cursor::Int64)
    N = length(menu.mc.codeinfo.code) + 1 # +1 for abi stencil
    n = min(N, menu.pagesize) + menu.nheader - 1
    return println(stdout, '\n'^(menu.nheader - 1), annotate_code_native(menu, cursor), '\n'^n)
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
        annotate_code_native_with_newlines(menu, cursor)
    end
    return cursor
end
function TerminalMenus.move_up!(menu::CopyAndPatchMenu, cursor::Int64, lastoption::Int64)
    # from stdlib/REPL/TerminalMenus/AbstractMenu.jl
    if cursor > 1
        cursor -= 1 # move selection up
        if cursor < (2 + menu.pageoffset) && menu.pageoffset > 0
            menu.pageoffset -= 1 # scroll page up
        end
    elseif TerminalMenus.scroll_wrap(menu)
        # wrap to bottom
        cursor = lastoption
        menu.pageoffset = max(0, lastoption - menu.pagesize)
    end
    if cursor != menu.selected
        menu.selected = cursor
        annotate_code_native_with_newlines(menu, cursor)
    end
    return cursor
end
function TerminalMenus.pick(menu::CopyAndPatchMenu, cursor::Int)
    menu.selected = cursor
    return false
end
function TerminalMenus.header(menu::CopyAndPatchMenu)
    io = IOBuffer(); ioc = IOContext(io, stdout)
    printstyled(ioc, 'q', color = :light_red, bold = true)
    q_str = String(take!(io))
    printstyled(
        ioc, 's', bold = true,
        color = menu.syntax === :intel ? :light_magenta : :light_yellow
    )
    s_str = String(take!(io))
    printstyled(
        ioc, menu.syntax,
        color = menu.syntax === :intel ? :light_magenta : :light_yellow
    )
    syntax_str = String(take!(io))
    printstyled(
        ioc, 'r', bold = true,
        color = menu.print_relocs ? :light_blue : :none
    )
    r_str = String(take!(io))
    printstyled(
        ioc, 'h', bold = true,
        color = menu.hex_for_imm ? :light_blue : :none
    )
    h_str = String(take!(io))
    return """
    Scroll through expressions for analysis:
    [$q_str]uit, [$s_str]yntax = $(syntax_str), [$r_str]elocations, [$h_str]ex for immediate values
       ip$(' '^(menu.ip_col_width - 2)) | stencil$(' '^(menu.stencil_name_col_width - 7)) | SSA
    """
end
function TerminalMenus.writeline(buf::IOBuffer, menu::CopyAndPatchMenu, idx::Int, iscursor::Bool)
    ioc = IOContext(buf, stdout)
    str_idx = Printf.format(menu.ip_fmt, idx)
    if idx == 1
        name = "abi"
    else
        ip = idx - 1
        name = get_name(menu.mc.instr_stencils[ip])
    end
    sname = Printf.format(menu.stencil_name_fmt, name)
    return if iscursor
        printstyled(ioc, str_idx, " | ", sname, " | ", menu.str_ssas[idx], bold = true, color = :green)
    else
        print(ioc, str_idx, " | ", sname, " | ", menu.str_ssas[idx])
    end
end
function TerminalMenus.keypress(menu::CopyAndPatchMenu, key::UInt32)
    if key == UInt32('s')
        menu.syntax = (menu.syntax === :intel) ? :att : :intel
        annotate_code_native_with_newlines(menu, menu.selected)
    elseif key == UInt32('r')
        menu.print_relocs ⊻= true
        annotate_code_native_with_newlines(menu, menu.selected)
    elseif key == UInt32('h')
        menu.hex_for_imm ⊻= true
        annotate_code_native_with_newlines(menu, menu.selected)
    end
    return false
end
