# Lifetime analysis based on SSA form
# Implementation of algorithm described in section 4.1 and figure 4 of
#    Linear Scan Register Allocation on SSA Form
#    Christian Wimmer, Michael Franz
#    Proceedings of the 8th annual IEEE/ACM international symposium
#    on Code generation and optimization. 2010

const VirtualReg = Union{Core.Argument,Core.SSAValue}
const Interval = UnitRange{Int}
mutable struct Lifetime
    const intervals::Vector{Interval}
    def::Int
    const uses::Set{Int}
end
Lifetime() = Lifetime(Interval[], 0, Set{Int}())

struct Loop
    heads::Vector{Int}
    backedges::Vector{Int}
end
Loop() = Loop(Vector{Int}[], Vector{Int}[])

struct LifetimeAnalysis
    cinfo::Core.CodeInfo
    cfg::Compiler.CFG
    block_order::Vector{Int}
    lifetimes::Dict{VirtualReg,Lifetime}
    loops::Vector{Loop}
end

function analyze_lifetimes(cinfo::Core.CodeInfo)
    cfg = Compiler.compute_basic_blocks(cinfo.code)
    block_order = collect(1:length(cfg.blocks))
    lifetimes, loops = _analyze_lifetimes(cinfo.code, cfg, block_order)
    return LifetimeAnalysis(cinfo, cfg, block_order, lifetimes, loops)
end

