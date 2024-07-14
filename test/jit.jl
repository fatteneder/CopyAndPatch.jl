f1(x) = x+2
f2(x) = (x+2)*3-x^3
f3(x) = (x+2)/3
@testset "intrinsics" begin
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

function mybitcast(x)
    Core.bitcast(UInt, x)
end
@testset "bit" begin
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
function f(x)
    versioninfo()
    g(x,2*x)
    x += log(x)
    (x+2)/3
end
@testset "multiple calls" begin
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

function f_println(x)
    println("sers oida: ", x)
end
@testset "println" begin
    for T in (Int64,Int32)
        try
            io = IOBuffer()
            my_redirect_stdout(io) do
                mc = jit(f_println, (T,))
                mc(one(T))
            end
            @test contains(String(take!(io)), "sers oida: 1")
        catch e
            @error "Failed f(::$T)"
            rethrow(e)
        end
    end
end

f(x) = x > 1 ? 1 : 2
@testset "GotoIfNot" begin
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

function f(n)
    x = 2
    if n > 3
        x *= 2
    else
        x -= 3
    end
    return x
end
@testset "GotoNode and PhiNode" begin
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

function f(n)
    return 1:n
end
@testset ":new node" begin
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
function foreign_1(x::Int64)
    @ccall CopyAndPatch.libmwes_path[].mwe_my_square(x::Int64)::Int64
end
function foreign_2(n::Int64)
    @ccall CopyAndPatch.libmwes_path[].mwe_foreign_carg_cret(n::Clonglong)::Clonglong
end
function foreign_3(n::Int64)
    @ccall CopyAndPatch.libmwes_path[].mwe_foreign_carg_jlret(n::Clonglong)::Any
end
function foreign_w_jl_1(n)
    @ccall CopyAndPatch.libmwes_path[].mwe_foreign_jlarg_cret(n::Any)::Clonglong
end
function foreign_w_jl_2(n)
    @ccall CopyAndPatch.libmwes_path[].mwe_foreign_jlarg_jlret(n::Any)::Any
end
@testset ":foreign node" begin
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

function mytuple(n::Int64)
    tpl = (n,2*n)
    return tpl
end
@testset "make and return tuple" begin
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

@noinline opaque() = invokelatest(identity, nothing) # Something opaque
# from the manual: https://docs.julialang.org/en/v1/devdocs/ssair/#PhiC-nodes-and-Upsilon-nodes
function foo_no_throw()
    local y
    x = 1
    try
        y = 2
        opaque()
        println("SERS")
        y = 3
        # error() ### disabling error inserts a :leave
    catch
    end
    (x, y)
end
function foo_throw()
    local y
    x = 1
    try
        y = 2
        opaque()
        println("SERS")
        y = 3
        error()
    catch
    end
    (x, y)
end
function foo_catch()
    local y
    x = 1
    try
        y = 2
        opaque()
        println("SERS")
        y = 3
        error()
    catch e
        x += 2
    end
    (x, y)
end
@testset "exceptions" begin
    try
        expected = foo_no_throw()
        mc = jit(foo_no_throw, ())
        ret = CopyAndPatch.call(mc)
        @test ret == expected
    catch e
        @error "Failed foo_no_throw()"
        rethrow(e)
    end

    try
        expected = foo_throw()
        mc = jit(foo_throw, ())
        ret = CopyAndPatch.call(mc)
        @test ret == expected
    catch e
        @error "Failed foo_throw()"
        rethrow(e)
    end

    try
        expected = foo_catch()
        mc = jit(foo_catch, ())
        ret = CopyAndPatch.call(mc)
        @test ret == expected
    catch e
        @error "Failed foo_catch()"
        rethrow(e)
    end
end

function f_unused_arguments(n)
    return 321
end
@testset "unused arguments" begin
    try
        expected = f_unused_arguments(123)
        mc = jit(f_unused_arguments, (Int64,))
        ret = mc(123)
        @test ret == expected
    catch e
        @error "Failed f_unused_arguments()"
        rethrow(e)
    end
end

function f_collect(n)
    return collect(1:n)
end
@testset "simple collect" begin
    try
        expected = f_collect(123)
        mc = jit(f_collect, (Int64,))
        ret = mc(123)
        @test ret == expected
    catch e
        @error "Failed f_collect()"
        rethrow(e)
    end
end

function f_implicit_block(n)
    p = 2
    for i in 2*p:p:n
    end
end
@testset "potential bug in implicit block logic in src/interpreter.c" begin
    # see comment about <= vs < in stencils/ast_phinode.c
    try
        expected = f_implicit_block(5)
        mc = jit(f_implicit_block, (Int64,))
        ret = mc(5)
        @test ret == expected
    catch e
        @error "Failed f_implicit_block()"
        rethrow(e)
    end
end

function f_avoid_box(n)
    s = 0
    p = 2
    for i in 2*p:p:n
        println(i)
        s += rand()
    end
    s
end
@testset "use value_pointer over box" begin
    # calling f_avoid_box fails to store a box of 1.1102230246251565e-16 inline
    # in the subsequent mul_float call this gives a type mismatch error
    # interesetingly this only happens on the first call, afterwards it just works
    try
        Random.seed!(123)
        expected = f_avoid_box(5)
        Random.seed!(123)
        mc = jit(f_avoid_box, (Int64,))
        ret = mc(5)
        @test ret == expected
    catch e
        @error "Failed f_avoid_box()"
        rethrow(e)
    end
end

function f_undefvar(n)
    p = 2
    for i in 2*p:p:n
        s += rand()
    end
end
@testset "throw_undef_if_not" begin
    try
        expected = try
            f_undefvar(5)
        catch e
            e
        end
        mc = jit(f_undefvar, (Int64,))
        ret = try
            mc(5)
        catch e
            e
        end
        @test ret == expected
    catch e
        @error "Failed f_undefvar()"
        rethrow(e)
    end
end
