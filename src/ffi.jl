# libffi offers these types: https://www.chiark.greenend.org.uk/doc/libffi-dev/html/Primitive-Types.html
# ffi_type_void ffi_type_uint8 ffi_type_sint8 ffi_type_uint16 ffi_type_sint16 ffi_type_uint32
# ffi_type_sint32 ffi_type_uint64 ffi_type_sint64 ffi_type_float ffi_type_double ffi_type_uchar
# ffi_type_schar ffi_type_ushort ffi_type_sshort ffi_type_uint ffi_type_sint ffi_type_ulong
# ffi_type_slong ffi_type_longdouble ffi_type_pointer ffi_type_complex_float ffi_type_complex_double
# ffi_type_complex_longdouble
# ---
# julia offers these types: https://docs.julialang.org/en/v1/manual/calling-c-and-fortran-code/#man-bits-types
# Cvoid Cuchar Cshort Cushort Cint Cuint Clonglong Culonglong Cintmax_t Cuintmax_t Cfloat Cdouble
# ComplexF32 ComplexF64 Cptrdiff_t Cssize_t Csize_t Cchar Clong Culong Cwchar_t
# ---
# here we define a mapping between julia's native types and ffi's types
# this should be enough to automatically map the C type alias
ffi_type(p::Type{Cvoid})      = cglobal((:ffi_type_void,libffi),p)
ffi_type(p::Type{UInt8})      = cglobal((:ffi_type_uint8,libffi),p)
ffi_type(p::Type{Int8})       = cglobal((:ffi_type_sint8,libffi),p)
ffi_type(p::Type{UInt16})     = cglobal((:ffi_type_uint16,libffi),p)
ffi_type(p::Type{Int16})      = cglobal((:ffi_type_sint16,libffi),p)
ffi_type(p::Type{UInt32})     = cglobal((:ffi_type_uint32,libffi),p)
ffi_type(p::Type{Int32})      = cglobal((:ffi_type_sint32,libffi),p)
ffi_type(p::Type{UInt64})     = cglobal((:ffi_type_uint64,libffi),p)
ffi_type(p::Type{Int64})      = cglobal((:ffi_type_sint64,libffi),p)
ffi_type(p::Type{Float32})    = cglobal((:ffi_type_float,libffi),p)
ffi_type(p::Type{Float64})    = cglobal((:ffi_type_double,libffi),p)
ffi_type(p::Type{ComplexF32}) = cglobal((:ffi_type_complex_float,libffi),p)
ffi_type(p::Type{ComplexF64}) = cglobal((:ffi_type_complex_double,libffi),p)
ffi_type(p::Type{Cstring})    = cglobal((:ffi_type_pointer,libffi),p)
ffi_type(p::Type{Cwstring})   = ffi_type(Ptr{Cwchar_t})
ffi_type(@nospecialize(p::Type{Ptr{T}})) where T = cglobal((:ffi_type_pointer,libffi),p)
ffi_type(@nospecialize(t))    = (isconcretetype(t)) ? ffi_type_struct(t) : ffi_type(Ptr{Cvoid})
# Note for AArch64 (from julia/src/ccalltests.c)
# `i128` is a native type on aarch64 so the type here is wrong.
# However, it happens to have the same calling convention with `[2 x i64]`
# when used as first argument or return value.
struct MimicInt128
    x::Int64
    y::Int64
end
ffi_type(p::Type{Int128})     = ffi_type_struct(MimicInt128)
ffi_type(p::Type{String})     = ffi_type(Ptr{Cvoid})
ffi_type(@nospecialize(p::Type{<:Array})) = ffi_type(fieldtype(p, :ref))
ffi_type(@nospecialize(p::Type{<:GenericMemoryRef{<:Any,T,Core.CPU}})) where {T} = ffi_type(Ptr{T})

# wrappers for libffihelper.so
ffi_default_abi() = @ccall libffihelpers_path[].ffi_default_abi()::Cint
sizeof_ffi_cif() = @ccall libffihelpers_path[].sizeof_ffi_cif()::Csize_t
sizeof_ffi_arg() = @ccall libffihelpers_path[].sizeof_ffi_arg()::Csize_t
sizeof_ffi_type() = @ccall libffihelpers_path[].sizeof_ffi_type()::Csize_t
ffi_sizeof(p::Ptr) = @ccall libffihelpers_path[].get_size_ffi_type(p::Ptr{Cvoid})::Csize_t

