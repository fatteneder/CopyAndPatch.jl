using CopyAndPatch
CopyAndPatch.init_stencils()


# can call the runtime intrinsics from libjulia-internal
T = Int64
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

# # this segfaults when we don't use the Core.IntrinsicFunction dispatch for pointer_from_function
# # however, that one does not work reliably as was clarified on slack
# fptr = CopyAndPatch.pointer_from_function(Base.add_int)#, :add_int)
# @show fptr, hash(Base.add_int)
# box_ret = ccall(fptr, Ptr{Cvoid},
#                 (Ptr{Cvoid},Ptr{Cvoid}),
#                 box_a, box_b)
# @show CopyAndPatch.unbox(T,box_ret)
# # fptr = CopyAndPatch.pointer_from_function(Base.mul_int, :mul_int)
# # box_ret = ccall(fptr, Ptr{Cvoid},
# #                 (Ptr{Cvoid},Ptr{Cvoid}),
# #                 box_a, box_b)
# # @show CopyAndPatch.unbox(T,box_ret)

ret = Ref{Ptr{Cvoid}}(C_NULL)
_, jitend, _ = CopyAndPatch.stencils["jit_end"]
_, jl_add_int, _ = CopyAndPatch.stencils["jl_add_int"]
stack = Ptr{Cvoid}[ pointer(jitend), Base.unsafe_convert(Ptr{Cvoid},ret), box_b, box_a, pointer(jl_add_int) ]

entry = stack[end]
@show pointer(jitend)
@show ret
ccall(entry, Cvoid, (Ptr{Cvoid},), pointer(stack, length(stack)-1)) # -1 because we removed entry
@show ret
@show CopyAndPatch.unbox(T,ret[])
