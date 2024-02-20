mutable struct MachineCode
    const buf::Vector{UInt8}
    offset::Int
    function MachineCode(sz::Int)
        if sz <= 0
            throw(ArgumentError("size must be positive"))
        end
        buf = mmap(Vector{UInt8}, sz, shared=false, exec=true)
        return new(buf, 0)
    end
end


struct CompiledMachineCode{RetType,ArgTypes}
    a::MachineCode # to keep the target of ptr alive
    ptr::Ptr{Cvoid}
    function CompiledMachineCode(a::MachineCode,rettype::DataType,argtypes::NTuple{N,DataType}) where N
        ptr = pointer(a.buf)
        new{rettype,Tuple{argtypes...}}(a, ptr)
    end
end


baremodule HoleValues
import Base: @enum
@enum HoleValue CODE CONTINUE DATA EXECUTOR GOT OPARG OPERAND TARGET TOP ZERO
export HoleValue
end


mutable struct Hole
    offset::Int64
    kind
    value
    symbol
    addend::Int64
end

struct Stencil
    body
    holes
    disassembly
    symbols
    offsets
    relocations
end

Stencil() = Stencil([], [], [], Dict(), Dict(), [])


struct StencilGroup
    code::Stencil # actual machine code (with holes)
    data::Stencil # needed to build a header file
    global_offset_table
end


struct ByteVector <: AbstractVector{UInt8}
    d::Vector{UInt8}
    # ByteVector(sz) = ByteVector(zeros(UInt8, sz))
end
ByteVector(init, sz) = ByteVector(Vector{UInt8}(init, sz))
ByteVector(v::AbstractVector{UInt8}) = ByteVector(v)
ByteVector(v::AbstractVector) = ByteVector(UInt8.(v))
# function Base.push!(b::ByteVector, bb::Float64)
#     for i=0:3
#         push!(b.d, bb<<i*4)
#     end
# end
Base.size(b::ByteVector) = size(b.d)
Base.getindex(b::ByteVector, i) = b.d[i]
Base.setindex!(b::ByteVector, bb::UInt8, i) = b.d[i] = bb
function Base.setindex!(b::ByteVector, bb, i)
    if sizeof(bb) == 8
        b[i] = reinterpret(UInt64, bb)
    else
        TODO()
    end
end
function Base.setindex!(b::ByteVector, bb::UInt64, i)
    @assert 1 <= i && i+8 <= length(b)+1
    for ii in 7:-1:0 # little endian
        b.d[i+ii] = UInt8(bb >> (ii*8) & 0xFF)
    end
    return b
end
Base.setindex!(b::ByteVector, p::Ptr, i) = b[i] = UInt64(p)

# test:
# bv = ByteVector(8)
# bv[1] = 1.0
# vv = reinterpret(UInt64, bv.d)
# vv[1] == reinterpret(UInt64, 1.0)
