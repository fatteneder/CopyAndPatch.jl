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

@testset "bit" begin
    function mybitcast(x)
        Core.bitcast(UInt, x)
    end
    expected = mybitcast(C_NULL)
    try
        mc = jit(mybitcast, (typeof(C_NULL),))
        res = CopyAndPatch.call(mc, C_NULL)
        @test res == expected
    catch e
        @error "Failed mybitcast(::$(typeof(C_NULL)))"
        rethrow(e)
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

mutable struct JIT_MutDummy
    x
end
struct JIT_ImmutDummy
    x
end
@testset ":foreign node" begin
    function foreign_1(x::Int64)
        @ccall CopyAndPatch.libmwes_path[].mwe_my_square(x::Int64)::Int64
    end
    function foreign_2(n::Int64)
        @ccall CopyAndPatch.libmwes_path[].mwe_foreign_carg_cret(n::Clonglong)::Clonglong
    end
    function foreign_3(n::Int64)
        @ccall CopyAndPatch.libmwes_path[].mwe_foreign_carg_jlret(n::Clonglong)::Any
    end
    for f in (foreign_1,foreign_2,foreign_3)
        try
            expected = f(3)
            mc = jit(f, (Int64,))
            ret = CopyAndPatch.call(mc, 3)
            @test ret == expected
        catch e
            @error "Failed $f(::Int64)"
            rethrow(e)
        end
    end

    function foreign_w_jl_1(n)
        @ccall CopyAndPatch.libmwes_path[].mwe_foreign_jlarg_cret(n::Any)::Clonglong
    end
    function foreign_w_jl_2(n)
        @ccall CopyAndPatch.libmwes_path[].mwe_foreign_jlarg_jlret(n::Any)::Any
    end
    for f in (foreign_w_jl_1,foreign_w_jl_2)
        for T in (JIT_MutDummy,JIT_ImmutDummy)
            arg = T(3)
            try
                expected = f(arg)
                mc = jit(f, (T,))
                ret = CopyAndPatch.call(mc, arg)
                @test ret == expected
            catch e
                @error "Failed $f(::$T)"
                rethrow(e)
            end
        end
    end
end

@testset "make and return tuple" begin
    function mytuple(n::Int64)
        tpl = (n,2*n)
        return tpl
    end
    try
        expected = mytuple(3)
        mc = jit(mytuple, (Int64,))
        ret = CopyAndPatch.call(mc, 3)
        @test ret == expected
    catch e
        @error "Failed mytuple(::Int64)"
        rethrow(e)
    end
end
