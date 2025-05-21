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
        # can't use codeinfo.nargs, because it only counts the used arguments
        # when codeinfo came from code_typed(; optimize=true)
        nargs = length(codeinfo.slotnames) - 1 # -1 because first is function
        ats = if nargs == 0
            Any[]
        else
            ats = Vector{Any}(undef, nargs)
            for i in 1:nargs-1
                ats[i] = argtypes[i]
            end
            ats[end] = codeinfo.isva ? argtypes[nargs:end] : argtypes[end]
            ats
        end
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


patch!(m::MachineCode, h::Hole, p::Ptr) = m.buf[h.offset + 1] = p


call(mc::MachineCode, @nospecialize(args...)) = mc(args...)


function (mc::MachineCode)(@nospecialize(args...))
    p = invoke_pointer(mc)
    fn = mc.fn
    nargs = length(mc.argtypes)
    p_args = if nargs == 0
        Any[]
    else
        if mc.codeinfo.isva
            Any[ args[1:nargs-1]..., args[nargs:end] ]
        else
            Any[ args... ]
        end
    end
    ci = C_NULL # unused by us, but required for ci->invoke abi
    return GC.@preserve mc p_args begin
        @ccall $p(fn::Any, p_args::Ptr{Any}, nargs::UInt32, ci::Ptr{Cvoid})::Any
    end
end


function Base.show(io::IO, ::MIME"text/plain", mc::MachineCode)
    print(io, "MachineCode(")
    if length(mc.argtypes) > 0
        if mc.codeinfo.isva
            print(io, "::", join(mc.argtypes[1:end-1], ",::"), ",::", join(mc.argtypes[end], ",::"))
        else
            print(io, "::", join(mc.argtypes, ",::"))
        end
    end
    print(io, ")::", mc.rettype)
    return
end
