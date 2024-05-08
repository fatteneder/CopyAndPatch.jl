is_little_endian() = ENDIAN_BOM == 0x04030201


unwrap(g::GlobalRef) = getproperty(g.mod, g.name)
iscallable(@nospecialize(f)) = !isempty(methods(f))


# TODO Remove this, because we cannot reliably query jl_function_t * (clarified on Slack)
function pointer_from_function(fn::Function)
    pm = pointer_from_objref(typeof(fn).name.module)
    ps = pointer_from_objref(nameof(fn))
    pf = ccall((:jl_get_global, path_libjulia[]), Ptr{Cvoid}, (Ptr{Cvoid},Ptr{Cvoid}), pm, ps)
    @assert pf !== C_NULL
    return pf
end

function is_method_instance(mi)
    GC.@preserve mi ccall((:is_method_instance,path_libjl[]), Cint, (Any,), mi)
end
function is_bool(b)
    p = box(b)
    # no need for GC.@preserve, because it is apparent that p depends on b, assuming
    # ccall(:jl_box_bool,x) is not unsafe?
    ccall((:is_bool,path_libjl[]), Cint, (Ptr{Cvoid},), p)
end


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
# TODO path_libjulia[] not needed here, I think.
const Boxable   = Union{Bool,Int8,Int16,Int32,Int64,UInt8,UInt32,UInt64,Float32,Float64}
const Unboxable = Union{Bool,Int8,Int16,Int32,Int64,UInt8,UInt32,UInt64,Float32,Float64}
box(x::Bool) = ccall((:jl_box_bool,path_libjulia[]), Ptr{Cvoid}, (Int8,), x)
box(x::Int8) = ccall((:jl_box_int8,path_libjulia[]), Ptr{Cvoid}, (Int8,), x)
box(x::Int16) = ccall((:jl_box_int16,path_libjulia[]), Ptr{Cvoid}, (Int16,), x)
box(x::Int32) = ccall((:jl_box_int32,path_libjulia[]), Ptr{Cvoid}, (Int32,), x)
box(x::Int64) = ccall((:jl_box_int64,path_libjulia[]), Ptr{Cvoid}, (Int64,), x)
box(x::UInt8) = ccall((:jl_box_uint8,path_libjulia[]), Ptr{Cvoid}, (UInt8,), x)
box(x::UInt16) = ccall((:jl_box_uint16,path_libjulia[]), Ptr{Cvoid}, (UInt16,), x)
box(x::UInt32) = ccall((:jl_box_uint32,path_libjulia[]), Ptr{Cvoid}, (UInt32,), x)
box(x::UInt64) = ccall((:jl_box_uint64,path_libjulia[]), Ptr{Cvoid}, (UInt64,), x)
box(x::Float32) = ccall((:jl_box_float32,path_libjulia[]), Ptr{Cvoid}, (Float32,), x)
box(x::Float64) = ccall((:jl_box_float64,path_libjulia[]), Ptr{Cvoid}, (Float64,), x)
unbox(::Type{Bool}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_bool,path_libjulia[]), Bool, (Ptr{Cvoid},), ptr)
unbox(::Type{Int8}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_int8,path_libjulia[]), Int8, (Ptr{Cvoid},), ptr)
unbox(::Type{Int16}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_int16,path_libjulia[]), Int16, (Ptr{Cvoid},), ptr)
unbox(::Type{Int32}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_int32,path_libjulia[]), Int32, (Ptr{Cvoid},), ptr)
unbox(::Type{Int64}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_int64,path_libjulia[]), Int64, (Ptr{Cvoid},), ptr)
unbox(::Type{UInt8}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_uint8,path_libjulia[]), UInt8, (Ptr{Cvoid},), ptr)
unbox(::Type{UInt16}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_uint16,path_libjulia[]), UInt16, (Ptr{Cvoid},), ptr)
unbox(::Type{UInt32}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_uint32,path_libjulia[]), UInt32, (Ptr{Cvoid},), ptr)
unbox(::Type{UInt64}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_uint64,path_libjulia[]), UInt64, (Ptr{Cvoid},), ptr)
unbox(::Type{Float32}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_float32,path_libjulia[]), Float32, (Ptr{Cvoid},), ptr)
unbox(::Type{Float64}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_float64,path_libjulia[]), Float64, (Ptr{Cvoid},), ptr)
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