const Ctypes = Union{Cchar,Cuchar,Cshort,Cstring,Cushort,Cint,Cuint,Clong,Culong,
                     Clonglong,Culonglong,Cintmax_t,Cuintmax_t,Csize_t,Cssize_t,
                     Cptrdiff_t,Cwchar_t,Cwstring,Cfloat,Cdouble,Cvoid}
function to_c_type(t)
    return if t <: Ctypes
        return t
    else
        return Ptr{Cvoid}
    end
end

const FFI_TYPE_CACHE = Dict{Any,Tuple{Vector{UInt8},Vector{Ptr{Cvoid}}}}()
function ffi_type_struct(@nospecialize(t::Type{T})) where T
    if haskey(FFI_TYPE_CACHE, T)
        return pointer(FFI_TYPE_CACHE[T][1])
    end
    n = fieldcount(T)
    elements = Vector{Ptr{Cvoid}}(undef, n+1) # +1 for null terminator
    for i in 1:n
        elements[i] = ffi_type(fieldtype(T,i))
    end
    elements[end] = C_NULL
    mem_ffi_type = Vector{UInt8}(undef, sizeof_ffi_type())
    @ccall libffihelpers_path[].setup_ffi_type_struct(mem_ffi_type::Ref{UInt8},
                                                      elements::Ref{Ptr{Cvoid}})::Cvoid
    ffi_offsets = Vector{Csize_t}(undef, n)
    default_abi = ffi_default_abi()
    status = @ccall libffi_path.ffi_get_struct_offsets(default_abi::Cint,
                                                       mem_ffi_type::Ref{UInt8},
                                                       ffi_offsets::Ref{Csize_t})::Cint
    if status != 0
        msg = "Failed to setup a ffi struct type for $T; ffi_get_struct_offsets returned status "
        if status == 1
            error(msg * "FFI_BAD_TYPEDEF")
        elseif status == 2
            error(msg * "FFI_BAD_ABI")
        elseif status == 3
            error(msg * "FFI_BAD_ARGTYPE")
        else
            error(msg * "unknown error code $status")
        end
    end
    if any(i -> ffi_offsets[i] != Csize_t(fieldoffset(T,i)), 1:n)
        jl_offsets = [ fieldoffset(T,i) for i in 1:n ]
        jl_types   = [ fieldtype(T,i) for i in 1:n ]
        error("""Mismatch in field offsets of type $T
                 Field types: $(join(jl_types,", "))
                 Offsets:
                     Julia:  $(join(jl_offsets,", "))
                     libffi: $(join(Int64.(ffi_offsets),", "))
              """)
    end
    FFI_TYPE_CACHE[T] = (mem_ffi_type, elements)
    return pointer(mem_ffi_type)
end

mutable struct Ffi_cif
    mem_cif::Vector{UInt8}
    p::Ptr{Cvoid}
    rettype::Type
    argtypes::Vector{Type}
    ffi_rettype::Ptr{Cvoid}
    ffi_argtypes::Vector{Ptr{Cvoid}}
    slots::Vector{Ptr{Cvoid}}

    function Ffi_cif(@nospecialize(rettype::Type{T}), @nospecialize(argtypes::NTuple{N})) where {T,N}
        if !isconcretetype(T) && T !== Any && !(T <: Ref)
            throw(ArgumentError("$T is an invalid return type, " *
                                "see the @ccall return type translation guide in the manual"))
        end
        if T <: Ref && !(T <: Ptr) && !isconcretetype(eltype(T))
            throw(ArgumentError("$T is an invalid return type, " *
                                "see the @ccall return type translation guide in the manual"))
        end
        ffi_rettype = ffi_type(T)
        if any(a -> a === Cvoid, argtypes)
            throw(ArgumentError("Encountered bad argument type Cvoid"))
        end
        ffi_argtypes = N == 0 ? C_NULL : Ptr{Cvoid}[ ffi_type(at) for at in argtypes ]
        sz_cif = sizeof_ffi_cif()
        @assert sz_cif > 0
        mem_cif = Vector{UInt8}(undef, sizeof(UInt8)*sz_cif)
        p_cif = pointer(mem_cif)
        default_abi = ffi_default_abi()
        status = @ccall libffi_path.ffi_prep_cif(
                                p_cif::Ptr{Cvoid}, default_abi::Cint, N::Cint,
                                ffi_rettype::Ptr{Cvoid}, ffi_argtypes::Ptr{Ptr{Cvoid}}
                                )::Cint
        if status == 0 # = FFI_OK
            slots = Vector{Ptr{Cvoid}}(undef, 2*N)
            return new(mem_cif, p_cif, T, [ a for a in argtypes ],
                       ffi_rettype, N == 0 ? Ptr{Cvoid}[] : ffi_argtypes, slots)
        else
            msg = "Failed to prepare ffi_cif for f(::$(join(argtypes,",::")))::$T; ffi_prep_cif returned status "
            if status == 1
                error(msg * "FFI_BAD_TYPEDEF")
            elseif status == 2
                error(msg * "FFI_BAD_ABI")
            elseif status == 3
                error(msg * "FFI_BAD_ARGTYPE")
            else
                error(msg * "unknown error code $status")
            end
        end
    end
