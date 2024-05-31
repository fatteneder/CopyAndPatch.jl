using CopyAndPatch
using JSON
using Base.Libc

json = JSON.parsefile(joinpath(@__DIR__, "mwe_int.json"))
group = CopyAndPatch.build(json)
bytes = group.code.body[1]
bvec = CopyAndPatch.ByteVector(bytes)

# llvm-objdump shows that the `a` pointer is 32bit
# so we malloc an int buffer, fill it with the desired value,
# and then insert that pointer into the body
buf = Ptr{UInt8}(Libc.calloc(sizeof(Cint), 8))
a = Int32(1024)
for i in 3:-1:0
    unsafe_store!(buf, UInt8(a >> (8*i) & 0xFF), i+1)
end
bvec[3] = buf

mc = CopyAndPatch.MachineCode(4096)
write(mc, bvec.d)
fn = CopyAndPatch.CompiledMachineCode(mc, Nothing, Cint, ())
@show CopyAndPatch.call(fn)

Libc.free(buf)
buf = C_NULL
bbuf = C_NULL
