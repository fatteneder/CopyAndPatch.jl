const hexfmt = Format("%02x")

function stencil_files()
    dir = normpath(joinpath(@__DIR__,"..","stencils"))
    files = readdir(dir, join=true)
    filter!(files) do ff
        f = basename(ff)
        (startswith(f, "jl_") || startswith(f, "jit_")) && endswith(f, ".json")
    end
    return files
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


function handle_section(section, group::StencilGroup)
    section_type = section["Type"]["Name"] # build.py uses Value instead of Name, why?
    flags = [ flag["Name"] for flag in section["Flags"]["Flags"] ]
    if section_type == "SHT_RELA"
        @assert "SHF_INFO_LINK" in flags flags
        @assert getkey(section, "Symbols", nothing) !== nothing
        if section["Info"] in keys(group.code.offsets)
            stencil = group.code
        else
            stencil = group.data
        end
        base = stencil.offsets[section["Info"]]
        for wrapped_relocation in section["Relocations"]
            relocation = wrapped_relocation["Relocation"]
            hole = handle_relocation(base, relocation, stencil.body)
            push!(stencil.relocations, hole)
        end
    elseif section_type == "SHT_PROGBITS"
        if !("SHF_ALLOC" in flags)
            return
        end
        if "SHF_EXECINSTR" in flags
            stencil = group.code
        else # ???
            stencil = group.data
        end
        stencil.offsets[section["Index"]] = length(stencil.body)
        for wrapped_symbol in section["Symbols"]
            symbol = wrapped_symbol["Symbol"]
            offset = length(stencil.body) + symbol["Value"]
            name = symbol["Name"]["Name"]
            # name = name.removeprefix(self.prefix) # TODO needed? it's either "_" or ""
            # @assert !(name in stencil.symbols)
            @assert !haskey(stencil.symbols, name)
            stencil.symbols[name] = offset
        end
        section_data = section["SectionData"]
        push!(stencil.body, section_data["Bytes"])
        @assert section["Relocations"] !== nothing
    elseif section_type == "SHT_X86_64_UNWIND"
        error("Found section 'SHT_X86_64_UNWIND. Did you compile with -fno-asynchronous-unwind-table?")
    else
        @assert section_type in (
            "SHT_GROUP",
            "SHT_LLVM_ADDRSIG",
            "SHT_NULL",
            "SHT_STRTAB",
            "SHT_SYMTAB",
            # "SHT_NOBITS" # added by me; this a section header for section that does not contain actual data
                         # # (e.g. uninitialized global and static vars) -- ref: gemini
        ) section_type
    end
    return section
end


function handle_relocation(base, relocation, raw)
    offset = get(relocation, "Offset", nothing)
    isnothing(offset) && error(relocation)
    type = get(relocation, "Type", nothing)
    isnothing(type) && error(relocation)
    addend = get(relocation, "Addend", nothing)
    isnothing(addend) && error(relocation)
    symbol = get(relocation, "Symbol", nothing)
    isnothing(symbol) && error(relocation)
    kind = get(type, "Name", nothing) # TODO build.py uses Value, why?
    isnothing(kind) && error(relocation)
    s = get(symbol, "Name", nothing) # TODO build.py uses Value, why?
    isnothing(s) && error(relocation)
    offset += base
    # TODO Remove prefix from s?
    value, symbol = symbol_to_value(s)
    return Hole(offset, kind, value, symbol, addend)
end


function pad!(s::Stencil, alignment::Int64)
    offset = length(s.body)
    # TODO Is max-ing here ok?
    padding = max(-offset % alignment, 0)
    push!(s.disassembly, "$(UInt8(offset)): $(join(("00" for _ in 1:padding), ' '))")
    if padding > 0
        push!(s.disassembly, repeat([UInt8(0)], padding))
    end
end

function process_relocations(stencil::Stencil, group::StencilGroup)
    for hole in stencil.relocations
        if hole.value === HoleValues.GOT
            value, symbol = HoleValues.DATA, nothing
            addend = hold.addend + global_offset_table_lookup(group, hole.symbol)
            hole = Hole(hole.offset, hole.kind, value, symbol, addend)
        elseif hole.symbol in keys(group.data.symbols)
            value, symbol = HoleValues.DATA, nothing
            addend = hole.addend + group.data.symbols[hole.symbol]
            hole = Hole(hole.offset, hole.kind, value, symbol, addend)
        elseif hole.symbol in keys(group.code.symbols)
            value, symbol = HoleValue.CODE, None
            addend = hole.addend + group.code.symbols[hole.symbol]
            hole = Hole(hole.offset, hole.kind, value, symbol, addend)
        end
        push!(stencil.holes, hole)
    end
