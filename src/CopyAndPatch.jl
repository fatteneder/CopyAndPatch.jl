module CopyAndPatch


import Base: isexpr, code_typed, unsafe_convert, Iterators
import Base.Libc.Libdl: dlpath, dlopen, dlsym
import Core: MethodInstance, CodeInfo
import InteractiveUtils: print_native
import JSON: parsefile
import Libffi_jll: libffi_handle, libffi_path
import Logging: SimpleLogger, with_logger
import Mmap: mmap
import Printf: Format, format
import REPL
import REPL: TerminalMenus



export jit


TODO() = error("Not implemented yet")
TODO(msg) = TODO("Not implemented yet", msg)
TODO(prefix, msg) = error(prefix, " ", msg)



const libjulia = Ref{Ptr{Cvoid}}(0)
const libjuliainternal = Ref{Ptr{Cvoid}}(0)
const libc = Ref{Ptr{Cvoid}}(0)
const libjuliahelpers_path = Ref{String}("")
const libffihelpers_path = Ref{String}("")
const libmwes_path = Ref{String}("")
function __init__()
    libjulia[] = dlopen(dlpath("libjulia.so"))
    libjuliainternal[] = dlopen(dlpath("libjulia-internal.so"))
    libc[] = dlopen(dlpath("libc.so.6"))
    libjuliahelpers_path[] = normpath(joinpath(@__DIR__, "..", "stencils", "bin", "libjuliahelpers.so"))
    libffihelpers_path[] = normpath(joinpath(@__DIR__, "..", "stencils", "bin", "libffihelpers.so"))
    libmwes_path[] = normpath(joinpath(@__DIR__, "..", "stencils", "bin", "libmwes.so"))
    nothing
end


include("utils.jl")
include("bytevector.jl")
include("machinecode.jl")
include("stencil.jl")
include("jit.jl")


end
