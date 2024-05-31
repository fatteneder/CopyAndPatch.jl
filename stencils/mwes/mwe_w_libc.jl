using CopyAndPatch
using JSON
using Base.Libc.Libdl

lib = dlopen(dlpath("libjulia"))
libc = dlopen(dlpath("libc.so.6"))

group = CopyAndPatch.StencilGroup(joinpath(@__DIR__, "mwe_w_libc.json"))
holes = CopyAndPatch.holes(group)
bvec = CopyAndPatch.ByteVector(UInt8.(group.code.body[1]))

op = +
arg1 = 1.0
arg2 = 2.0
fmtstr = "ret = %f\n"

patches = Dict{String,Any}(
    "_JIT_FUNC" => CopyAndPatch.pointer_from_function(+),
    # arg1, arg2 are isbits
    "_JIT_ARG1" => UInt64(arg1),
    "_JIT_ARG2" => UInt64(arg2),
    "jl_box_float64" => dlsym(lib, :jl_box_float64),
    "jl_unbox_float64" => dlsym(lib, :jl_unbox_float64),
    "jl_call2" => dlsym(lib, :jl_call2),
    "printf" => dlsym(libc, :printf),
    ".rodata.str1.1" => pointer(fmtstr)
)

for h in holes
    local p = get(patches, h.symbol) do
        CopyAndPatch.TODO(h.symbol)
    end
    bvec[h.offset+1] = p
end

fn = CopyAndPatch.MachineCode(bvec, Nothing, Cvoid, ())
fn()
