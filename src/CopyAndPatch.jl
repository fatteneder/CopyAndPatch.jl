module CopyAndPatch


import Mmap: mmap
# using JuliaInterpreter
import JSON: parsefile
import Base.Libc.Libdl: dlpath, dlopen, dlsym
import Printf: Format, format


TODO() = error("Not implemented yet")
TODO(msg) = error("Not implemented yet: $msg")



const path_libjulia = Ref{String}("")
const libjulia = Ref{Ptr{Cvoid}}(0)
const libjuliainternal = Ref{Ptr{Cvoid}}(0)
const libc = Ref{Ptr{Cvoid}}(0)
function __init__()
    libjulia[] = dlopen(dlpath("libjulia.so"))
    libjuliainternal[] = dlopen(dlpath("libjulia-internal.so"))
    libc[] = dlopen(dlpath("libc.so.6"))
    path_libjulia[] = dlpath("libjulia.so")
    nothing
end


include("utils.jl")
include("bytevector.jl")
include("machinecode.jl")
include("stencil.jl")


end
