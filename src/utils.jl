TODO() = error("Not implemented yet")
TODO(msg) = TODO("Not implemented yet", msg)
TODO(prefix, msg) = error(prefix, " ", msg)


is_little_endian() = ENDIAN_BOM == 0x04030201


unwrap(g::GlobalRef) = getproperty(g.mod, g.name)
iscallable(@nospecialize(f)) = !isempty(methods(f))


# from stencils/libjuliahelpers.c
is_method_instance(mi) = @ccall LIBJULIAHELPERS_PATH[].is_method_instance(mi::Any)::Cint
function is_bool(b)
    p = box(b)
    GC.@preserve b @ccall LIBJULIAHELPERS_PATH[].is_bool(p::Ptr{Cvoid})::Cint
end
is_concrete_immutable(@nospecialize(x::DataType)) =
    @ccall LIBJULIAHELPERS_PATH[].jl_is_concrete_immutable(x::Any)::Bool
is_pointerfree(@nospecialize(x::DataType)) =
    @ccall LIBJULIAHELPERS_PATH[].jl_is_pointerfree(x::Any)::Bool

# from julia_internal.h
# TODO What about Base.allocatedinline?
datatype_isinlinealloc(@nospecialize(ty::Ref{T})) where T = datatype_isinlinealloc(T)
function datatype_isinlinealloc(@nospecialize(ty::DataType))
    ptrfree = is_pointerfree(ty)
    r = @ccall jl_datatype_isinlinealloc(ty::Any, ptrfree::Cint)::Cint
    return r != 0
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
#   unsafe_string(@ccall jl_typeof_str(p2::Ptr{Cvoid})::Cstring) # segfaults in global scope,
#                                                                # but gives "ImmutDummy" inside
#                                                                # function
#end
# ```
# jl_value_ptr actually returns jl_value_t *, so we should be using a ::Any return type
# however, doing so would convert the returned value into a julia type
# using instead ::Ptr{Cvoid} we obtain an address that seems to be working with the rest
# FWIW this is also how its being used in code_typed outputs.
value_pointer(@nospecialize(x)) = @ccall jl_value_ptr(x::Any)::Ptr{Cvoid}


# missing a few:
# - jl_value_t *jl_box_char(uint32_t x);
# - jl_value_t *jl_box_ssavalue(size_t x);
# - jl_value_t *jl_box_slotnumber(size_t x);
#
# - void *jl_unbox_voidpointer(jl_value_t *v) JL_NOTSAFEPOINT;
# - uint8_t *jl_unbox_uint8pointer(jl_value_t *v) JL_NOTSAFEPOINT;
#
# Here is a list of default primitives:
# https://docs.julialang.org/en/v1/manual/types/#Primitive-Types
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
box(x::Ptr{UInt8})     = @ccall jl_box_uint8pointer(x::Ptr{UInt8})::Ptr{Cvoid}
box(x::Ptr{T}) where T = @ccall jl_box_voidpointer(x::Ptr{T})::Ptr{Cvoid}
unbox(::Type{Bool}, ptr::Ptr{Cvoid})           = @ccall jl_unbox_bool(ptr::Ptr{Cvoid})::Bool
unbox(::Type{Int8}, ptr::Ptr{Cvoid})           = @ccall jl_unbox_int8(ptr::Ptr{Cvoid})::Int8
unbox(::Type{Int16}, ptr::Ptr{Cvoid})          = @ccall jl_unbox_int16(ptr::Ptr{Cvoid})::Int16
unbox(::Type{Int32}, ptr::Ptr{Cvoid})          = @ccall jl_unbox_int32(ptr::Ptr{Cvoid})::Int32
unbox(::Type{Int64}, ptr::Ptr{Cvoid})          = @ccall jl_unbox_int64(ptr::Ptr{Cvoid})::Int64
unbox(::Type{UInt8}, ptr::Ptr{Cvoid})          = @ccall jl_unbox_uint8(ptr::Ptr{Cvoid})::UInt8
unbox(::Type{UInt16}, ptr::Ptr{Cvoid})         = @ccall jl_unbox_uint16(ptr::Ptr{Cvoid})::UInt16
unbox(::Type{UInt32}, ptr::Ptr{Cvoid})         = @ccall jl_unbox_uint32(ptr::Ptr{Cvoid})::UInt32
unbox(::Type{UInt64}, ptr::Ptr{Cvoid})         = @ccall jl_unbox_uint64(ptr::Ptr{Cvoid})::UInt64
unbox(::Type{Float32}, ptr::Ptr{Cvoid})        = @ccall jl_unbox_float32(ptr::Ptr{Cvoid})::Float32
unbox(::Type{Float64}, ptr::Ptr{Cvoid})        = @ccall jl_unbox_float64(ptr::Ptr{Cvoid})::Float64
unbox(::Type{Ptr{UInt8}}, ptr::Ptr{Cvoid})     = @ccall jl_unbox_uint8pointer(ptr::Ptr{UInt8})::Ptr{UInt8}
unbox(::Type{Ptr{T}}, ptr::Ptr{Cvoid}) where T = @ccall jl_unbox_voidpointer(ptr::Ptr{Cvoid})::Ptr{T}
# TODO This def needed?
unbox(T::Type, ptr::Integer) = unbox(T, Ptr{Cvoid}(UInt64(ptr)))
