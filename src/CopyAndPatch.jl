module CopyAndPatch


using Mmap
using JuliaInterpreter
using JSON


TODO() = error("Not implemented yet")
TODO(msg) = error("Not implemented yet: $msg")


function jit!(frame::Frame)
    pc = JuliaInterpreter.pc_expr(frame)
    if JuliaInterpreter.is_ReturnNode(pc)
        return pc.val
    else
        TODO(pc)
    end
    return pc
end


include("bytevector.jl")
include("machinecode.jl")
include("stencil.jl")


end
