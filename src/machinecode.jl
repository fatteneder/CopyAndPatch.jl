mutable struct MachineCode
    fn::Any # TODO Should this be Function? What about callable structs?
    rettype::DataType
    argtypes::Vector{DataType}
    buf::Vector{UInt8}
    slots::Vector{Ptr{UInt64}}
    ssas::Vector{Ptr{UInt64}}
    static_prms::Vector{Ptr{UInt64}}
    gc_roots::Vector{Any}
    # TODO Remove union
    codeinfo::Union{Nothing,CodeInfo}
    stencil_starts::Vector{Int64}

    function MachineCode(bvec::ByteVector, fn,
            @nospecialize(rettype::Type), @nospecialize(argtypes::NTuple{N,DataType}),
            gc_roots::Vector{Any}=Any[]) where N
        rt = rettype <: Union{} ? Nothing : rettype
        ats = [ at for at in argtypes ]
        buf = mmap(Vector{UInt8}, length(bvec), shared=false, exec=true)
        copy!(buf, bvec)
        new(fn, rt, ats, buf, UInt64[], UInt64[], UInt64[], gc_roots, nothing, Int64[])
    end
    function MachineCode(sz::Integer, fn,
            @nospecialize(rettype::Type), @nospecialize(argtypes::NTuple{N,DataType}),
            gc_roots::Vector{Any}=Any[]) where N
        rt = rettype <: Union{} ? Nothing : rettype
        ats = [ at for at in argtypes ]
        buf = mmap(Vector{UInt8}, sz, shared=false, exec=true)
        new(fn, rt, ats, buf, UInt64[], UInt64[], UInt64[], gc_roots, nothing, Int64[])
    end
end
MachineCode(fn, @nospecialize(rettype), @nospecialize(argtypes), bvec, gc_roots::Vector{Any}=Any[]) =
    MachineCode(fn, rettype, argtypes, ByteVector(bvec), gc_roots)


Base.pointer(code::MachineCode) = Base.unsafe_convert(Ptr{Cvoid}, pointer(code.buf))


call(mc::MachineCode, @nospecialize(args...)) = mc(args...)
function (mc::MachineCode)(@nospecialize(args...))
    nargs = length(mc.argtypes)
    if length(args) != nargs
        throw(MethodError(mc, args))
    end
    gc_roots = mc.gc_roots
    slots = mc.slots
    slots[1] = value_pointer(mc.fn)
    for (ii,a) in enumerate(args)
        i = ii+1 # slots[1] is the function itself
        if a isa Boxable
            slots[i] = box(a)
        else
            slots[i] = value_pointer(a)
        end
    end
    GC.@preserve mc begin
        ccall(pointer(mc), Cint, (Cint,), 0 #= ip =#)
    end
    p = mc.static_prms[end]
    return Base.unsafe_pointer_to_objref(p)
end


function Base.show(io::IO, ::MIME"text/plain", mc::MachineCode)
    print(io, "MachineCode(")
    length(mc.argtypes) > 0 && print(io, "::", join(mc.argtypes,",::"))
    print(io, ")::", mc.rettype)
end
