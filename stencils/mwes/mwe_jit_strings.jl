using CopyAndPatch


function f(x)
    # return x*x
    println("SERS ", x)
end

stack, argstack, ssas, boxes = jit(f, (Int64,))

jit_entry = stack[end]
stackptr = pointer(stack,length(stack)-1)
ccall(jit_entry, Cvoid, (Ptr{Cvoid},), stackptr)
