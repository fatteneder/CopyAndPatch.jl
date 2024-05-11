struct MachineCode{RetType,ArgTypes}
    buf::Vector{UInt8}
    # TODO Remove ptr
    ptr::Ptr{Cvoid}
    gc_roots::Vector{Any}
    function MachineCode(bvec::ByteVector, rettype::DataType, argtypes::NTuple{N,DataType},
                         gc_roots=Any[]) where N
        buf = mmap(Vector{UInt8}, length(bvec), shared=false, exec=true)
        copy!(buf, bvec)
        ptr = pointer(buf)
        new{rettype,Tuple{argtypes...}}(buf, ptr, Any[])
    end
    function MachineCode(sz::Integer, rettype::DataType, argtypes::NTuple{N,DataType},
                         gc_roots=Any[]) where N
        buf = mmap(Vector{UInt8}, sz, shared=false, exec=true)
        ptr = pointer(buf)
        new{rettype,Tuple{argtypes...}}(buf, ptr, Any[])
    end
end
MachineCode(bvec, rettype, argtypes, gc_roots=Any[]) = MachineCode(ByteVector(bvec), rettype, argtypes, gc_roots)

rettype(mc::MachineCode{RetType,ArgTypes}) where {RetType,ArgTypes} = RetType
argtypes(mc::MachineCode{RetType,ArgTypes}) where {RetType,ArgTypes} = ArgTypes


Base.pointer(code::MachineCode) = code.ptr


@generated function (code::MachineCode{RetType,ArgTypes})(args...) where {RetType,ArgTypes}
    rettype_ex = Symbol(RetType)
    argtype_ex = Expr(:tuple)
    for t in ArgTypes.types
        push!(argtype_ex.args, t)
    end
    nargs = length(ArgTypes.types)
    arg_ex = [ :(args[$i]) for i in 1:nargs ]
    ex = quote
        if length($args) != $nargs
            throw(MethodError($(code),$(args)))
        end
        ccall(code.ptr, $rettype_ex, $argtype_ex, $(arg_ex...))
    end
    return ex
end
function call(code::MachineCode{RetType,ArgTypes}, args...) where {RetType,ArgTypes}
    nargs = length(ArgTypes.parameters)
    if length(args) != nargs
        throw(MethodError(code, args))
    end
    gc_roots = code.gc_roots
    slots = first(gc_roots)
    for (i,a) in enumerate(args)
        # 1 is the method itself, which we skip for now
        # slots[i+1] = box(a)
        slots[i+1] = unsafe_pointer_from_objref(a)
    end
    # TODO I think the problem is that we 'hardcode' the argument values in the stencil
    # when we jit it, and so overwriting slots here doesn't help.
    # There would be two ways to fix this:
    # - Add one more layer of indirection for slots, but this would require to use ***args
    #   everywhere, I think.
    # - Record the offsets in the memory for each slot and patch the values right
    #   before execution. This also sounds wrong.
    p = GC.@preserve args gc_roots begin
        ccall(code.ptr, Ptr{Cvoid}, (Cint,), 1)
    end
    @assert p !== C_NULL
    return if RetType <: Boxable
        unsafe_load(Base.unsafe_convert(Ptr{RetType}, p))
    elseif RetType === Nothing
        nothing
    else
        Base.unsafe_pointer_to_objref(p)
    end
end


function Base.show(io::IO, ::MIME"text/plain", code::MachineCode{RetType,ArgTypes}) where {RetType,ArgTypes}
    print(io, "MachineCode(")
    args = ArgTypes.types
    length(args) > 0 && print(io, "::", join(args,"::,"))
    print(io, ")::", RetType)
end
