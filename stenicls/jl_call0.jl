using CopyAndPatch
using JSON
using Base.Libc.Libdl

const libjulia = dlpath("libjulia")
const lib = dlopen(libjulia)

function to_jl_function_t(fn::Function)
    pm = pointer_from_objref(typeof(fn).name.module)
    ps = pointer_from_objref(nameof(fn))
    pf = ccall((:jl_get_global, libjulia), Ptr{Cvoid}, (Ptr{Cvoid},Ptr{Cvoid}), pm, ps)
    @assert pf !== C_NULL
    return pf
end

json = JSON.parsefile(joinpath(@__DIR__, "jl_call0.json"))
group = CopyAndPatch.build(json)
bytes = group.code.body[1]
bvec = CopyAndPatch.ByteVector(bytes)

# llvm-objdump shows that there are two linker hints we need to take care of
# 1. _JIT_FUNC, 2
# 2. jl_call0, 12

p_jit_func = to_jl_function_t(versioninfo)
p_jl_call0 = dlsym(lib, :jl_call0)

os = [2, 12]
ps = [p_jit_func, p_jl_call0]
for (o, p) in zip(os, ps)
    bvec[o+1] = p
end

mc = CopyAndPatch.MachineCode(4096)
write(mc, bvec.d)
fn = CopyAndPatch.CompiledMachineCode(mc, Cvoid, ())
@show CopyAndPatch.call(fn)
