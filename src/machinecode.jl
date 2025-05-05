mutable struct MachineCode
    fn::Any
    rettype::Any
    argtypes::Vector{Any}
    buf::Vector{UInt8}
    codeinfo::Core.CodeInfo
    instr_stencil_starts::Vector{Int64}
    load_stencils_starts::Vector{Vector{Int64}}
    instr_stencils::Vector{StencilData}
    load_stencils::Vector{Vector{StencilData}}
    # TODO remove
    slots::Vector{Ptr{UInt64}}
    ssas::Vector{Ptr{UInt64}}
    static_prms::Vector{Any}
    gc_roots::Vector{Any}
    ntmps::Int64

    function MachineCode(
            sz::Integer, @nospecialize(fn::Any),
            @nospecialize(rettype::Any), @nospecialize(argtypes::Tuple),
            codeinfo::Core.CodeInfo,
            instr_stencil_starts::Vector{Int64},
            load_stencils_starts::Vector{Vector{Int64}},
            instr_stencils::Vector{StencilData},
            load_stencils::Vector{Vector{StencilData}},
            gc_roots::Vector{Any} = Any[]
        )
        rt = rettype <: Union{} ? Nothing : rettype
        ats = [ at for at in argtypes ]
        buf = Mmap.mmap(Vector{UInt8}, sz, shared = false, exec = true)
        nslots = length(codeinfo.slotnames)
        nssas = length(codeinfo.ssavaluetypes)
        @assert nssas == length(codeinfo.code)
        slots = zeros(UInt64, nslots)
        ssas = zeros(UInt64, nssas)
        return new(
            fn, rt, ats, buf, codeinfo, instr_stencil_starts, load_stencils_starts,
            instr_stencils, load_stencils, slots, ssas, Any[], gc_roots, 0
        )
    end
    function MachineCode(
            bvec::ByteVector, @nospecialize(fn::Any),
            @nospecialize(rettype::Any), @nospecialize(argtypes::Tuple),
            codeinfo::Core.CodeInfo,
            instr_stencil_starts::Vector{Int64},
            load_stencils_starts::Vector{Vector{Int64}},
            instr_stencils::Vector{StencilData},
            load_stencils::Vector{Vector{StencilData}},
            gc_roots::Vector{Any} = Any[]
        )
        mc = MachineCode(
            length(bvec), fn, rettype, argtypes, codeinfo,
            instr_stencil_starts, load_stencils_starts;
            instr_stencils, load_stencils, gc_roots
        )
        copyto!(mc.bvec, 1, bvec, 1, length(bvec))
        return mc
    end
end


function get_continuation(mc::MachineCode, ip::Int64)
    return if length(mc.load_stencils_starts[ip]) > 0
        pointer(mc.buf, mc.load_stencils_starts[ip][1])
    else
        pointer(mc.buf, mc.instr_stencil_starts[ip])
    end
end


invoke_pointer(code::MachineCode) = Base.unsafe_convert(Ptr{Cvoid}, pointer(code.buf))


call(mc::MachineCode, @nospecialize(args...)) = mc(args...)


function (mc::MachineCode)(@nospecialize(args...))
    p = invoke_pointer(mc)
    fn = mc.fn
    nargs = length(args)
    ci = C_NULL # unused by us, but required for ci->invoke abi
    return GC.@preserve mc args begin
        @ccall $p(
            fn::Any, args::Any #= Any, because args isa Tuple =#,
            nargs::UInt32, ci::Ptr{Cvoid}
        )::Any
    end
end


function Base.show(io::IO, ::MIME"text/plain", mc::MachineCode)
    print(io, "MachineCode(")
    length(mc.argtypes) > 0 && print(io, "::", join(mc.argtypes, ",::"))
    return print(io, ")::", mc.rettype)
end
