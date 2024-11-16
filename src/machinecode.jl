mutable struct MachineCode
    fn::Any # TODO Should this be Function? What about callable structs?
    rettype::Union{<:Union,DataType}
    argtypes::Vector{Union{DataType,UnionAll,Core.TypeofVararg}}
    buf::Vector{UInt8}
    slots::Vector{Ptr{UInt64}}
    ssas::Vector{Ptr{UInt64}}
    static_prms::Vector{Any}
    gc_roots::Vector{Any}
    exc_thrown::Base.RefValue{Cint}
    phioffset::Base.RefValue{Cint}
    # TODO Remove union
    codeinfo::Union{Nothing,CodeInfo}
    stencil_starts::Vector{Int64}

    function MachineCode(sz::Integer, @nospecialize(fn),
            @nospecialize(rettype::Type), @nospecialize(argtypes::Tuple),
            gc_roots::Vector{Any}=Any[])
        rt = rettype <: Union{} ? Nothing : rettype
        ats = [ at for at in argtypes ]
        buf = mmap(Vector{UInt8}, sz, shared=false, exec=true)
        new(fn, rt, ats, buf, UInt64[], UInt64[], Any[], gc_roots, Ref(Cint(0)), Ref(Cint(0)),
            nothing, Int64[])
    end
    function MachineCode(bvec::ByteVector, @nospecialize(fn),
            @nospecialize(rettype::Type), @nospecialize(argtypes::Tuple),
            gc_roots::Vector{Any}=Any[])
        mc = MachineCode(length(bvec), fn, rettype, argtypes, gc_roots)
        copyto!(mc.bvec, 1, bvec, 1, length(bvec))
        return mc
    end
end


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
    for (i,a) in enumerate(args)
        slots[i+1] = value_pointer(a)
    end
    mc.phioffset[] = Cint(0)
    v = GC.@preserve mc begin
        ret_ip = ccall(pointer(mc), Cint, (Cint,), 0 #= ip =#)
        Base.unsafe_pointer_to_objref(mc.ssas[ret_ip])
    end
    return v
end


function Base.show(io::IO, ::MIME"text/plain", mc::MachineCode)
    print(io, "MachineCode(")
    length(mc.argtypes) > 0 && print(io, "::", join(mc.argtypes,",::"))
    print(io, ")::", mc.rettype)
end
