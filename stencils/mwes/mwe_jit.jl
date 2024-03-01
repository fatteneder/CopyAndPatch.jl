using CopyAndPatch


f(x) = (x+2-1)*2
stack, argstack = jit(f, (Int64,))
jit_entry = stack[end]
stackptr = pointer(stack,length(stack)-1)
ccall(jit_entry, Cvoid, (Ptr{Cvoid},), stackptr)
