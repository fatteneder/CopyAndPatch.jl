module CopyAndPatch


import Base: isexpr, code_typed, unsafe_convert, Iterators
import Base.Libc.Libdl: dlpath, dlopen, dlsym
import Core: MethodInstance, CodeInfo
import InteractiveUtils: print_native
import JSON: parsefile
import Libffi_jll: libffi_handle, libffi_path
import Mmap: mmap
import Printf: Format, format


export jit


TODO() = error("Not implemented yet")
TODO(msg) = TODO("Not implemented yet", msg)
TODO(prefix, msg) = error(prefix, " ", msg)



const path_libjulia = Ref{String}("")
const path_libjuliainternal = Ref{String}("")
const path_libjl = Ref{String}("")
const path_libffihelpers = Ref{String}("")
const libjulia = Ref{Ptr{Cvoid}}(0)
const libjuliainternal = Ref{Ptr{Cvoid}}(0)
const libc = Ref{Ptr{Cvoid}}(0)
function __init__()
    libjulia[] = dlopen(dlpath("libjulia.so"))
    libjuliainternal[] = dlopen(dlpath("libjulia-internal.so"))
    libc[] = dlopen(dlpath("libc.so.6"))
    path_libjulia[] = dlpath("libjulia.so")
    path_libjuliainternal[] = dlpath("libjulia-internal.so")
    path_libjl[] = normpath(joinpath(@__DIR__, "..", "stencils", "libjl.so"))
    path_libffihelpers[] = normpath(joinpath(@__DIR__, "..", "stencils", "libffihelpers.so"))
    nothing
end


include("utils.jl")
include("bytevector.jl")
include("machinecode.jl")
include("stencil.jl")
include("jit.jl")


end
