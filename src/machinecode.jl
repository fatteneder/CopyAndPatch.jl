struct MachineCode{RetType,ArgTypes}
    buf::Vector{UInt8}
    ptr::Ptr{Cvoid}
    function MachineCode(bvec::ByteVector, rettype::DataType,argtypes::NTuple{N,DataType}) where N
        buf = mmap(Vector{UInt8}, length(bvec), shared=false, exec=true)
        copy!(buf, bvec)
        ptr = pointer(buf)
        new{rettype,Tuple{argtypes...}}(buf, ptr)
    end
end
MachineCode(bvec, rettype, argtypes) = MachineCode(ByteVector(bvec), rettype, argtypes)


@generated function (code::MachineCode{RetType,ArgTypes})(args...) where {RetType,ArgTypes}
    rettype_ex = Symbol(RetType)
    argtype_ex = Expr(:tuple)
    for t in ArgTypes.types
        push!(argtype_ex.args, Symbol(t))
    end
    arg_ex = [ :(args[$i]) for i in 1:length(args) ]
    ex = quote
        ccall(code.ptr, $rettype_ex, $argtype_ex, $(arg_ex...))
    end
    return ex
end


function Base.show(io::IO, ::MIME"text/plain", code::MachineCode{RetType,ArgTypes}) where {RetType,ArgTypes}
    print(io, "MachineCode(")
    args = ArgTypes.types
    length(args) > 0 && print("::", join(args,"::,"))
    print(")::", RetType)
end
