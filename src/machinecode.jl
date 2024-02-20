mutable struct MachineCode{RetType,ArgTypes}
    const bvec::ByteVector
    offset::Int
    const ptr::Ptr{Cvoid}
    function MachineCode(rettype::DataType,argtypes::NTuple{N,DataType}, sz=4096) where N
        sz > 0 || throw(ArgumentError("sz must be positive"))
        buf = mmap(Vector{UInt8}, sz, shared=false, exec=true)
        bvec = ByteVector(buf)
        ptr = pointer(buf)
        new{rettype,Tuple{argtypes...}}(bvec, 0, ptr)
    end
end


@generated function call(a::MachineCode{RetType,ArgTypes}, args...) where {RetType,ArgTypes}
    rettype_ex = Symbol(RetType)
    argtype_ex = Expr(:tuple)
    for t in ArgTypes.types
        push!(argtype_ex.args, Symbol(t))
    end
    arg_ex = [ :(args[$i]) for i in 1:length(args) ]
    ex = quote
        ccall(a.ptr, $rettype_ex, $argtype_ex, $(arg_ex...))
    end
    return ex
end


@inline function Base.write(a::MachineCode, b::UInt8)
    a.offset < length(a) || throw(ArgumentError("buffer overflow"))
    a.offset += 1
    a.buf[a.offset] = b
    return
end
function Base.write(a::MachineCode, bs::AbstractVector{<:UInt8})
    for b in bs
        write(a, b)
    end
end
function Base.write(a::MachineCode, @nospecialize(bs::UInt8...))
    for b in bs
        write(a, b)
    end
end
