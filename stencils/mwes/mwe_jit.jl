using CopyAndPatch


f(x) = x+2
# this does not work, because mul_int can't be queried with CopyAndPatch.pointer_from_function
# f(x) = (x+2)*3
stack, argstack = jit(f, (Int64,))
jit_entry = stack[end]
stackptr = pointer(stack,length(stack)-1)
ccall(jit_entry, Cvoid, (Ptr{Cvoid},), stackptr)
