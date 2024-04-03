using CopyAndPatch


function f()
    y = 1
    println("SERS ", y)
end

stack, argstack, ssas, boxes = jit(f, ())

jit_entry = stack[end]
stackptr = pointer(stack,length(stack)-1)
ccall(jit_entry, Cvoid, (Ptr{Cvoid},), stackptr)
