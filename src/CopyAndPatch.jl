module CopyAndPatch


import Mmap: mmap
# using JuliaInterpreter
import JSON: parsefile
import Base.Libc.Libdl: dlpath, dlopen
import Printf: Format, format


TODO() = error("Not implemented yet")
TODO(msg) = error("Not implemented yet: $msg")


# function jit!(frame::Frame)
#     pc = JuliaInterpreter.pc_expr(frame)
#     if JuliaInterpreter.is_ReturnNode(pc)
#         return pc.val
#     else
#         TODO(pc)
#     end
#     return pc
# end


include("utils.jl")
include("bytevector.jl")
include("machinecode.jl")
include("stencil.jl")


end
