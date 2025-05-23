# from https://github.com/JuliaLang/julia/issues/12711#issuecomment-912740865
function my_redirect_stdout(f::Function, io::IO)
    old_stdout = stdout
    rd, = redirect_stdout()
    task = @async write(io, rd)
    try
        ret = f()
        Libc.flush_cstdio()
        flush(stdout)
        return ret
    finally
        close(rd)
        redirect_stdout(old_stdout)
        wait(task)
    end
end


f1(x) = x + 2
f2(x) = (x + 2) * 3 - x^3
f3(x) = (x + 2) / 3
@testset "intrinsics" begin
    for T in (Int64, Int32)
        for (i, f) in enumerate((f1, f2, f3))
            expected = f(one(T))
            try
                res = @cpjit(f, (one(T),))
                @test res == expected
            catch e
                @error "Failed $f(::$T)"
                rethrow(e)
            end
        end
    end
end

function mybitcast(x)
    return Core.bitcast(UInt, x)
end
@testset "bit" begin
    expected = mybitcast(C_NULL)
    try
        res = @cpjit(mybitcast, (C_NULL,))
        @test res == expected
    catch e
        @error "Failed mybitcast(::$(typeof(C_NULL)))"
        rethrow(e)
    end
end

@noinline function g(x, y)
    InteractiveUtils.versioninfo()
    return x + y
end
function f(x)
    InteractiveUtils.versioninfo()
    g(x, 2 * x)
    x += log(x)
    return (x + 2) / 3
end
@testset "multiple calls" begin
    for T in (Int64, Int32)
        expected = f(one(T))
        try
            res = @cpjit(f, (one(T),))
            @test res == expected
        catch e
            @error "Failed $f(::$T)"
            rethrow(e)
        end
    end
end

function f_println(x)
    return println("sers oida: ", x)
end
@testset "println" begin
    for T in (Int64, Int32)
        try
            io = IOBuffer()
            my_redirect_stdout(io) do
                @cpjit(f_println, (one(T),))
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
    for T in (Int64, Int32)
        expected = f(one(T))
        try
            res = @cpjit(f, (one(T),))
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
    for T in (Int64, Int32)
        expected = f(one(T))
        try
            res = @cpjit(f, (one(T),))
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
    for T in (Int64, Int32)
        expected = f(one(T))
        try
            res = @cpjit(f, (one(T),))
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
    return @ccall CP.LIBMWES_PATH[].mwe_my_square(x::Int64)::Int64
end
function foreign_2(n::Int64)
    return @ccall CP.LIBMWES_PATH[].mwe_foreign_carg_cret(n::Clonglong)::Clonglong
end
function foreign_3(n::Int64)
    return @ccall CP.LIBMWES_PATH[].mwe_foreign_carg_jlret(n::Clonglong)::Any
end
function foreign_w_jl_1(n)
    return @ccall CP.LIBMWES_PATH[].mwe_foreign_jlarg_cret(n::Any)::Clonglong
end
function foreign_w_jl_2(n)
    return @ccall CP.LIBMWES_PATH[].mwe_foreign_jlarg_jlret(n::Any)::Any
end
@testset ":foreign node" begin
    for f in (foreign_1, foreign_2, foreign_3)
        try
            expected = f(3)
            ret = @cpjit(f, (3,))
            @test ret == expected
        catch e
            @error "Failed $f(::Int64)"
            rethrow(e)
        end
    end

    for f in (foreign_w_jl_1, foreign_w_jl_2)
        for T in (JIT_MutDummy, JIT_ImmutDummy)
            arg = T(3)
            try
                expected = f(arg)
                ret = @cpjit(f, (arg,))
                @test ret == expected
            catch e
                @error "Failed $f(::$T)"
                rethrow(e)
            end
        end
    end
end

function mytuple(n::Int64)
    tpl = (n, 2 * n)
    return tpl
end
@testset "make and return tuple" begin
    try
        expected = mytuple(3)
        ret = @cpjit(mytuple, (3,))
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
    return (x, y)
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
    return (x, y)
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
    return (x, y)
end
@testset "exceptions" begin
    try
        expected = foo_no_throw()
        ret = @cpjit(foo_no_throw, ())
        @test ret == expected
    catch e
        @error "Failed foo_no_throw()"
        rethrow(e)
    end

    try
        expected = foo_throw()
        ret = @cpjit(foo_throw, ())
        @test ret == expected
    catch e
        @error "Failed foo_throw()"
        rethrow(e)
    end

    try
        expected = foo_catch()
        ret = @cpjit(foo_catch, ())
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
        ret = @cpjit(f_unused_arguments, (123,))
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
        ret = @cpjit(f_collect, (123,))
        @test ret == expected
    catch e
        @error "Failed f_collect()"
        rethrow(e)
    end
end

function f_implicit_block(n)
    p = 2
    for i in (2 * p):p:n
    end
    return
