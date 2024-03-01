using CopyAndPatch
using Base.Libc.Libdl

lib = dlopen(dlpath("libjulia"))
libc = dlopen(dlpath("libc.so.6"))


group = CopyAndPatch.StencilGroup(joinpath(@__DIR__, "..", "jit_end.json"))
holes = CopyAndPatch.holes(group)

patches = Dict{String,Ptr}(
    "printf" => dlsym(libc, :printf),
    "puts" => dlsym(libc, :puts)
)
bvec = CopyAndPatch.ByteVector(UInt8.(group.code.body[1]))
if !isempty(group.data.body)
    bvec_data = CopyAndPatch.ByteVector(UInt8.(group.data.body[1]))
else
    bvec_data = nothing
end

for h in holes
    if startswith(h.symbol, ".rodata")
        p = pointer(bvec_data.d, h.addend+1)
    else
        p = get(patches, h.symbol) do
            CopyAndPatch.TODO(h.symbol)
        end
    end
    bvec[h.offset+1] = p
end

jit_end = CopyAndPatch.MachineCode(bvec, Cvoid, (Ptr{Cvoid},))
jit_end(C_NULL)



group = CopyAndPatch.StencilGroup(joinpath(@__DIR__, "mwe_continuation.json"))
holes = CopyAndPatch.holes(group)

patches = Dict{String,Ptr}(
    "jl_call" => dlsym(CopyAndPatch.libjulia[], :jl_call),
    "printf" => dlsym(libc, :printf),
    "puts" => dlsym(libc, :puts)
)
bvec = CopyAndPatch.ByteVector(UInt8.(group.code.body[1]))
if !isempty(group.data.body)
    bvec_data = CopyAndPatch.ByteVector(UInt8.(group.data.body[1]))
else
    bvec_data = nothing
end

for h in holes
    if startswith(h.symbol, ".rodata")
        p = pointer(bvec_data.d, h.addend+1)
    else
        p = get(patches, h.symbol) do
            CopyAndPatch.TODO(h.symbol)
        end
    end
    bvec[h.offset+1] = p
end

jl_continuation = CopyAndPatch.MachineCode(bvec, Cvoid, (Ptr{Cvoid},))

fn = CopyAndPatch.pointer_from_function(versioninfo)
args = Ptr{UInt64}[]
nargs = 0

# stack
st = Ptr{UInt64}[ fn, pointer(args), UInt64(nargs), pointer(jit_end) ]
display(st)

jl_continuation(pointer(st,length(st)))
