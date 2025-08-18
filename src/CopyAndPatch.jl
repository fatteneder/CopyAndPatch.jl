module CopyAndPatch


import Base
import Base.Iterators
import Core
import InteractiveUtils
import JSON
import Libdl
import Libffi_jll
import Logging
import Mmap
import Printf
import REPL
import REPL.TerminalMenus
if VERSION ≥ v"1.12.0-DEV.1581"
    import Compiler
    const CC = Compiler
else
    const CC = Core.Compiler
end
import Core.OptimizedGenerics.CompilerPlugins as CCPlugins
import Scratch
import TOML



include("utils.jl")
include("ffi.jl")
include("bytevector.jl")
include("lifetimes.jl")
include("stencil.jl")
include("machinecode.jl")
include("jit.jl")
include("code_native.jl")
include("extern_pkg_code.jl")
include("julia_integration.jl")


const STENCILS = Ref(Dict{String, StencilData}())
const MAGICNR = 0xDEADBEEFDEADBEEF


function init_stencils()
    files = readdir(STENCIL_DIR[], join = true)
    filter!(files) do f
        endswith(f, ".json")
    end
    empty!(STENCILS[])
    for f in files
        try
            name = first(splitext(basename(f)))
            s = StencilGroup(f, name)
            bvec = ByteVector(s.code.body)
            bvec_data = ByteVector(s.data.body)
            patch_default_deps!(bvec, bvec_data, s)
            for h in s.code.relocations
                @assert h.kind == "R_X86_64_64"
                bvec[h.offset + 1] = MAGICNR
            end
            STENCILS[][name] = StencilData(s, bvec, bvec_data)
        catch e
            println("Failure when processing $f")
            rethrow(e)
        end
    end
    return
end


function patch_default_deps!(bvec::ByteVector, bvec_data::ByteVector, s::StencilGroup)
    holes = s.code.relocations
    patched = Hole[]
    for h in holes
        startswith(h.symbol, "_JIT_") && continue
        ptr = if startswith(h.symbol, "jl_")
            p = Libdl.dlsym(LIBJULIA[], h.symbol, throw_error = false)
            if isnothing(p)
                p = Libdl.dlsym(LIBJULIAINTERNAL[], h.symbol, throw_error = false)
                if isnothing(p)
                    error("failed to find $(h.symbol) symbol")
                end
            end
            p
        elseif startswith(h.symbol, "jlh_")
            Libdl.dlsym(LIBJULIAHELPERS[], h.symbol)
        elseif startswith(h.symbol, ".rodata") || startswith(h.symbol, ".lrodata")
            idx = get(s.data.symbols, h.symbol) do
                error("can't locate symbol $(h.symbol) in data section")
            end
            @assert idx == 0
            @assert h.addend + 1 < length(bvec_data)
            pointer(bvec_data, h.addend + 1)
        elseif startswith(h.symbol, "ffi_")
            Libdl.dlsym(Libffi_jll.libffi_handle, Symbol(h.symbol))
        else
            Libdl.dlsym(LIBC[], h.symbol)
        end
        bvec[h.offset + 1] = ptr
        push!(patched, h)
    end
    return filter!(holes) do h
        !(h in patched)
    end
end


const LIBJULIAHELPERS_PATH = Ref{String}("")
const LIBFFIHELPERS_PATH = Ref{String}("")
const LIBMWES_PATH = Ref{String}("")
const LIBJULIA = Ref{Ptr{Cvoid}}(0)
const LIBJULIAINTERNAL = Ref{Ptr{Cvoid}}(0)
const LIBC = Ref{Ptr{Cvoid}}(0)
const LIBJULIAHELPERS = Ref{Ptr{Cvoid}}(0)
const SCRATCH_DIR = Ref{String}("")
const STENCIL_DIR = Ref{String}("")
function __init__()
    project_file = joinpath(@__DIR__, "..", "Project.toml")
    project_toml = TOML.parsefile(project_file)
    uuid = Base.UUID(project_toml["uuid"])
    version = VersionNumber(project_toml["version"])
    SCRATCH_DIR[] = Scratch.get_scratch!(uuid, "CopyAndPatch-$(version)")
    STENCIL_DIR[] = joinpath(SCRATCH_DIR[], "cpjit-bin")
    LIBJULIAHELPERS_PATH[] = normpath(joinpath(STENCIL_DIR[], "libjuliahelpers.so"))
    LIBFFIHELPERS_PATH[] = normpath(joinpath(STENCIL_DIR[], "libffihelpers.so"))
    LIBMWES_PATH[] = normpath(joinpath(STENCIL_DIR[], "libmwes.so"))
    LIBJULIA[] = Libdl.dlopen(Libdl.dlpath("libjulia.so"))
    LIBJULIAINTERNAL[] = Libdl.dlopen(Libdl.dlpath("libjulia-internal.so"))
    LIBC[] = Libdl.dlopen(Libdl.dlpath("libc.so.6"))
    LIBJULIAHELPERS[] = Libdl.dlopen(LIBJULIAHELPERS_PATH[])
    init_stencils()
    return nothing
end


end
