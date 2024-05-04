@testset "intrinsics" begin
    f1(x) = x+2
    f2(x) = (x+2)*3-x^3
    f3(x) = (x+2)/3
    function f4(x)
        versioninfo()
        (x+2)/3
    end
    for T in (Int64,Int32), f in (f1,f2,f3)
        @test try
            memory = jit(f, (T,))
            ccall(pointer(memory), Cvoid, (Ptr{Cvoid},), C_NULL)
            true
        catch e
            @error "Failed $f(::$T) with" e
            false
        end
    end
end

@noinline function g(x,y)
    versioninfo()
    x + y
end
# TODO Moving f(x) to here gives a segfault
@testset "multiple calls" begin
    function f(x)
        versioninfo()
        g(x,2*x)
        x += log(x)
        (x+2)/3
    end
    for T in (Int64,Int32)
        @test try
            memory = jit(f, (T,))
            ccall(pointer(memory), Cvoid, (Ptr{Cvoid},), C_NULL)
            true
        catch e
            @error "Failed $f(::$T) with" e
            false
        end
    end
end

@testset "GotoIfNot" begin
    f(x) = x > 1 ? 1 : 2
    for T in (Int64,Int32)
        @test try
            memory = jit(f, (T,))
            ccall(pointer(memory), Cvoid, (Ptr{Cvoid},), C_NULL)
            true
        catch e
            @error "Failed $f(::$T) with" e
            false
        end
    end
end
