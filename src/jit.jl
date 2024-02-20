if isa(node, Expr)
    if node.head === :(=)
        lhs, rhs = node.args
        if isa(rhs, Expr)
            rhs = eval_rhs(recurse, frame, rhs)
        else
            rhs = istoplevel ? @lookup(moduleof(frame), frame, rhs) : @lookup(frame, rhs)
        end
        isa(rhs, BreakpointRef) && return rhs
        do_assignment!(frame, lhs, rhs)
    elseif node.head === :enter
        TODO()
        rhs = node.args[1]::Int
        push!(data.exception_frames, rhs)
    elseif node.head === :leave
        TODO()
        if length(node.args) == 1 && isa(node.args[1], Int)
            arg = node.args[1]::Int
            for _ = 1:arg
                pop!(data.exception_frames)
            end
        else
            for i = 1:length(node.args)
                targ = node.args[i]
                targ === nothing && continue
                enterstmt = frame.framecode.src.code[(targ::SSAValue).id]
                enterstmt === nothing && continue
                pop!(data.exception_frames)
                if isdefined(enterstmt, :scope)
                    pop!(data.current_scopes)
                end
            end
        end
    elseif node.head === :pop_exception
        TODO()
    elseif istoplevel
        TODO()
        if node.head === :method && length(node.args) > 1
            evaluate_methoddef(frame, node)
        elseif node.head === :module
            error("this should have been handled by split_expressions")
        elseif node.head === :using || node.head === :import || node.head === :export
            Core.eval(moduleof(frame), node)
        elseif node.head === :const
            g = node.args[1]
            if isa(g, GlobalRef)
                mod, name = g.mod, g.name
            else
                mod, name = moduleof(frame), g::Symbol
            end
            Core.eval(mod, Expr(:const, name))
        elseif node.head === :thunk
            newframe = Frame(moduleof(frame), node.args[1]::CodeInfo)
            if isa(recurse, Compiled)
                finish!(recurse, newframe, true)
            else
                newframe.caller = frame
                frame.callee = newframe
                finish!(recurse, newframe, true)
                frame.callee = nothing
            end
            return_from(newframe)
        elseif node.head === :global
            Core.eval(moduleof(frame), node)
        elseif node.head === :toplevel
            mod = moduleof(frame)
            iter = ExprSplitter(mod, node)
            rhs = Core.eval(mod, Expr(:toplevel,
                :(for (mod, ex) in $iter
                      if ex.head === :toplevel
                          Core.eval(mod, ex)
                          continue
                      end
                      newframe = ($Frame)(mod, ex)
                      while true
                          ($through_methoddef_or_done!)($recurse, newframe) === nothing && break
                      end
                      $return_from(newframe)
                  end)))
        elseif node.head === :error
            error("unexpected error statement ", node)
        elseif node.head === :incomplete
            error("incomplete statement ", node)
        else
            rhs = eval_rhs(recurse, frame, node)
        end
    elseif node.head === :thunk || node.head === :toplevel
        error("this frame needs to be run at top level")
    else
        TODO()
        rhs = eval_rhs(recurse, frame, node)
    end
elseif isa(node, GotoNode)
    return (frame.pc = node.label)
elseif isa(node, GotoIfNot)
    arg = @lookup(frame, node.cond)
    if !isa(arg, Bool)
        throw(TypeError(nameof(frame), "if", Bool, arg))
    end
    if !arg
        return (frame.pc = node.dest)
    end
elseif isa(node, ReturnNode)
    return nothing
elseif isa(node, NewvarNode)
    # FIXME: undefine the slot?
elseif istoplevel && isa(node, LineNumberNode)
elseif istoplevel && isa(node, Symbol)
    rhs = getfield(moduleof(frame), node)
elseif @static (isdefined(Core.IR, :EnterNode) && true) && isa(node, Core.IR.EnterNode)
    rhs = node.catch_dest
    push!(data.exception_frames, rhs)
    if isdefined(node, :scope)
        push!(data.current_scopes, @lookup(frame, node.scope))
    end
else
    rhs = @lookup(frame, node)
end
