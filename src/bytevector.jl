struct ByteVector <: AbstractVector{UInt8}
    d::Vector{UInt8}
    ByteVector(v::AbstractVector{UInt8}) = new(v)
end
ByteVector(sz::Integer) = ByteVector(zeros(UInt8, sz))
ByteVector(v::AbstractVector{<:Unsigned}) = ByteVector(reinterpret(UInt8, v))


Base.size(b::ByteVector) = size(b.d)
Base.getindex(b::ByteVector, i) = b.d[i]
Base.setindex!(b::ByteVector, bb::UInt8, i) = b.d[i] = bb
Base.setindex!(b::ByteVector, p::Ptr, i) = b[i] = UInt64(p)
function Base.setindex!(b::ByteVector, bb::T, i) where T<:Unsigned
    n = sizeof(T)
    i+n <= length(b.d) || throw(ArgumentError("buffer overflow"))
    @static if is_little_endian()
        for ii in 0:n-1
            b[i+ii] = UInt8(bb >> (ii*8) & 0xFF)
        end
    else
        for ii in 0:n-1
            b[i+ii] = UInt8(bb >> ((n-1-ii)*8) & 0xFF)
        end
    end
    b
end