function _analyze_lifetimes(stmts::Vector{Any}, cfg::Compiler.CFG, block_order::Vector{Int})
    liveIns = [ Set{VirtualReg}() for i in 1:length(block_order) ]
    lifetimes = Dict{VirtualReg,Lifetime}()
    loops = Loop[]
    for i_block in reverse(block_order)
        block = cfg.blocks[i_block]

        # build live set for current block by combining liveIns of all successors
        live = Set{VirtualReg}()
        for i_succ in block.succs
            union!(live, liveIns[i_succ])
        end
        # println("="^20, "\n---- liveIns succs"); display(live)
        # and add all inputs from this block appearing in any phi functions in its successors
        for i_succ in block.succs
            succ = cfg.blocks[i_succ]
            for i_stmt in succ.stmts
                stmt = stmts[i_stmt]
                stmt isa Core.PhiNode || break
                for (i,e) in enumerate(stmt.edges)
                    if e in block.stmts
                        val = stmt.values[i]
                        val isa VirtualReg && push!(live, val)
                        break
                    end
                end
            end
        end
        # println("---- liveIns succs + succs phis"); display(live)

        # XXX: an additional pass added by me
        # remove all inputs from this block appearing in any phi functions in successors
        # iff this block is not an immediate dominator of that successor
        for i_succ in block.succs
            succ = cfg.blocks[i_succ]
            is_imm_dominated = length(succ.preds) == 1
            if !is_imm_dominated
                for i_stmt in succ.stmts
                    stmt = stmts[i_stmt]
                    stmt isa Core.PhiNode || break
                    for (i,e) in enumerate(stmt.edges)
                        if e != i_block
                            val = stmt.values[i]
                            val isa VirtualReg && delete!(live, val)
                        end
                    end
                end
            end
        end
        # println("---- live after removing phi ins in case of dominance frontier"); display(live)

        # initialize intervals for live operands in this block
        for operand in live
            lt = get!(lifetimes, operand, Lifetime())
            push!(lt.intervals, block.stmts)
        end

        # scan statements of current block,
        # shorten intervals for outputs and add intervals for inputs
        phi_inputs = Set{VirtualReg}() # used for loop header analysis below
        for i_stmt in reverse(block.stmts)
            outputs = get_outputs(stmts, i_stmt)
            # println("* processing $(stmts[i_stmt])"); @show outputs
            for operand in outputs
                lt = get!(lifetimes, operand, Lifetime())
                if length(lt.intervals) > 0
                    lt.intervals[end] = Interval(i_stmt, lt.intervals[end].stop)
                end
                lt.def = i_stmt
                delete!(live, operand)
            end
            inputs = get_inputs(stmts, i_stmt)
            if stmts[i_stmt] isa Core.PhiNode
                union!(phi_inputs, inputs)
            end
            for operand in inputs
                lt = get!(lifetimes, operand, Lifetime())
                push!(lt.intervals, Interval(block.stmts.start, i_stmt))
                push!(lt.uses, i_stmt)
                push!(live, operand)
            end
        end
        # println("---- live after in/out processed"); display(live)

        # remove phi outputs from current block
        for i_stmt in block.stmts
            stmt = stmts[i_block]
            stmt isa Core.PhiNode || break
            delete!(live, Core.SSAValue(i_stmt))
        end
        # println("---- live after removing phi outs"); display(live)

        # special case loop headers
        preds_loop_ends = Int[]
        # TODO Can a loop header have multiple back edges?
        findall(block.preds) do i
            # a loop header is a block with a backedge
            if i ≥ i_block
                push!(preds_loop_ends, i)
                return true
            end
            return false
        end
        @assert length(preds_loop_ends) ≤ 1
        is_loop_header = length(preds_loop_ends) == 1
        if is_loop_header
            # TODO Detect irreducible loops!!!
            # TODO Handle irreducible loops!!!

            # XXX: an additional pass added by me
            # filter phi inputs from live which are only inflowing into the loop
            # and which are not live after the loop header
            filtered_live = filter(live) do operand
                operand in phi_inputs || return true
                is_inflowing = true
                for i_stmt in block.stmts
                    stmt = stmts[i_stmt]
                    stmt isa Core.PhiNode || break
                    for (e,v) in zip(stmt.edges,stmt.values)
                        v == operand || continue
                        for i_pred in block.preds
                            pred = cfg.blocks[i_pred]
                            if e in pred.stmts
                                i_pred in preds_loop_ends && return true
                            end
                        end
                    end
                end
                return !is_inflowing
            end
            # println("&&&&&& did filtering work?"); @show filtered_live; @show live

            # extend lifetimes till loop end
            for i_loop_end in preds_loop_ends
                loop_end = cfg.blocks[i_loop_end]
                for operand in filtered_live
                    lt = lifetimes[operand]
                    push!(lt.intervals, Interval(block.stmts.start, loop_end.stmts.stop))
                end
            end

            loop = Loop([i_block],preds_loop_ends)
            push!(loops, loop)
        end

        liveIns[i_block] = live
    end

    for lt in values(lifetimes)
        sort!(lt.intervals)
        # TODO Merge adjacent intervals
        # sort!(lt.uses)
    end
    # merge loops with common heads
    i = 1
    while i < length(loops)
        li = loops[i]
        j = i+1
        while j < length(loops)
            lj = loops[j]
            if only(lj.heads) in li.heads
                loops[i] = Loop(li.heads, unique(vcat(li.ends, lj.ends)))
                popat!(loops, j)
            else
                j += 1
            end
        end
        i += 1
    end
    # merge adjacent intervals
    # for intervals in values(lifetime_intervals)
    #     length(intervals) < 2 && continue
    #     pos = 1
    #     while pos < length(intervals)
    #         i1, i2 = intervals[pos], intervals[pos+1]
    #         if i2.start - i1.stop <= 0
    #             intervals[pos] = Interval(i1.start, i2.stop)
    #             popat!(intervals, pos+1)
    #         else
    #             pos += 1
    #         end
    #     end
    # end

    # TODO lifetime_intervals is missing dead variables
    return lifetimes, loops
end

