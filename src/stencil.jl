const HEXFMT = Printf.Format("%02x")

baremodule HoleValues
    import Base: @enum
    @enum HoleValue CODE CONTINUE DATA EXECUTOR GOT OPARG OPERAND TARGET TOP ZERO
    export HoleValue
end
using .HoleValues


mutable struct Hole
    offset::Int64
    kind::String
    value::HoleValue
    symbol::Union{String,Nothing}
    addend::Int64
end


mutable struct Stencil
    parent::Any # the StencilGroup the stencil is contained in
    const body::Vector{UInt8}
    const holes::Vector{Hole}
    const symbols::Dict{String,Any}
    const offsets::Dict{Int64,Int64}
    const relocations::Vector{Hole}
end
Stencil() = Stencil(nothing, UInt8[], Hole[], Dict{String,Any}(), Dict{Int64,Int64}(), Hole[])


mutable struct StencilGroup
    const name::String
    const code::Stencil # actual machine code (with holes)
    const data::Stencil # needed to build a header file
    const global_offset_table::Dict{String,Any}
    isIntrinsicFunction::Bool
end


struct StencilData
    md::StencilGroup # stencil meta data
    bvec::ByteVector # _JIT_ENTRY section
    bvec_data::ByteVector # .rodata and similar
end


function Base.show(io::IO, ::MIME"text/plain", st::StencilData)
    print(io, "StencilData(\"", get_name(st), "\")")
    return
end


get_name(st::StencilData) = st.md.name


function handle_section(section, group::StencilGroup)
    section_type = section["Type"]["Name"]
    flags = [ flag["Name"] for flag in section["Flags"]["Flags"] ]
    if section_type == "SHT_RELA" # relocation entries with addends
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
            hole = handle_relocation(base, relocation)
            push!(stencil.relocations, hole)
        end
    elseif section_type == "SHT_PROGBITS" # .text (exec code), .data (init data), .rodata (read-only data)
        if !("SHF_ALLOC" in flags)
            return
        end
        if "SHF_EXECINSTR" in flags
            stencil = group.code
        else
            stencil = group.data
        end
        if length(section["Symbols"]) > 0
            symbol = only(section["Symbols"])["Symbol"]
            stencil.offsets[section["Index"]] = length(stencil.body)
            offset = length(stencil.body) + symbol["Value"]
            name = symbol["Name"]["Name"]
            @assert !haskey(stencil.symbols, name)
            stencil.symbols[name] = offset
            stencil.offsets[section["Index"]] = length(stencil.body)
            bytes = section["SectionData"]["Bytes"]
            @assert length(bytes) > 0 && length(stencil.body) == 0
            append!(stencil.body, UInt8.(bytes))
            @assert section["Relocations"] !== nothing
        end
    elseif section_type == "SHT_X86_64_UNWIND"
        error("Found section 'SHT_X86_64_UNWIND. Did you compile with -fno-asynchronous-unwind-table?")
    else
        @assert section_type in (
            "SHT_GROUP", # groupped section, has no actual data or code
            "SHT_LLVM_ADDRSIG", # llvm specific for LTO
            "SHT_NULL", # unused or inactive section
            "SHT_STRTAB", # sections with null-terminated strings referenced somewhere else
            "SHT_SYMTAB", # symbol table, e.g. function names and global variables
        ) section_type
    end
    # TODO Move to SHT_PROGBITS?
    if section["Name"]["Name"] == ".data"
        for sym in section["Symbols"]
            s = get(sym, "Symbol", nothing); s === nothing && continue
            name = get(s, "Name", nothing); name === nothing && continue
            if name["Name"] == "isIntrinsicFunction"
                group.isIntrinsicFunction = true
            end
            break
        end
    end
    return section
end


function handle_relocation(base, relocation)
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
            value, symbol = HoleValues.CODE, nothing
            addend = hole.addend + group.code.symbols[hole.symbol]
            hole = Hole(hole.offset, hole.kind, value, symbol, addend)
        end
        push!(stencil.holes, hole)
    end
    return
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
        s = replace(symbol, r"^_JIT_" => "", count = 1)
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
    for (s, offset) in group.global_offset_table
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
        push!(group.data.holes, Hole(global_offset_table + offset, "R_X86_64_64", value, symbol, addend))
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
        TODO("padding")
        push!(group.data.body, repeat([UInt8(0)], padding))
    end
    return
end


StencilGroup(path::AbstractString, name::String) = StencilGroup(only(JSON.parsefile(string(path))), name)
function StencilGroup(json::Dict, name::String)
    group = StencilGroup(name, Stencil(), Stencil(), Dict(), false)
    group.code.parent = group
    group.data.parent = group

    for sec in json["Sections"]
        handle_section(sec["Section"], group)
    end

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

    sort!(group.code.holes, by = h -> h.offset)
    sort!(group.data.holes, by = h -> h.offset)

    return group
end


function patch!(b::ByteVector, start::Integer, offset::Integer, addend::Integer, val)
    @assert addend == 0
    b[start #=1-based=# + offset] = val
    return
end

function patch!(b::ByteVector, start::Integer, offset::Integer, addend::Integer, val::Ptr)
    b[start #=1-based=# + offset] = Ptr{Cvoid}(Ptr{UInt8}(val) + addend)
    return
end

patch!(bvec::ByteVector, st::Stencil, symbol::String, val; kwargs...) =
    patch!(bvec, 0, st, symbol, val, kwargs...)

function patch!(
        bvec::ByteVector, start::Integer, st::Stencil, symbol::String, val;
        optional::Bool = false
    )
    holes = st.relocations
    anyfound = false
    for h in holes
        if h.symbol == symbol
            if h.kind == "R_X86_64_64"
                # zero out the hole
                patch!(bvec, start, h.offset, 0#=addend=#, UInt64(0))
            else
                TODO(h.kind)
            end
            patch!(bvec, start, h.offset, h.addend, val)
            anyfound = true
        end
    end
    if !optional && !anyfound
        error("No symbol $symbol found in stencil '$(st.parent.name)'")
    end
    return
end

function patch!(
        vec::AbstractVector{<:UInt8}, offset::Integer, st::Stencil, symbol::String, val;
        kwargs...
    )
    return patch!(ByteVector(vec), offset, st, symbol, val; kwargs...)
end
