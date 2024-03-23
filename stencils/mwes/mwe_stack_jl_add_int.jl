using CopyAndPatch


T = UInt64
a, b = T(2), T(3)
box_a, box_b = CopyAndPatch.box(a), CopyAndPatch.box(b)
box_ret = ccall((:jl_add_int,CopyAndPatch.path_libjuliainternal[]), Ptr{Cvoid},
                (Ptr{Cvoid},Ptr{Cvoid}),
                box_a, box_b)
@show CopyAndPatch.unbox(T,box_ret)
# box_ret = ccall((:jl_mul_int,CopyAndPatch.path_libjuliainternal[]), Ptr{Cvoid},
#                 (Ptr{Cvoid},Ptr{Cvoid}),
#                 box_a, box_b)
# @show CopyAndPatch.unbox(T,box_ret)

# this segfaults when we don't use the Core.IntrinsicFunction dispatch for pointer_from_function
# however, that one does not work reliably as was clarified on slack
fptr = CopyAndPatch.pointer_from_function(Base.add_int)#, :add_int)
@show fptr, hash(Base.add_int)
box_ret = ccall(fptr, Ptr{Cvoid},
                (Ptr{Cvoid},Ptr{Cvoid}),
                box_a, box_b)
@show CopyAndPatch.unbox(T,box_ret)
# fptr = CopyAndPatch.pointer_from_function(Base.mul_int, :mul_int)
# box_ret = ccall(fptr, Ptr{Cvoid},
#                 (Ptr{Cvoid},Ptr{Cvoid}),
#                 box_a, box_b)
# @show CopyAndPatch.unbox(T,box_ret)
