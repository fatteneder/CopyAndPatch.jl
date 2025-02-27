struct ByteVector <: AbstractVector{UInt8}
    d::Vector{UInt8}
    ByteVector(v::AbstractVector{UInt8}) = new(v)
end
ByteVector(sz::Integer) = ByteVector(zeros(UInt8, sz))
ByteVector(v::AbstractVector{<:Unsigned}) = ByteVector(reinterpret(UInt8, v))


function Base.fill!(b::ByteVector, v::T) where {T <: Number}
    n = sizeof(T)
    for i in 1:n:(length(b) - n)
        b[i] = v
    end
    return
end
Base.size(b::ByteVector) = size(b.d)
Base.length(b::ByteVector, ::Type{T}) where {T <: Unsigned} = length(b) ÷ sizeof(T)
Base.getindex(b::ByteVector, i) = b.d[i]
function Base.getindex(b::ByteVector, ::Type{T}, i) where {T <: Unsigned}
    sz = sizeof(T)
    start = sz * (i - 1) + 1
    stop = sz * i
    1 <= start <= stop <= length(b) || throw(BoundsError(b, i))
    return first(reinterpret(T, b[start:stop]))
end
function Base.setindex!(bvec::ByteVector, b::T, i) where {T <: Number}
    n = sizeof(T)
    i + n - 1 <= length(bvec.d) || throw(BoundsError(b, i))
    @views bvec.d[i:(i + n - 1)] .= reinterpret(UInt8, [b])
    return bvec
end
Base.setindex!(bvec::ByteVector, p::Ptr, i) = bvec[i] = UInt64(p)
function Base.setindex!(bvec::ByteVector, b::T, ::Type{S}, i) where {T <: Union{Ptr, Number}, S <: Unsigned}
    return bvec[sizeof(T) * (i - 1) + 1] = b
end


# TODO Boundscheck?
Base.pointer(bvec::ByteVector) = pointer(bvec, 1)
Base.pointer(bvec::ByteVector, i::Integer) = pointer(bvec, UInt8, i)
Base.pointer(bvec::ByteVector, ::Type{T}, i::Integer) where {T <: Unsigned} = pointer(bvec.d, sizeof(T) * (i - 1) + 1)
