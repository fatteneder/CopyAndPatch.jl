mutable struct MachineCode
    fn::Any
    rettype::Any
    argtypes::Vector{Any}
    buf::Vector{UInt8}
    codeinfo::CodeInfo
    stencil_starts::Vector{Int64}
    slots::Vector{Ptr{UInt64}}
    ssas::Vector{Ptr{UInt64}}
    static_prms::Vector{Any}
    gc_roots::Vector{Any}
    exc_thrown::Base.RefValue{Cint}
    phioffset::Base.RefValue{Cint}

    function MachineCode(sz::Integer, @nospecialize(fn),
            @nospecialize(rettype), @nospecialize(argtypes::Tuple),
            codeinfo::CodeInfo, stencil_starts::Vector{Int64},
            gc_roots::Vector{Any}=Any[])
        rt = rettype <: Union{} ? Nothing : rettype
        ats = [ at for at in argtypes ]
        buf = mmap(Vector{UInt8}, sz, shared=false, exec=true)
        nslots = length(codeinfo.slotnames)
        nssas = length(codeinfo.ssavaluetypes)
        @assert nssas == length(codeinfo.code)
        slots = zeros(UInt64, nslots)
        ssas = zeros(UInt64, nssas)
        return new(fn, rt, ats, buf, codeinfo, stencil_starts,
                   slots, ssas, Any[], gc_roots, Ref(Cint(0)), Ref(Cint(0)))
    end
    function MachineCode(bvec::ByteVector, @nospecialize(fn),
            @nospecialize(rettype), @nospecialize(argtypes::Tuple),
            codeinfo::CodeInfo, stencil_starts::Vector{Int64},
            gc_roots::Vector{Any}=Any[])
        mc = MachineCode(length(bvec), fn, rettype, argtypes, codeinfo, stencil_starts; gc_roots)
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
