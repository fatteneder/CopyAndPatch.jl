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


include("utils.jl")
include("ffi.jl")
include("bytevector.jl")
include("lifetimes.jl")
include("machinecode.jl")
include("stencil.jl")
include("jit.jl")
include("code_native.jl")
include("extern_pkg_code.jl")
include("julia_integration.jl")


const STENCILS = Ref(Dict{String, Any}())
const MAGICNR = 0x0070605040302010


function init_stencils()
    stencildir = joinpath(@__DIR__, "..", "stencils", "bin")
    files = readdir(stencildir, join = true)
    filter!(files) do f
        endswith(f, ".json")
    end
    empty!(STENCILS[])
    for f in files
        try
            name = first(splitext(basename(f)))
            s = StencilGroup(f, name)
            bvec = ByteVector(UInt8.(only(s.code.body)))
            bvecs_data = if !isempty(s.data.body)
                [ ByteVector(UInt8.(b)) for b in s.data.body ]
            else
                [ByteVector(0)]
            end
            patch_default_deps!(bvec, bvecs_data, s)
            for h in s.code.relocations
                @assert h.kind == "R_X86_64_64"
                bvec[h.offset + 1] = MAGICNR
            end
            STENCILS[][name] = (s, bvec, bvecs_data)
        catch e
            println("Failure when processing $f")
            rethrow(e)
        end
    end
    return
end


function patch_default_deps!(bvec::ByteVector, bvecs_data::Vector{ByteVector}, s::StencilGroup)
    holes = s.code.relocations
    patched = Hole[]
    for h in holes
        startswith(h.symbol, "_JIT_") && continue
        ptr = if startswith(h.symbol, "jl_")
            p = Libdl.dlsym(LIBJULIA[], h.symbol, throw_error = false)
            if isnothing(p)
                p = Libdl.dlsym(LIBJULIAINTERNAL[], h.symbol, throw_error = false)
                if isnothing(p)
                    @warn "failed to find $(h.symbol) symbol"
                    continue
                end
            end
            p
        elseif startswith(h.symbol, "jlh_")
            Libdl.dlsym(LIBJULIAHELPERS[], h.symbol)
        elseif startswith(h.symbol, ".rodata")
            idx = get(s.data.symbols, h.symbol) do
                error("can't locate symbol $(h.symbol) in data section")
            end
            bvec_data = bvecs_data[idx + 1]
            @assert h.addend + 1 < length(bvec_data)
            pointer(bvec_data.d, h.addend + 1)
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
function __init__()
    LIBJULIAHELPERS_PATH[] = normpath(joinpath(@__DIR__, "..", "stencils", "bin", "libjuliahelpers.so"))
    LIBFFIHELPERS_PATH[] = normpath(joinpath(@__DIR__, "..", "stencils", "bin", "libffihelpers.so"))
    LIBMWES_PATH[] = normpath(joinpath(@__DIR__, "..", "stencils", "bin", "libmwes.so"))
    LIBJULIA[] = Libdl.dlopen(Libdl.dlpath("libjulia.so"))
    LIBJULIAINTERNAL[] = Libdl.dlopen(Libdl.dlpath("libjulia-internal.so"))
    LIBC[] = Libdl.dlopen(Libdl.dlpath("libc.so.6"))
    LIBJULIAHELPERS[] = Libdl.dlopen(LIBJULIAHELPERS_PATH[])
    init_stencils()
    return nothing
end


end
