using CopyAndPatch


# can call the runtime intrinsics from libjulia-internal
a, b = Int8(1), Int8(2)
box_a, box_b = CopyAndPatch.box(a), CopyAndPatch.box(b)
box_ret = ccall((:jl_add_int,CopyAndPatch.path_libjuliainternal[]), Ptr{Cvoid},
                (Ptr{Cvoid},Ptr{Cvoid}),
                box_a, box_b)
ret = CopyAndPatch.unbox(Int8,box_ret)
box_ret = ccall((:jl_mul_int,CopyAndPatch.path_libjuliainternal[]), Ptr{Cvoid},
                (Ptr{Cvoid},Ptr{Cvoid}),
                box_a, box_b)
ret = CopyAndPatch.unbox(Int8,box_ret)
