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
function Base.setindex!(bvec::ByteVector, b::T, i) where T<:Number
    # TODO Rewrite this to use reinterpret. Will need StaticArrays to avoid allocs.
    n = sizeof(T)
    i+(n-1) <= length(bvec.d) || throw(ArgumentError("buffer overflow"))
    bb = to_unsigned(b)
    @static if is_little_endian()
        for ii in 0:n-1
            bvec.d[i+ii] = UInt8(bb >> (ii*8) & 0xFF)
        end
    else
        for ii in 0:n-1
            bvec.d[i+ii] = UInt8(bb >> ((n-1-ii)*8) & 0xFF)
        end
    end
    bvec
end
Base.setindex!(bvec::ByteVector, p::Ptr, i) = bvec[i] = UInt64(p)

function to_unsigned(x::T) where T
    @assert isbits(x)
    n = sizeof(T)
    if n == 1
        return reinterpret(UInt8,x)
    elseif n == 2
        return reinterpret(UInt16,x)
    elseif n == 4
        return reinterpret(UInt32,x)
    elseif n == 8
        return reinterpret(UInt64,x)
    end
    TODO(n)
end
