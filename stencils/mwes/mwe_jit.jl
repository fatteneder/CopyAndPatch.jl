using CopyAndPatch


# f(x) = x+2
# f(x) = (x+2)*3-x^3
# f(x) = (x+2)/3
function f(x)
    versioninfo()
    (x+2)/3
end
# this does not work, because mul_int can't be queried with CopyAndPatch.pointer_from_function

# stack, argstack, ssas, boxes = jit(f, (Int64,))

# this here requires jl_sext_int
# jl_sext_int requires pointers to primitive types, but those seem to be
# obtainable with pointer_from_objref, so perhaps pre-patch those in stencils?
stack, argstack, ssas, boxes = jit(f, (Int32,))

jit_entry = stack[end]
stackptr = pointer(stack,length(stack)-1)
ccall(jit_entry, Cvoid, (Ptr{Cvoid},), stackptr)