@inline function get_inputs(stmts::Vector{Any}, i)
    inputs = Set{VirtualReg}()
    stmt = stmts[i]
    if stmt isa Core.PhiNode
        for val in stmt.values
            val isa VirtualReg && push!(inputs, val)
        end
    elseif stmt isa Core.GotoNode
    elseif stmt isa Core.GotoIfNot
        push!(inputs, stmt.cond)
    elseif stmt isa Core.ReturnNode
    elseif Base.isexpr(stmt, :call)
        for i in 2:length(stmt.args)
            arg = stmt.args[i]
            arg isa VirtualReg && push!(inputs, arg)
        end
    else
        TODO(stmt)
    end
    return inputs
end

@inline function get_outputs(stmts::Vector{Any}, i)
    outputs = Set{VirtualReg}()
    stmt = stmts[i]
    if stmt isa Core.PhiNode
        push!(outputs, Core.SSAValue(i))
    elseif stmt isa Core.GotoNode
    elseif stmt isa Core.GotoIfNot
    elseif stmt isa Core.ReturnNode
        stmt.val isa VirtualReg && push!(outputs, stmt.val)
    elseif Base.isexpr(stmt, :call)
        push!(outputs, Core.SSAValue(i))
    else
        TODO(stmt)
    end
    return outputs
end

function get_virtual_regs(stmts)
    inputs = Set{VirtualReg}()
    outputs = Set{VirtualReg}()
    for (i,stmt) in enumerate(stmts)
        union!(inputs, get_inputs(stmts, i))
        union!(outputs, get_outputs(stmts, i))
    end
    return inputs, outputs
end

# type-piracy, useful for debugging compute_lifetimes()
function Base.show(io::IO, block::Compiler.BasicBlock)
    print(io, "bb")
    if block.stmts.start == block.stmts.stop
        print(io, " (stmt ", block.stmts.start, ")")
    else
        print(io, " (stmts ", block.stmts.start, ":", block.stmts.stop, ")")
    end
    if !isempty(block.succs)
        print(io, " → bb ")
        join(io, block.succs, ", ")
    end
end


mutable struct LifetimeAnalysisMenu <: TerminalMenus.AbstractMenu
    analysis::LifetimeAnalysis
    row_cursor::Int # cursor position of first line in code info output
    col_cursor::Int # cursor position of first virtual registor in lifetime diagram
    nlines::Int
    max_w::Int # analysis.cinfo max width
    col_gap::Int # min spacing between lifetime lines
    regs::Vector{VirtualReg} # keys(analysis.lifetimes), but sorted (slots before ssa values)
    lifetimes::Vector{Lifetime} # values(analysis.lifetimes), but sorted
    headers::Vector{String} # string.(regs) and argument numbers translated to slot names
    str_cinfo::String
    str_cinfo_nocolor::String
    block_rngs::Vector{Int}
    is_loop_headers::Vector{Int64} # start index of loop header BasicBlock in analysis.stmts
    is_loop_backedges::Vector{Int64} # end index of BasicBlocks that have a backedge to a loop header
    # required for TerminalMenus interface
    pagesize::Int
    pageoffset::Int
end

