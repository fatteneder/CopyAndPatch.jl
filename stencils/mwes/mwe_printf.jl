using CopyAndPatch
using JSON
using Base.Libc

json = JSON.parsefile(joinpath(@__DIR__, "mwe_printf.json"))
group = CopyAndPatch.build(json)
bytes = group.code.body[1]
bvec = CopyAndPatch.ByteVector(bytes)

# llvm-objdump shows that there are two linker hints we need to take care of
# 1. pointer to the string "sers\n"
# 2. pointer to puts

str = "sers\n"
p_str = pointer(str)
bvec[2+1] = p_str

lib = Libc.Libdl.dlopen(Libc.Libdl.dlpath("/usr/lib/libc.so.6"))
p_put = Libc.Libdl.dlsym(lib, :puts)
bvec[12+1] = p_put

mc = CopyAndPatch.MachineCode(4096)
write(mc, bvec.d)
fn = CopyAndPatch.CompiledMachineCode(mc, Nothing, Cint, ())
@show CopyAndPatch.call(fn)
