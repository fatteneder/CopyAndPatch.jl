mutable struct MachineCode{RetType,ArgTypes}
    buf::Vector{UInt8}
    slots::Vector{Ptr{UInt64}}
    ssas::Vector{Ptr{UInt64}}
    static_prms::Vector{Ptr{UInt64}}
    gc_roots::Vector{Any}
    # TODO Remove union
    codeinfo::Union{Nothing,CodeInfo}
    stencil_starts::Vector{Int64}

    function MachineCode(bvec::ByteVector, @nospecialize(rettype::Type{T}), argtypes::NTuple{N,DataType},
                         gc_roots::Vector{Any}=Any[]) where {T,N}
        rt = rettype <: Union{} ? Nothing : rettype
        buf = mmap(Vector{UInt8}, length(bvec), shared=false, exec=true)
        copy!(buf, bvec)
        new{rt,Tuple{argtypes...}}(buf, UInt64[], UInt64[], UInt64[], gc_roots, nothing, Int64[])
    end
    function MachineCode(sz::Integer, @nospecialize(rettype::Type{T}), argtypes::NTuple{N,DataType},
                         gc_roots::Vector{Any}=Any[]) where {T,N}
        rt = rettype <: Union{} ? Nothing : rettype
        buf = mmap(Vector{UInt8}, sz, shared=false, exec=true)
        new{rt,Tuple{argtypes...}}(buf, UInt64[], UInt64[], UInt64[], gc_roots, nothing, Int64[])
    end
end
MachineCode(bvec, rettype, argtypes, gc_roots::Vector{Any}=Any[]) =
    MachineCode(ByteVector(bvec), rettype, argtypes, gc_roots)

const MC = MachineCode

rettype(mc::MachineCode{RetType,ArgTypes}) where {RetType,ArgTypes} = RetType
argtypes(mc::MachineCode{RetType,ArgTypes}) where {RetType,ArgTypes} = ArgTypes


Base.pointer(code::MachineCode) = Base.unsafe_convert(Ptr{Cvoid}, pointer(code.buf))


function call(code::MachineCode{RetType,ArgTypes}, @nospecialize(args...)) where {RetType,ArgTypes}
    argtypes = [ a for a in ArgTypes.parameters ]
    nargs = length(argtypes)
    if length(args) != nargs
        throw(MethodError(code, args))
    end
    gc_roots = code.gc_roots
    slots = code.slots
    N = nargs+1 # because slots[1] is the function itself
    for (ii,a) in enumerate(args)
        i = ii+1
        if a isa Boxable
            slots[i] = box(a)
        elseif a isa AbstractArray
            slots[i] = value_pointer(a)
        else
            slots[N+ii] = value_pointer(a)
            slots[i] = pointer(slots, N+ii)
        end
    end
    GC.@preserve code begin
        ccall(pointer(code), Cvoid, (Cint,), 0 #= ip =#)
    end
    p = code.static_prms[end]
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
    length(args) > 0 && print(io, "::", join(args,",::"))
    print(io, ")::", RetType)
end
