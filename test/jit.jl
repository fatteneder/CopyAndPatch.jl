@testset "intrinsics" begin

    f(x) = (x+2)*3-x^3

    for T in (Int64,Int32)
        stack, argstack, ssas, boxes = jit(f, (T,))
        jit_entry = stack[end]
        stackptr = pointer(stack,length(stack)-1)
        ccall(jit_entry, Cvoid, (Ptr{Cvoid},), stackptr)
    end

end
