@testset "intrinsics" begin
    f1(x) = x+2
    f2(x) = (x+2)*3-x^3
    f3(x) = (x+2)/3
    for T in (Int64,Int32)
        for (i,f) in enumerate((f1,f2,f3))
            expected = f(one(T))
            try
                mc = jit(f, (T,))
                res = CopyAndPatch.call(mc, one(T))
                @test res == expected
            catch e
                @error "Failed $f(::$T)"
                rethrow(e)
            end
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
    xx = 1.0
    expected = f(xx)
    for T in (Int64,Int32)
        expected = f(one(T))
        try
            mc = jit(f, (T,))
            res = CopyAndPatch.call(mc, one(T))
            @test res == expected
        catch e
            @error "Failed $f(::$T)"
            rethrow(e)
        end
    end
end

@testset "println" begin
    function f(x)
        println("sers oida: ", x)
    end
    for T in (Int64,Int32)
        expected = f(one(T))
        # io = IOBuffer()
        # TODO This segfaults when capturing stdout.
        # Maybe need to porperly handle the data section now?
        # my_redirect_stdout(io) do
            try
                mc = jit(f, (T,))
                res = CopyAndPatch.call(mc, one(T))
                @test res == expected
            catch e
                @error "Failed $f(::$T)"
                rethrow(e)
            end
        # end
        # @test contains(String(take!(io)), "sers oida: 2")
    end
end

@testset "GotoIfNot" begin
    f(x) = x > 1 ? 1 : 2
    expected = f(1.0)
    for T in (Int64,Int32)
        expected = f(one(T))
        try
            mc = jit(f, (T,))
            res = CopyAndPatch.call(mc, one(T))
            @test res == expected
        catch e
            @error "Failed $f(::$T)"
            rethrow(e)
        end
    end
end

@testset "GotoNode and PhiNode" begin
    function f(n)
        x = 2
        if n > 3
            x *= 2
        else
            x -= 3
        end
        return x
    end
    for T in (Int64,Int32)
        expected = f(one(T))
        try
            mc = jit(f, (T,))
            res = CopyAndPatch.call(mc, one(T))
            @test res == expected
        catch e
            @error "Failed $f(::$T)"
            rethrow(e)
        end
    end
end

@testset ":new node" begin
    function f(n)
        return 1:n
    end
    for T in (Int64,Int32)
        expected = f(one(T))
        try
            mc = jit(f, (T,))
            res = CopyAndPatch.call(mc, one(T))
            @test res == expected
        catch e
            @error "Failed $f(::$T)"
            rethrow(e)
        end
    end
end

@testset ":foreign node" begin
    # The function tested here is declared as int64_t my_square(int64_t x),
    # but IIUC we are passing in a boxed Int64, e.g. jl_value_t *.
    # How do these jl_value_t * boxes work? Is it maybe just an ordinary int64_t * pointing
    # to the value of x, and to determine what is boxed is determined by julia by looking just
    # at its address?
    function foreign(x::Int64)
        @ccall CopyAndPatch.libffihelpers_path[].my_square(x::Int64)::Int64
    end
    try
        expected = f(1)
        mc = jit(f, (Int64,))
        ret = CopyAndPatch.call(mc, 1)
        @test ret == expected
    catch e
        @error "Failed $f(::$T)"
        rethrow(e)
    end
end
