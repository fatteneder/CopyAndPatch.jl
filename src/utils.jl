is_little_endian() = ENDIAN_BOM == 0x04030201


unwrap(g::GlobalRef) = getproperty(g.mod, g.name)
iscallable(@nospecialize(f)) = !isempty(methods(f))


# TODO Remove this, because we cannot reliably query jl_function_t * (clarified on Slack)
function pointer_from_function(fn::Function)
    pm = pointer_from_objref(typeof(fn).name.module)
    ps = pointer_from_objref(nameof(fn))
    pf = @ccall jl_get_global(pm::Ptr{Cvoid}, ps::Ptr{Cvoid})::Ptr{Cvoid}
    @assert pf !== C_NULL
    return pf
end

is_method_instance(mi) = @ccall libjuliahelpers_path[].is_method_instance(mi::Any)::Cint
function is_bool(b)
    p = box(b)
    GC.@preserve b @ccall libjuliahelpers_path[].is_bool(p::Ptr{Cvoid})::Cint
end


# @nospecialize is needed here to return the desired pointer also for immutables.
# IIUC without it jl_value_ptr will not see the immutable container and instead
# return a pointer to the first field in x.
#
# Consider this MWE:
# ```julia
# struct ImmutDummy
#   x
#   y
# end
#
# x = ImmutDummy("string", 1)
# p = @ccall jl_value_ptr(x::Any)::Ptr{Cvoid}
# p1 = value_pointer(x)
# p2 = value_pointer_without_nospecialize(x)
#
# GC.@preserve x begin
#   unsafe_string(@ccall jl_typeof_str(p::Ptr{Cvoid})::Cstring)  # "ImmutDummy"
#   unsafe_string(@ccall jl_typeof_str(p1::Ptr{Cvoid})::Cstring) # "ImmutDummy"
#   unsafe_string(@ccall jl_typeof_str(p2::Ptr{Cvoid})::Cstring) # segfaults in global scope, but gives "ImmutDummy" inside function
#end
# ```
value_pointer(@nospecialize(x)) = @ccall jl_value_ptr(x::Any)::Ptr{Cvoid}


