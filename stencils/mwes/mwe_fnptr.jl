using CopyAndPatch
using JSON
using Base.Libc.Libdl

lib = dlopen(dlpath("libjulia"))
libc = dlopen(dlpath("libc.so.6"))


# 1. Prepare a function that we later use to call with mwe_fnptr.o

group = CopyAndPatch.StencilGroup(joinpath(@__DIR__, "..", "jl_call0.json"))
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

fn1 = CopyAndPatch.MachineCode(bvec, Cvoid, ())
fn1()


# 2. Patch mwe_fnptr.o

group = CopyAndPatch.StencilGroup(joinpath(@__DIR__, "mwe_fnptr.json"))
holes = CopyAndPatch.holes(group)

patches = Dict{String,Ptr}(
    "_JIT_FUNC" => fn1.ptr,
    "printf" => dlsym(libc, :printf),
    "puts" => dlsym(libc, :puts)
)
bvec = CopyAndPatch.ByteVector(UInt8.(group.code.body[1]))
bvec_data = CopyAndPatch.ByteVector(UInt8.(group.data.body[1]))

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

fn2 = CopyAndPatch.MachineCode(bvec, Cvoid, ())
fn2()
