struct ByteVector <: AbstractVector{UInt8}
    d::Vector{UInt8}
    ByteVector(v::AbstractVector{UInt8}) = new(v)
end
ByteVector(sz::Integer) = ByteVector(zeros(UInt8, sz))
ByteVector(v::AbstractVector{<:Unsigned}) = ByteVector(reinterpret(UInt8, v))


function Base.fill!(b::ByteVector, v::T) where T<:Number
    n = sizeof(T)
    for i in 1:n:length(b)-n
        b[i] = v
    end
end
Base.size(b::ByteVector) = size(b.d)
Base.getindex(b::ByteVector, i) = b.d[i]
Base.getindex(b::ByteVector, ::Type{T}, i) where {T<:Unsigned} = b[sizeof(T)*(i-1)+1]
function Base.setindex!(bvec::ByteVector, b::T, i) where T<:Number
    n = sizeof(T)
    i+n-1 <= length(bvec.d) || throw(ArgumentError("buffer overflow"))
    @views bvec.d[i:i+n-1] .= reinterpret(UInt8, [b])
    bvec
end
Base.setindex!(bvec::ByteVector, p::Ptr, i) = bvec[i] = UInt64(p)
function Base.setindex!(bvec::ByteVector, b::T, ::Type{S}, i) where {T<:Union{Ptr,Number},S<:Unsigned}
    bvec[sizeof(T)*(i-1)+1] = b
end


Base.pointer(bvec::ByteVector) = pointer(bvec, 1)
Base.pointer(bvec::ByteVector, i::Integer) = pointer(bvec, UInt8, i)
Base.pointer(bvec::ByteVector, ::Type{T}, i::Integer) where {T<:Unsigned} = pointer(bvec.d, sizeof(T)*(i-1)+1)