# missing a few:
# - jl_value_t *jl_box_char(uint32_t x);
# - jl_value_t *jl_box_voidpointer(void *x);
# - jl_value_t *jl_box_uint8pointer(uint8_t *x);
# - jl_value_t *jl_box_ssavalue(size_t x);
# - jl_value_t *jl_box_slotnumber(size_t x);
#
# - void *jl_unbox_voidpointer(jl_value_t *v) JL_NOTSAFEPOINT;
# - uint8_t *jl_unbox_uint8pointer(jl_value_t *v) JL_NOTSAFEPOINT;
#
# Here is a list of default primitives: https://docs.julialang.org/en/v1/manual/types/#Primitive-Types
# It also contains Float16, UInt128, Int128, but we don't have box methods for them.
# Why? Because they are emulated in software?
#
# Why are there box methods for char, ssavalue, slotnumber, but no unbox methods?
#
const Boxable   = Union{Bool,Int8,Int16,Int32,Int64,UInt8,UInt32,UInt64,Float32,Float64,Ptr}
const Unboxable = Union{Bool,Int8,Int16,Int32,Int64,UInt8,UInt32,UInt64,Float32,Float64}
box(x::Bool)           = @ccall jl_box_bool(x::Int8)::Ptr{Cvoid}
box(x::Int8)           = @ccall jl_box_int8(x::Int8)::Ptr{Cvoid}
box(x::Int16)          = @ccall jl_box_int16(x::Int16)::Ptr{Cvoid}
box(x::Int32)          = @ccall jl_box_int32(x::Int32)::Ptr{Cvoid}
box(x::Int64)          = @ccall jl_box_int64(x::Int64)::Ptr{Cvoid}
box(x::UInt8)          = @ccall jl_box_uint8(x::UInt8)::Ptr{Cvoid}
box(x::UInt16)         = @ccall jl_box_uint16(x::UInt16)::Ptr{Cvoid}
box(x::UInt32)         = @ccall jl_box_uint32(x::UInt32)::Ptr{Cvoid}
box(x::UInt64)         = @ccall jl_box_uint64(x::UInt64)::Ptr{Cvoid}
box(x::Float32)        = @ccall jl_box_float32(x::Float32)::Ptr{Cvoid}
box(x::Float64)        = @ccall jl_box_float64(x::Float64)::Ptr{Cvoid}
box(x::Ptr{UInt8})     = @ccall jl_box_uint8pointer(x::Any)::Ptr{Cvoid}
box(x::Ptr{T}) where T = @ccall jl_box_voidpointer(x::Any)::Ptr{Cvoid}
unbox(::Type{Bool}, ptr::Ptr{Cvoid})    = @ccall jl_unbox_bool(ptr::Ptr{Cvoid})::Bool
unbox(::Type{Int8}, ptr::Ptr{Cvoid})    = @ccall jl_unbox_int8(ptr::Ptr{Cvoid})::Int8
unbox(::Type{Int16}, ptr::Ptr{Cvoid})   = @ccall jl_unbox_int16(ptr::Ptr{Cvoid})::Int16
unbox(::Type{Int32}, ptr::Ptr{Cvoid})   = @ccall jl_unbox_int32(ptr::Ptr{Cvoid})::Int32
unbox(::Type{Int64}, ptr::Ptr{Cvoid})   = @ccall jl_unbox_int64(ptr::Ptr{Cvoid})::Int64
unbox(::Type{UInt8}, ptr::Ptr{Cvoid})   = @ccall jl_unbox_uint8(ptr::Ptr{Cvoid})::UInt8
unbox(::Type{UInt16}, ptr::Ptr{Cvoid})  = @ccall jl_unbox_uint16(ptr::Ptr{Cvoid})::UInt16
unbox(::Type{UInt32}, ptr::Ptr{Cvoid})  = @ccall jl_unbox_uint32(ptr::Ptr{Cvoid})::UInt32
unbox(::Type{UInt64}, ptr::Ptr{Cvoid})  = @ccall jl_unbox_uint64(ptr::Ptr{Cvoid})::UInt64
unbox(::Type{Float32}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_float32(ptr::Ptr{Cvoid})::Float32
unbox(::Type{Float64}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_float64(ptr::Ptr{Cvoid})::Float64
unbox(T::Type, ptr::Integer) = unbox(T, Ptr{Cvoid}(UInt64(ptr)))


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
# here we define a mapping between julia's types and ffi's types
# a few notes:
# - ffi uses macros to define some types, e.g. ffi_type_sshort, so we resolve them manually here
#   this might need to be adjusted depending on the system for which libffi is configured
# - some C types can be identical, e.g. Cintmax_t = Clonglong = Int64 on x86_64-redhat-linux
#   because of that we define ffi_type below only for the 'unique' ones to avoid overwrite warnings
# - there are at least four system dependent types, Cchar, Clong, Culong, Cwchar_t, which
#   we will need special care later on
for (jl_t, ffi_t) in [
                       (Cvoid,      :ffi_type_void),
                       (Cuchar,     :ffi_type_uint8),
                       (Cshort,     :ffi_type_sint16), # ffi_type_sshort
                       (Cushort,    :ffi_type_uint16), # ffi_type_ushort
                       (Cint,       :ffi_type_sint32), # ffi_type_sint
                       (Cuint,      :ffi_type_uint32), # ffi_type_uint
                       (Cfloat,     :ffi_type_float),
                       (Cdouble,    :ffi_type_double),
                       (Clonglong,  :ffi_type_sint64),
                       (Culonglong, :ffi_type_uint64),
                       (ComplexF32, :ffi_type_complex_float),
                       (ComplexF64, :ffi_type_complex_double),
                   ]
    @eval ffi_type(::Type{$jl_t}) = dlsym(libffi_handle,$(QuoteNode(ffi_t)))
end
ffi_type(p::Type{Cstring}) = dlsym(libffi_handle,:ffi_type_pointer)
ffi_type(p::Type{Ptr}) = dlsym(libffi_handle,:ffi_type_pointer)
ffi_type(@nospecialize(p::Type{Ptr{T}})) where T = dlsym(libffi_handle,:ffi_type_pointer)

const Ctypes = Union{Cchar,Cuchar,Cshort,Cstring,Cushort,Cint,Cuint,Clong,Culong,
                     Clonglong,Culonglong,Cintmax_t,Cuintmax_t,Csize_t,Cssize_t,
                     Cptrdiff_t,Cwchar_t,Cwstring,Cfloat,Cdouble,Cvoid}
function to_ffi_type(t)
    return if t <: Ctypes
        return ffi_type(t)
    else
        return ffi_type(Ptr{Cvoid})
    end
end


mutable struct Ffi_cif
    p::Ptr{Cvoid}
    rettype::Type
    argtypes::Vector{Type}
    slots::Vector{Ptr{Cvoid}}

    function Ffi_cif(@nospecialize(rettype::Type{T}), @nospecialize(argtypes::NTuple{N,Type})) where {T,N}
        # TODO Do we need to hold onto ffi_rettype, ffi_argtypes for the lifetime of Ffi_cfi?
        ffi_rettype = to_ffi_type(rettype)
        if any(a -> a === Cvoid, argtypes)
            throw(ArgumentError("Encountered bad argument type Cvoid"))
        end
        ffi_argtypes = N == 0 ? C_NULL : [ to_ffi_type(at) for at in argtypes ]
        sz_cif = @ccall libffihelpers_path[].get_sizeof_ffi_cif()::Csize_t
        @assert sz_cif > 0
        p_cif = Libc.malloc(sz_cif)
        @assert p_cif !== C_NULL
        default_abi = @ccall libffihelpers_path[].get_ffi_default_abi()::Cint
        # https://www.chiark.greenend.org.uk/doc/libffi-dev/html/The-Basics.html
        status = @ccall libffi_path.ffi_prep_cif(
                                p_cif::Ptr{Cvoid}, default_abi::Cint, N::Cint,
                                ffi_rettype::Ptr{Cvoid}, ffi_argtypes::Ptr{Ptr{Cvoid}}
                                )::Cint
        if status == 0 # = FFI_OK
            slots = Vector{Ptr{Cvoid}}(undef, 2*N)
            cif = new(p_cif, T, [ a for a in argtypes ], slots)
            return finalizer(cif) do cif
                if cif.p !== C_NULL
                    Libc.free(cif.p)
                    cif.p = C_NULL
                end
            end
        else
            msg = "Failed to prepare ffi_cif for f(::$(join(argtypes,",::")))::$T; ffi_prep_cif returned "
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
Ffi_cif(@nospecialize(rettype::Type), @nospecialize(s::Core.SimpleVector)) = Ffi_cif(rettype, tuple(s...))

Base.pointer(cif::Ffi_cif) = cif.p

function ffi_call(cif::Ffi_cif, fn::Ptr{Cvoid}, @nospecialize(args::Vector))
    @assert fn !== C_NULL
    N = length(cif.argtypes)
    @assert N == length(args)
    # TODO Would like to always use Ref{cif.rettype}(), but for non-is-bits types this
    # initializes to #undef and errors inside ffi_call.
    ret = cif.rettype <: Ctypes ?  Ref{cif.rettype}() : Ref{Ptr{Cvoid}}(C_NULL)
    slots = cif.slots
    for (i,a) in enumerate(args)
        if a isa Boxable
            if cif.argtypes[i] <: Ptr
                slots[N+i] = box(a)
                slots[i] = pointer(slots, N+i)
            else
                slots[i] = box(a)
            end
        elseif a isa AbstractArray
            slots[i] = value_pointer(a)
        else
            slots[N+i] = value_pointer(a)
            slots[i] = pointer(slots, N+i)
        end
    end
    GC.@preserve cif args begin
        @ccall libffi_path.ffi_call(cif.p::Ptr{Cvoid}, fn::Ptr{Cvoid},
                                    ret::Ptr{Cvoid}, slots::Ptr{Cvoid})::Cvoid
    end
    return if cif.rettype <: Ptr
        Base.unsafe_convert(cif.rettype, ret[])
    elseif cif.rettype <: Ctypes
        ret[]
    else
        unsafe_pointer_to_objref(ret[])
    end
end
