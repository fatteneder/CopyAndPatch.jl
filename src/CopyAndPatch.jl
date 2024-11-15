module CopyAndPatch


import Base: isexpr, code_typed, unsafe_convert, Iterators
import Base.Libc.Libdl: dlpath, dlopen, dlsym
import Core: MethodInstance, CodeInfo
import InteractiveUtils: print_native
import JSON: parsefile
import Libffi_jll: libffi_handle, libffi_path, libffi
import Logging: SimpleLogger, with_logger
import Mmap: mmap
import Printf: Format, format
import REPL
import REPL: TerminalMenus


export jit


include("utils.jl")
include("ffi.jl")
include("bytevector.jl")
include("machinecode.jl")
include("stencil.jl")
include("jit.jl")
include("code_native.jl")


const STENCILS = Ref(Dict{String,Any}())
const MAGICNR = 0x0070605040302010


function init_stencils()
    stencildir = joinpath(@__DIR__, "..", "stencils", "bin")
    files = readdir(stencildir, join=true)
    filter!(files) do f
        endswith(f, ".json")
    end
    empty!(STENCILS[])
    for f in files
        try
            s = StencilGroup(f)
            bvec = ByteVector(UInt8.(only(s.code.body)))
            bvecs_data = if !isempty(s.data.body)
                [ ByteVector(UInt8.(b)) for b in s.data.body ]
            else
                [ ByteVector(0) ]
            end
            patch_default_deps!(bvec, bvecs_data, s)
            for h in s.code.relocations
                @assert h.kind == "R_X86_64_64"
                bvec[h.offset+1] = MAGICNR
            end
            name = first(splitext(basename(f)))
            STENCILS[][name] = (s,bvec,bvecs_data)
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
            p = dlsym(libjulia[], h.symbol, throw_error=false)
            if isnothing(p)
                p = dlsym(libjuliainternal[], h.symbol, throw_error=false)
                if isnothing(p)
                    @warn "failed to find $(h.symbol) symbol"
                    continue
                end
            end
            p
        elseif startswith(h.symbol, "jlh_")
            dlsym(libjuliahelpers[], h.symbol)
        elseif startswith(h.symbol, ".rodata")
            idx = get(s.data.symbols, h.symbol) do
                error("can't locate symbol $(h.symbol) in data section")
            end
            bvec_data = bvecs_data[idx+1]
            @assert h.addend+1 < length(bvec_data)
            pointer(bvec_data.d, h.addend+1)
        elseif startswith(h.symbol, "ffi_")
            dlsym(libffi_handle, Symbol(h.symbol))
        else
            dlsym(libc[], h.symbol)
        end
        bvec[h.offset+1] = ptr
        push!(patched, h)
    end
    filter!(holes) do h
        !(h in patched)
    end
end

function install_hooks()
    if !isdefined(Base, :cpjit)
        @eval Base function cpjit(ci::Core.CodeInstance, src::Core.CodeInfo)
            rettype = getfield(ci, :rettype)
            fn, argtypes... = ci.def.specTypes.parameters
            try
                # TODO Remove the try ... catch block from jl_cpjit_compile_codeinst_impl
                @debug "cpjit: compiling $fn($(join("::".*string.(argtypes),",")))::$(rettype)"
                mc = $(jit)(src, fn, rettype, Tuple(argtypes))
                @atomic :monotonic ci.cpjit_mc = mc
                return Cint(1)
            catch e
                @debug "cpjit: compilation of $fn($(join("::".*string.(argtypes),",")))::$(rettype) failed with" current_exceptions()
                return Cint(0)
            end
        end
    end
    if !isdefined(Base, :cpjit_call)
        @eval Base function cpjit_call(mc::$(MachineCode), @nospecialize(args...))
            try
                @debug "cpjit_call: calling $(mc.fn)"
                cif = $(Ffi_cif)(mc.rettype, Tuple(mc.argtypes))
                return $(ffi_call)(cif, pointer(mc), [a for a in args])
            catch e
                @debug "cpjit_call: call of $(mc.fn)($(join("::".*string.(mc.argtypes),",")))::$(mc.rettype) failed with" current_exceptions()
                return nothing
            end
        end
    end
end

function enable(toggle::Bool)
    install_hooks()
    @ccall jl_use_cpjit_set(toggle::Cint)::Cvoid
end


const libjuliahelpers_path = Ref{String}("")
const libffihelpers_path = Ref{String}("")
const libmwes_path = Ref{String}("")
const libjulia = Ref{Ptr{Cvoid}}(0)
const libjuliainternal = Ref{Ptr{Cvoid}}(0)
const libc = Ref{Ptr{Cvoid}}(0)
const libjuliahelpers = Ref{Ptr{Cvoid}}(0)
function __init__()
    libjuliahelpers_path[] = normpath(joinpath(@__DIR__, "..", "stencils", "bin", "libjuliahelpers.so"))
    libffihelpers_path[] = normpath(joinpath(@__DIR__, "..", "stencils", "bin", "libffihelpers.so"))
    libmwes_path[] = normpath(joinpath(@__DIR__, "..", "stencils", "bin", "libmwes.so"))
    libjulia[] = dlopen(dlpath("libjulia.so"))
    libjuliainternal[] = dlopen(dlpath("libjulia-internal.so"))
    libc[] = dlopen(dlpath("libc.so.6"))
    libjuliahelpers[] = dlopen(libjuliahelpers_path[])
    init_stencils()
    nothing
end


end
