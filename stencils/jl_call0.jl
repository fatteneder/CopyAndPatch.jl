using CopyAndPatch
using JSON
using Base.Libc.Libdl

lib = dlopen(dlpath("libjulia"))

group = CopyAndPatch.StencilGroup(joinpath(@__DIR__, "jl_call0.json"))
holes = CopyAndPatch.holes(group)

patches = Dict{String,Ptr}(
    "_JIT_FUNC" => CopyAndPatch.pointer_from_function(versioninfo),
    "jl_call0" => dlsym(lib, :jl_call0)
)
bvec = CopyAndPatch.ByteVector(UInt8.(group.code.body[1]))
for h in holes
    p = get(patches, h.symbol) do
        CopyAndPatch.TODO(h.symbol)
    end
    bvec[h.offset+1] = p
end

fn = CopyAndPatch.MachineCode(bvec, Cvoid, ())
fn()