end
@testset "potential bug in implicit block logic in src/interpreter.c" begin
    # see comment about <= vs < in stencils/ast_phinode.c
    try
        expected = f_implicit_block(5)
        ret = @cpjit(f_implicit_block, (5,))
        @test ret == expected
    catch e
        @error "Failed f_implicit_block()"
        rethrow(e)
    end
end

### TODO Broke when updating from fatteneder/julia@cpjit-mmap-v2 to fatteneder/julia@cpjit-mmap-v3,
### apparently we have to deal with llvmcalls now ...
#
# function f_phiblock_w_nothing()
#     @debug "hello world"
#     return 1
# end
# @testset "logging macro" begin
#     try
#         expected = f_phiblock_w_nothing()
#         ret = @cpjit(f_phiblock_w_nothing, ())
#         @test ret == expected
#     catch e
#         @error "Failed f_phiblock_w_nothing()"
#         rethrow(e)
#     end
# end

# struct InterpolateIntoMacro
#     x::Any
# end
# function f_interpolate_into_logging_macro(a::InterpolateIntoMacro)
#     @debug "$(a.x)"
#     return 123
# end
# @testset "interpolation into logging macro" begin
#     try
#         a = InterpolateIntoMacro(123)
#         expected = f_interpolate_into_logging_macro(a)
#         ret = @cpjit(f_interpolate_into_logging_macro, (a,))
#         @test ret == expected
#     catch e
#         @error "Failed f_interpolate_into_logging_macro()"
#         rethrow(e)
#     end
# end

function f_avoid_box(n)
    s = 0
    p = 2
    for i in (2 * p):p:n
        println(i)
        s += rand()
    end
    return s
end
@testset "use value_pointer over box" begin
    # calling f_avoid_box fails to store a box of 1.1102230246251565e-16 inline
    # in the subsequent mul_float call this gives a type mismatch error
    # interesetingly this only happens on the first call, afterwards it just works
    try
        Random.seed!(123)
        expected = f_avoid_box(5)
        Random.seed!(123)
        ret = @cpjit(f_avoid_box, (5,))
        @test ret == expected
    catch e
        @error "Failed f_avoid_box()"
        rethrow(e)
    end
end

function f_undefvar(n)
    p = 2
    for i in (2 * p):p:n
        s += rand()
    end
    return
end
@testset "throw_undef_if_not" begin
    try
        expected = try
            f_undefvar(5)
        catch e
            e
        end
        ret = try
            @cpjit(f_undefvar, (5,))
        catch e
            e
        end
        @test ret == expected
    catch e
        @error "Failed f_undefvar()"
        rethrow(e)
    end
end

# https://en.wikipedia.org/wiki/Sieve_of_Eratosthenes
function eratosthenes_sieve(n)
    qs = 1:n
    ms = zeros(Int64, length(qs))
    p = 2
    while true
        for i in (2 * p):p:n
            ms[i] = 1
        end
        next_p = nothing
        for i in 1:length(qs)
            if ms[i] == 0 && i > p
                next_p = i
                break
            end
        end
        isnothing(next_p) && break
        p = next_p
    end
    ps = [ q for (i, q) in enumerate(qs) if ms[i] == 0 && q > 1 ]
    return ps
end
@testset "Eratosthenes sieve" begin
    n = 30
    expected = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]
    try
        ret = @cpjit(eratosthenes_sieve, (n,))
        @test ret == expected
    catch e
        @error "Failed eratosthenes_sieve($n)"
        rethrow(e)
    end
end

function f_closure(x)
    function closure()
        return println("hello from the closure, 2x = ", 2 * x)
    end
    closure()
    return closure
end
@testset "call and return closure" begin
    for T in (Int64, Int32)
        try
            io = IOBuffer()
            x = rand(T)
            ret = my_redirect_stdout(io) do
                ret = @cpjit(f_closure, (x,))
            end
            @test contains(String(take!(io)), "hello from the closure, 2x = $(2 * x)")
        catch e
            @error "Failed f_closure(::$T)"
            rethrow(e)
        end
    end
end

function f_vararg(x...)
    return sum(x)
end
@testset "vararg" begin
    try
        args = (1,2,3)
        expected = f_vararg(args...)
        ret = @cpjit(f_vararg, args)
        @test ret == expected
    catch e
        @error "Failed f_vararg()"
        rethrow(e)
    end
    try
        args = (1,2,3)
        expected = f_vararg(args...)
        ret = @cpjit(f_vararg, args, (Vararg{Int64},))
        @test ret == expected
    catch e
        @error "Failed f_vararg()"
        rethrow(e)
    end
end

@testset ":foreigncall with nreq>0 and (cconv|effects)" begin
    try
        ret = @cpjit(IOBuffer, ())
        @test ret isa IOBuffer
    catch e
        @error "Failed IOBuffer()"
        rethrow(e)
    end
end
