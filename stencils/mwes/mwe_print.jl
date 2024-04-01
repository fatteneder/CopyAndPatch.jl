using CopyAndPatch
import Base.Libc.Libdl: dlsym
CopyAndPatch.init_stencils()

jl_nothing = dlsym(CopyAndPatch.libjulia[], :jl_nothing)

ff = println
ms = methods(ff)
idx = findfirst(mm -> mm.sig === Tuple{typeof(ff),Vararg{Any}}, ms) |> something
m = ms[idx]
@assert m.specializations isa Core.SimpleVector
idx = findfirst(s -> !isnothing(s) && s.specTypes === Tuple{typeof(ff),String}, m.specializations) |> something
mi = m.specializations[3]

s = "sers oida"
args = [ pointer_from_objref(s) ]
nargs = length(args)

# direct call
ccall((:jl_invoke,CopyAndPatch.path_libjulia[]), Ptr{Cvoid}, (Ptr{Cvoid},Ptr{Cvoid},UInt32,Ptr{Cvoid}),
      CopyAndPatch.pointer_from_function(ff), pointer(args), UInt32(nargs), pointer_from_objref(mi));

# jit it
ret = Ref{Ptr{Cvoid}}(C_NULL)
_, jitend, _ = CopyAndPatch.stencils["jit_end"]
_, jl_invoke, _ = CopyAndPatch.stencils["jl_invoke"]
stack = Ptr{Cvoid}[ pointer(jitend), # return
                    Base.unsafe_convert(Ptr{Cvoid},ret), CopyAndPatch.pointer_from_function(ff), pointer(args), nargs, pointer_from_objref(mi), pointer(jl_invoke)
                  ]
entry = stack[end]
ccall(entry, Cvoid, (Ptr{Cvoid},), pointer(stack, length(stack)-1)); # -1, because we popped entry