end

const HOLEKINDS = [
    "ARM64_RELOC_GOT_LOAD_PAGE21",
    "ARM64_RELOC_GOT_LOAD_PAGEOFF12",
    "ARM64_RELOC_UNSIGNED",
    "IMAGE_REL_AMD64_ADDR64",
    "IMAGE_REL_I386_DIR32",
    "R_AARCH64_ABS64",
    "R_AARCH64_CALL26",
    "R_AARCH64_JUMP26",
    "R_AARCH64_MOVW_UABS_G0_NC",
    "R_AARCH64_MOVW_UABS_G1_NC",
    "R_AARCH64_MOVW_UABS_G2_NC",
    "R_AARCH64_MOVW_UABS_G3",
    "R_X86_64_64", # 64-bit absolute address.
    "X86_64_RELOC_UNSIGNED",
]


function symbol_to_value(symbol)
    if startswith(symbol, "_JIT_")
        s = replace(symbol, r"^_JIT_"=>"", count=1)
        hs = instances(HoleValues.HoleValue)
        i = findfirst(==(s), string.(hs))
        if isnothing(i)
            return HoleValues.ZERO, symbol
        else
            return hs[i], nothing
        end
    end
    return HoleValues.ZERO, symbol
end


function emit_global_offset_table!(group)
    global_offset_table = length(group.data.body)
    for (s,offset) in group.global_offset_table
        if s in group.code.symbols
            value, symbol = HoleValues.CODE, nothing
            addend = group.code.symbols[s]
        elseif s in group.data.symbols
            value, symbol = HoleValues.DATA, nothing
            addend = group.data.symbols[s]
        else
            value, symbol = symbol_to_value(s)
            addend = 0
        end
        push!(group.data.holes, Hole(global_offset_table+offset, "R_X86_64_64", value, symbol, addend))
        value_part = value != HoleValues.ZERO ? value.name : ""
        if !isnothing(value_part) && isnothing(value) && isnothing(addend)
            addend_part = ""
        else
            addend_part = isnothing(symbol) ? "&$(symbol) + " : ""
            addend_part *= format_addend(addend)
            if !isnothing(value_part)
                value_part *= " + "
            end
        end
        @show(value_part)
        @show(addend_part)
        push!(group.data.disassembly, "$(UInt8(length(group.data.body))): $(value_part)$(addend_part)")
        push!(group.data.body, repeat([UInt8(0)], padding))
    end
end


StencilGroup(path::AbstractString) = StencilGroup(parsefile(string(path)))
function StencilGroup(json::Vector{Any})
    group = StencilGroup(Stencil(), Stencil(), Dict())
    for sec in json[1]["Sections"]
        handle_section(sec["Section"], group)
    end

    @assert group.code.symbols["_JIT_ENTRY"] == 0
    if length(group.data.body) > 0
        # @assert length(group.data.body) == 1
        body = UInt8.(group.data.body[1])
        line = "0: $(join(format.(Ref(hexfmt), body), ' '))"
        push!(group.data.disassembly, line)
    end

    pad!(group.data, 8)

    process_relocations(group.code, group)

    remaining = []
    for hole in group.code.holes
        if hole.kind in ("R_AARCH64_CALL26", "R_AARCH64_JUMP26") && hole.value === HoleValues.ZERO
            # some sort of aarch64 trampolin?
            TODO()
        else
            push!(remaining, hole)
        end
    end

    @assert length(group.code.holes) == length(remaining)
    group.code.holes .= remaining

    process_relocations(group.data, group)

    emit_global_offset_table!(group)

    sort!(group.code.holes, by=h->h.offset)
    sort!(group.data.holes, by=h->h.offset)

    return group
end


holes(g::StencilGroup) = g.code.relocations
patch!(m::MachineCode, h::Hole, p::Ptr) = m.buf[h.offset+1] = p
patch!(b::ByteVector, h::Hole, val) = b[h.offset+1] = val
# patchlibs!(m::MachineCode, g::Hole)
function patch!(bvec::ByteVector, st::Stencil, symbol::String, val)
    holes = st.relocations
    anyfound = false
    for h in holes
        if startswith(h.symbol, symbol)
            patch!(bvec, h, val)
            anyfound = true
        end
    end
    !anyfound && error("No symbol $symbol found in stencil")
end
function patch!(vec::AbstractVector{<:UInt8}, st::Stencil, symbol::String, val)
    patch!(ByteVector(vec), st, symbol, val)
end
