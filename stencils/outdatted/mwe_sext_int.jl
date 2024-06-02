using CopyAndPatch
CopyAndPatch.init_stencils()


T = Int64
val = Int32(123)
ret = Ref{Ptr{Cvoid}}(C_NULL)
_, jitend, _ = CopyAndPatch.stencils["jit_returnnode"]
_, jl_sext_int, _ = CopyAndPatch.stencils["jl_sext_int"]
stack = Ptr{Cvoid}[ pointer(jitend), # return
                   Base.unsafe_convert(Ptr{Cvoid},ret), CopyAndPatch.box(val), pointer_from_objref(T), pointer(jl_sext_int) # box call
                   ]
entry = stack[end]
ccall(entry, Cvoid, (Ptr{Cvoid},), pointer(stack, length(stack)-1)) # -1, because we popped entry
@show ret
@show CopyAndPatch.unbox(T,ret[])