end
Ffi_cif(@nospecialize(rettype::Type), @nospecialize(s::Core.SimpleVector)) =
    Ffi_cif(rettype, tuple(s...))

Base.pointer(cif::Ffi_cif) = cif.p

function ffi_call(cif::Ffi_cif, fn::Ptr{Cvoid}, @nospecialize(args::Vector))
    if fn === C_NULL
        throw(ArgumentError("Function ptr can't be NULL"))
    end
    N = length(cif.argtypes)
    if N != length(args)
        throw(ArgumentError("Number of arguments must match with the Ffi_cif's defintion, " *
                            "found $(length(args)) vs $N"))
    end

    # return value memory
    sz_ret = if cif.rettype <: Ctypes || cif.rettype === Any || cif.rettype <: Ref
        sizeof_ffi_arg()
    else # its a concrete type and fn returns-by-copy
        ffi_sizeof(cif.ffi_rettype)
    end
    mem_ret = zeros(Int8, sz_ret)

    # slots memory
    static_prms = Vector{UInt8}[]
    slots = cif.slots
    # TODO I think this and call(::MachineCode, ...) should be the same,
    # but they aren't atm. There might be something wrong somewhere.
    for (i,a) in enumerate(args)
        if a isa Boxable
            if cif.argtypes[i] === Any
                slots[N+i] = box(a)
                slots[i] = pointer(slots, N+i)
            else
                slots[i] = box(a)
            end
        elseif a isa AbstractArray
            slots[i] = cif.argtypes[i] <: Ptr ? value_pointer(a) : pointer(a)
        elseif isconcretetype(cif.argtypes[i])
            @assert isconcretetype(cif.argtypes[i])
            mem = Vector{UInt8}(undef, sizeof(cif.argtypes[i]))
            push!(static_prms, mem)
            GC.@preserve mem begin
                unsafe_copyto!(pointer(mem), Base.unsafe_convert(Ptr{UInt8}, value_pointer(a)), sizeof(a))
            end
            slots[i] = pointer(mem)
        else
            slots[N+i] = value_pointer(a)
            slots[i] = pointer(slots, N+i)
        end
    end

    GC.@preserve cif args static_prms mem_ret begin
        @ccall libffi_path.ffi_call(cif.p::Ptr{Cvoid}, fn::Ptr{Cvoid},
                                    mem_ret::Ptr{Cvoid}, slots::Ptr{Ptr{Cvoid}})::Cvoid
        return if isbitstype(cif.rettype)
            @ccall jl_new_bits(cif.rettype::Any, mem_ret::Ptr{Cvoid})::Any
        elseif cif.rettype === Any || cif.rettype <: Ref
            unsafe_pointer_to_objref(unsafe_load(Ptr{Ptr{Cvoid}}(pointer(mem_ret))))
        else
            @ccall libjuliahelpers_path[].jlh_convert_to_jl_value(cif.rettype::Any,
                                                                  mem_ret::Ptr{Cvoid})::Any
        end
    end
end