function LifetimeAnalysisMenu(analysis::LifetimeAnalysis)
    tmpio = IOBuffer()
    tmpioc = IOContext(tmpio, stdout)
    Base.show(tmpioc, analysis.cinfo)
    str_cinfo = String(take!(tmpio))
    tmpioc = IOContext(tmpio, :color=>false)
    Base.show(tmpioc, analysis.cinfo)
    str_cinfo_nocolor = String(take!(tmpio))
    nlines = count(==('\n'), str_cinfo_nocolor)

    max_w = maximum(length, eachline(IOBuffer(str_cinfo_nocolor)))

    block_rngs = [ b.stmts.start for b in analysis.cfg.blocks ]
    regs_slots = [ k for k in keys(analysis.lifetimes) if k isa Core.Argument ]
    sort!(regs_slots, lt=(a,b) -> a.n < b.n)
    regs_ssas = [ k for k in keys(analysis.lifetimes) if k isa Core.SSAValue ]
    sort!(regs_ssas, lt=(a,b) -> a.id < b.id)
    regs = vcat(regs_slots, regs_ssas)
    lifetimes = [ analysis.lifetimes[r] for r in regs ]
    headers = [ reg isa Core.Argument ? string(analysis.cinfo.slotnames[reg.n]) : string(reg)
                for reg in regs ]

    is_loop_headers = mapreduce(vcat, analysis.loops) do l
        bs = analysis.cfg.blocks[l.heads]
        return [ b.stmts.start for b in bs ]
    end
    is_loop_backedges = mapreduce(vcat, analysis.loops) do l
        bs = analysis.cfg.blocks[l.backedges]
        return [ b.stmts.stop for b in bs ]
    end
    col_gap = 3
    row_cursor = 1
    col_cursor = 1

    menu = LifetimeAnalysisMenu(
        analysis, row_cursor, col_cursor, nlines, max_w, col_gap,
        regs, lifetimes, headers, str_cinfo, str_cinfo_nocolor,
        block_rngs, is_loop_headers, is_loop_backedges,
        0, 0
    )
    return menu
end

function inspect(analysis::LifetimeAnalysis)
    menu = LifetimeAnalysisMenu(analysis)
    term = default_terminal()
    print('\n', _inspect(stdout, menu), '\n')
    TerminalMenus.request(term, menu)
    return nothing
end

TerminalMenus.numoptions(m::LifetimeAnalysisMenu) = 0
TerminalMenus.cancel(m::LifetimeAnalysisMenu) = nothing
TerminalMenus.selected(menu::LifetimeAnalysisMenu) = nothing
TerminalMenus.writeline(buf::IOBuffer, menu::LifetimeAnalysisMenu, idx::Int, iscursor::Bool) = nothing
TerminalMenus.pick(menu::LifetimeAnalysisMenu, cursor::Int) = false

function TerminalMenus.header(menu::LifetimeAnalysisMenu)
    io = IOBuffer(); ioc = IOContext(io, stdout)
    printstyled(ioc, 'q', color = :light_red, bold = true)
    q_str = String(take!(io))
    printstyled(ioc, 'r', color = :light_blue, bold = true)
    r_str = String(take!(io))
    printstyled(ioc, 'R', color = :light_blue, bold = true)
    R_str = String(take!(io))
    printstyled(ioc, '←', bold = true, color=:yellow)
    arrow_left_str = String(take!(io))
    printstyled(ioc, '→', bold = true, color=:yellow)
    arrow_right_str = String(take!(io))
    printstyled(ioc, '↑', bold = true, color=:yellow)
    arrow_up_str = String(take!(io))
    printstyled(ioc, '↓', bold = true, color=:yellow)
    arrow_down_str = String(take!(io))
    return """
    [$q_str]uit, [$r_str]edraw, [$R_str]reset, [$arrow_up_str/$arrow_down_str] scroll code, [$arrow_left_str/$arrow_right_str] scroll lifetimes
    """
end

function TerminalMenus.keypress(menu::LifetimeAnalysisMenu, key::UInt32)
    if key == UInt32(TerminalMenus.ARROW_LEFT)
        menu.col_cursor = min(menu.col_cursor+1, length(menu.regs))
        print('\n', _inspect(stdout, menu), '\n')
    elseif key == UInt32(TerminalMenus.ARROW_RIGHT)
        menu.col_cursor = max(menu.col_cursor-1, 1)
        print('\n', _inspect(stdout, menu), '\n')
    elseif key == UInt32('r')
        print('\n', _inspect(stdout, menu), '\n')
    elseif key == UInt32('R')
        menu.col_cursor = 1
        menu.row_cursor = 1
        print('\n', _inspect(stdout, menu), '\n')
    end
    return false
end
# we are not really using the menu scrolling functionality,
# but we need to use them to act on up/down arrow
function TerminalMenus.move_down!(menu::LifetimeAnalysisMenu, cursor::Int64, lastoption::Int64)
    menu.row_cursor = min(menu.row_cursor+1, menu.nlines)
    print('\n', _inspect(stdout, menu), '\n')
    return 1
