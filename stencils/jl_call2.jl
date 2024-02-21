using CopyAndPatch
using JSON
using Base.Libc
using Base.Libc.Libdl

lib = dlopen(dlpath("libjulia"))
libc = dlopen(dlpath("libc.so.6"))

group = CopyAndPatch.StencilGroup(joinpath(@__DIR__, "jl_call2.json"))
holes = CopyAndPatch.holes(group)
bvec = CopyAndPatch.ByteVector(UInt8.(group.code.body[1]))
bvec_data = CopyAndPatch.ByteVector(UInt8.(group.data.body[1]))

patches = Dict{String,Any}(
    "_JIT_FUNC" => CopyAndPatch.pointer_from_function(+),
    # arg1, arg2 are isbits
    # the conversion here works because there is a hole for a UInt64 although
    # CInt is Int32, I think
    # "_JIT_ARG1" => UInt64(Int32(255)),
    # "_JIT_ARG2" => UInt64(Int32(4)),
    # "jl_box_int32" => dlsym(lib, :jl_box_int32),
    # "jl_unbox_int32" => dlsym(lib, :jl_unbox_int32),
    # "_JIT_ARG1" => reinterpret(UInt64, Cdouble(255)),
    # "_JIT_ARG2" => reinterpret(UInt64, Cdouble(4)),
    "_JIT_ARG1" => UInt64(Cdouble(255)),
    "_JIT_ARG2" => UInt64(Cdouble(4)),
    "jl_box_float64" => dlsym(lib, :jl_box_float64),
    "jl_unbox_float64" => dlsym(lib, :jl_unbox_float64),
    "jl_call2" => dlsym(lib, :jl_call2),
)

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

fn = CopyAndPatch.MachineCode(bvec, Cdouble, ())
@show fn()
