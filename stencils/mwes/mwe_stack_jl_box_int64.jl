using CopyAndPatch
CopyAndPatch.init_stencils()


T = Int64
val = T(123)
ret = Ref{Ptr{Cvoid}}(C_NULL)
_, jitend, _ = CopyAndPatch.stencils["jit_end"]
_, jl_box_int64, _ = CopyAndPatch.stencils["stack_jl_box_int64"]
stack = Ptr{Cvoid}[ pointer(jitend), # return
                    Base.unsafe_convert(Ptr{Cvoid},ret), reinterpret(Ptr{Cvoid}, val), pointer(jl_box_int64) # box call
                   ]
entry = stack[end]
ccall(entry, Cvoid, (Ptr{Cvoid},), pointer(stack, length(stack)-1)) # -1, because we popped entry
@show ret
@show CopyAndPatch.unbox(T,ret[])
