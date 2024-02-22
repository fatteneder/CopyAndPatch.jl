using CopyAndPatch
using JSON
using Base.Libc
using Base.Libc.Libdl

lib = dlopen(dlpath("libjulia"))
libc = dlopen(dlpath("libc.so.6"))

group = CopyAndPatch.StencilGroup(joinpath(@__DIR__, "jl_call2_float.json"))
holes = CopyAndPatch.holes(group)
bvec = CopyAndPatch.ByteVector(UInt8.(group.code.body[1]))
if !isempty(group.data.body)
    bvec_data = CopyAndPatch.ByteVector(UInt8.(group.data.body[1]))
else
    bvec_data = Any[]
end

patches = Dict{String,Any}(
    "_JIT_FUNC" => CopyAndPatch.pointer_from_function(+),
    "_JIT_ARG1" => convert(UInt64, reinterpret(UInt32, Cfloat(255f0))),
    "_JIT_ARG2" => convert(UInt64, reinterpret(UInt32, Cfloat(4.1f0))),
    "jl_box_float32" => dlsym(lib, :jl_box_float32),
    "jl_unbox_float32" => dlsym(lib, :jl_unbox_float32),
    "jl_call2" => dlsym(lib, :jl_call2),
    "printf" => dlsym(libc, :printf)
)

@show patches["_JIT_ARG1"]
@show patches["_JIT_ARG2"]

for h in holes
    if startswith(h.symbol, ".rodata")
        p = pointer(bvec_data.d, h.addend+1)
    else
        local p = get(patches, h.symbol) do
            CopyAndPatch.TODO(h.symbol)
        end
    end
    bvec[h.offset+1] = p
end

fn = CopyAndPatch.MachineCode(bvec, Cfloat, ())
@show fn()
