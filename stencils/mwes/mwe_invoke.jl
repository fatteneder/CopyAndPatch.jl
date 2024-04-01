using CopyAndPatch


g = versioninfo
precompile(g, ())
m = methods(g)[1]
mi = m.specializations isa Core.SimpleVector ? m.specializations[1] : m.specializations

args = []
nargs = 0
ret = Ref{Ptr{Cvoid}}(C_NULL)
_, jitend, _ = CopyAndPatch.stencils["jit_end"]
_, jl_invoke, _ = CopyAndPatch.stencils["jl_invoke"]
stack = Ptr{Cvoid}[ pointer(jitend), # return
                    Base.unsafe_convert(Ptr{Cvoid},ret), CopyAndPatch.pointer_from_function(g), pointer(args), nargs, pointer_from_objref(mi), pointer(jl_invoke)
                  ]
entry = stack[end]
ccall(entry, Cvoid, (Ptr{Cvoid},), pointer(stack, length(stack)-1)) # -1, because we popped entry
