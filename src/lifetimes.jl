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

function show_lifetimes(cinfo::Core.CodeInfo)
    lifetimes = compute_lifetimes(cinfo)
    show_lifetimes(cinfo, lifetimes)
end

function show_lifetimes(cinfo::Core.CodeInfo, lifetimes::Dict)
    io = IOBuffer()
    ioc = IOContext(io, stdout)
    show(ioc, cinfo)
    str_cinfo = String(take!(io))
    ioc = IOContext(io, :color=>false)
    show(ioc, cinfo)
    str_cinfo_nocolor = String(take!(io))
    max_w = maximum(length, eachline(IOBuffer(str_cinfo_nocolor)))
    nlines = count(==('\n'), str_cinfo_nocolor)
    cfg = Compiler.compute_basic_blocks(cinfo.code)
    # block_rngs = reduce(vcat, [ b.stmts.start, b.stmts.stop ] for b in cfg.blocks)
    block_rngs = [ b.stmts.start for b in cfg.blocks ]
    # unique!(block_rngs)
    active = Set{VirtualReg}()
    inactive = Set{VirtualReg}()
    line_itr = eachline(IOBuffer(str_cinfo))
    line_itr_nocolor = eachline(IOBuffer(str_cinfo_nocolor))
    fmt_head = Printf.Format("%-6s")
    fmt_col = Printf.Format(" %s%4s")
    ioc = IOContext(io, stdout)
    slot_regs = [ k for k in keys(lifetimes) if k isa Core.Argument ]
    sort!(slot_regs, lt=(a,b) -> a.n < b.n)
    ssa_regs = [ k for k in keys(lifetimes) if k isa Core.SSAValue ]
    sort!(ssa_regs, lt=(a,b) -> a.id < b.id)
    regs = vcat(slot_regs, ssa_regs)
    intervals = [ lifetimes[r] for r in regs ]
    # TODO Recolor the first brackets in the cinfo that mark the blocks
    for (i,(line, nc_line)) in enumerate(zip(line_itr, line_itr_nocolor))
        # ┓  ┛ ┫ │ ║ ╖   ╗ ╜   ╝ ╣  ╻ ╹   ╿ ╽
        w = length(nc_line)
        Δw = max_w - w
        print(ioc, line)
        if i == 1
            print(ioc, " "^(Δw+3))
            # for reg in keys(lifetimes)
            for reg in regs
                name = reg isa Core.Argument ? cinfo.slotnames[reg.n] : reg
                print(ioc, Printf.format(fmt_head, string(name)))
            end
        else
            ii = i-1
            if ii in block_rngs
                printstyled(ioc, " ", "─"^(Δw+2), color=:light_black)
            else
                print(ioc, " "^(Δw+3))
            end
            # for (reg,intervals) in pairs(lifetimes)
            for (reg,intervals) in zip(regs,intervals)
                sym, color = "┃", :light_black
                if length(intervals) > 0
                    j = findfirst(intervals) do intrvl
                        ii in intrvl
                    end
                    if j !== nothing
                        intrvl = intervals[j]
                        if ii == intrvl.start
                            if intrvl.start == intrvl.stop
                                sym, color = "┻", :light_green
                            else
                                sym, color = "┳", :light_red
                            end
                        elseif ii == intrvl.stop
                            sym, color = "┻", :light_green
                        else
                            sym, color = "┃", :light_blue
                        end
                    end
                    printstyled(ioc, " ", sym; color)
                    if ii in block_rngs
                        printstyled(ioc, " ", "─"^3, color=:light_black)
                    else
                        print(ioc, " "^4)
                    end
                end
            end
        end
        println(ioc)
    end
    print(String(take!(io)))
end
