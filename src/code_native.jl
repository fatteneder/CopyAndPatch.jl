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