end
function TerminalMenus.move_up!(menu::LifetimeAnalysisMenu, cursor::Int64, lastoption::Int64)
    menu.row_cursor = max(menu.row_cursor-1, 1)
    print('\n', _inspect(stdout, menu), '\n')
    return 1
end

function _inspect(io::IO, M::LifetimeAnalysisMenu)
    ioc = IOContext(io)
    line_itr = eachline(IOBuffer(M.str_cinfo))
    line_itr_nocolor = eachline(IOBuffer(M.str_cinfo_nocolor))
    # compute number of registers that fit on screen
    height, width = displaysize(ioc)
    width -= M.max_w+M.col_gap
    n_cols = 1
    while M.col_cursor-1+n_cols < length(M.regs)
        width -= length(M.headers[M.col_cursor+n_cols-1])+M.col_gap
        if width ≤ 1
            n_cols -= 1
            break
        else
            n_cols += 1
        end
    end
    n_cols = min(n_cols, length(M.regs))
    col_rng = M.col_cursor:M.col_cursor-1+n_cols
    # compute number of lines that fit on screen
    n_rows = height-5
    row_rng = M.row_cursor:M.row_cursor-1+n_rows
    # draw output
    println(ioc)
    for (i,(line, nc_line)) in enumerate(zip(line_itr, line_itr_nocolor))
        w = length(nc_line)
        Δw = M.max_w - w

        if i == 1
            print(ioc, line)
            print(ioc, " "^(Δw+M.col_gap))
            for h in M.headers[col_rng]
                l = length(h)
                # l ≤ 2 && print(ioc, " ")
                print(ioc, " "^(l≤2), h, " "^((l≤1)+M.col_gap))
            end
            println(ioc)
            continue
        end

        # print a line from cinfo
        i in row_rng || continue
        print(ioc, line)

        # append trailing dashes to cinfo line to fill space till lifetime diagram starts
        ii = i-1
        if ii in M.block_rngs
            # print header
            color = if ii in M.is_loop_headers
                :yellow
            elseif ii in M.is_loop_backedges
                :magenta
            else
                :light_black
            end
            printstyled(ioc, " ", "─"^(Δw+M.col_gap-1); color)
        else
            print(ioc, " "^(Δw+M.col_gap))
        end

        # draw a horizontal slice of the lifetime diagram
        for (col,(h,reg,lt)) in enumerate(zip(M.headers[col_rng],
                                              M.regs[col_rng],
                                              M.lifetimes[col_rng]))
            vert_sym, vert_color = "┃", :light_black
            horz_sym, horz_color = " ", :white
            if length(lt.intervals) > 0
                j = findfirst(lt.intervals) do intrvl
                    ii in intrvl
                end
                if j !== nothing
                    intrvl = lt.intervals[j]
                    if ii == lt.def
                        vert_sym, vert_color = "┳", :light_red
                    elseif ii in lt.uses
                        vert_sym, vert_color = "┻", :light_green
                    else
                        vert_sym, vert_color = "┃", :light_blue
                    end
                end
            end
            if ii in M.block_rngs
                horz_sym = "─"
                if ii in M.is_loop_headers
                    horz_color = :yellow
                elseif ii in M.is_loop_backedges
                    horz_color = :magenta
                else
                    horz_color = :light_black
                end
            end
            l = length(h)
            c = l÷2+isodd(l)
            printstyled(ioc, horz_sym^(max(0,c-2)); color=horz_color)
            printstyled(ioc, " ", vert_sym, " "; color=vert_color)
            if col < length(col_rng)
                printstyled(ioc, horz_sym^(max(0,l-c-1)+M.col_gap); color=horz_color)
            end
        end
        println(ioc)
    end
    # TODO take string here
end
