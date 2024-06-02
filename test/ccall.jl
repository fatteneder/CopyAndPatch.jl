const libccalltest = joinpath(@__DIR__, "..", "stencils", "bin", "libccalltest.so")

#### These tests were crafted by me to figure things out

function mimic_test(x)
    a1 = Ref(x)
    a2 = @ccall jl_value_ptr(a1::Any)::Ptr{Cvoid}
    a11 = Base.bitcast(Ptr{Int64}, a2)
    a14 = @ccall libccalltest.test_echo_p(a11::Ptr{Int64})::Ptr{Int64}
    a15 = Base.pointerref(a14, 1, 1)
    return a15
end
@testset "mimic ccall test" begin
    mc = jit(mimic_test, (Int64,))
    result = CopyAndPatch.call(mc, 132)
    expected = mimic_test(132)
    @test result == expected
end


#### The following tests were copied from julia/src/ccall.jl

const verbose = true
ccall((:set_verbose, libccalltest), Cvoid, (Int32,), verbose)

# Test for proper round-trip of Ref{T} type
function gen_ccall_echo(x, T, U, ret=nothing)
    # Construct a noninline function to do all the work, this is necessary
    # to make sure object x is still valid (rooted as argument)
    # when loading the pointer.
    # This works as long as we still keep the argument
    # rooted but might fail if we are smarter about eliminating dead root.

    # `eval` in global scope to make sure the function is not a closure
    func_ex = :(ccall((:test_echo_p, libccalltest), $T, ($U,), x))
    # It is not allowed to allocate after the ccall returns
    # and before calling `ret`.
    if ret !== nothing
        func_ex = :($ret($func_ex))
    end
    @gensym func_name
    @eval @noinline $func_name(x) = $func_ex
    esc(quote
            mc = jit($func_name, (typeof($x),))
            CopyAndPatch.call(mc, $x)
    end)
    # :($func_name($(esc(x))))
end

macro ccall_echo_func(x, T, U)
    gen_ccall_echo(x, T, U)
end
macro ccall_echo_load(x, T, U)
    gen_ccall_echo(x, T, U, :unsafe_load)
end
macro ccall_echo_objref(x, T, U)
    gen_ccall_echo(x, :(Ptr{$T}), U, :unsafe_pointer_to_objref)
end

mutable struct IntLike
    x::Int
end
@test @ccall_echo_load(132, Ptr{Int}, Ref{Int}) === 132
@test @ccall_echo_load(Ref(921), Ptr{Int}, Ref{Int}) === 921
@test @ccall_echo_load(IntLike(993), Ptr{Int}, Ref{IntLike}) === 993
@test @ccall_echo_load(IntLike(881), Ptr{IntLike}, Ref{IntLike}).x === 881
@test @ccall_echo_func(532, Int, Int) === 532
if Sys.WORD_SIZE == 64
    # this test is valid only for x86_64 and win64
    @test @ccall_echo_func(164, IntLike, Int).x === 164
end
@test @ccall_echo_func(IntLike(828), Int, IntLike) === 828
@test @ccall_echo_func(913, Any, Any) === 913
@test @ccall_echo_objref(553, Ptr{Any}, Any) === 553
@test @ccall_echo_func(124, Ref{Int}, Any) === 124
@test @ccall_echo_load(422, Ptr{Any}, Ref{Any}) === 422
@test @ccall_echo_load([383], Ptr{Int}, Ref{Int}) === 383
@test @ccall_echo_load(Ref([144,172],2), Ptr{Int}, Ref{Int}) === 172
# that test is also ignored in julia
# # @test @ccall_echo_load(Ref([8],1,1), Ptr{Int}, Ref{Int}) === 8


# Tests for passing and returning structs

let a, ci_ary, x
    a = 20 + 51im

    ctest(a) = ccall((:ctest, libccalltest), Complex{Int}, (Complex{Int},), a)
    mc = jit(ctest, (typeof(a),))
    x = mc(a)

    @test x == a + 1 - 2im

    ci_ary = [a] # Make sure the array is alive during unsafe_load
    cptest(ci_ary) = unsafe_load(ccall((:cptest, libccalltest), Ptr{Complex{Int}},
                                 (Ptr{Complex{Int}},), ci_ary))
    mc = jit(cptest, (typeof(ci_ary),))
    x = mc(ci_ary)

    @test x == a + 1 - 2im
    @test a == 20 + 51im

    cptest_static(a) = ccall((:cptest_static, libccalltest), Ptr{Complex{Int}}, (Ref{Complex{Int}},), a)
    mc = jit(cptest_static, (typeof(a),))
    x = mc(a)
    @test unsafe_load(x) == a
    @assert x !== C_NULL
    Libc.free(convert(Ptr{Cvoid}, x))
end

let a, b, x
    a = 2.84 + 5.2im

    cgtest(a) = ccall((:cgtest, libccalltest), ComplexF64, (ComplexF64,), a)
    mc = jit(cgtest, (typeof(a),))
    x = mc(a)

    @test x == a + 1 - 2im

    b = [a] # Make sure the array is alive during unsafe_load
    cgptest(b) = unsafe_load(ccall((:cgptest, libccalltest), Ptr{ComplexF64}, (Ptr{ComplexF64},), b))
    mc = jit(cgptest, (typeof(b),))
    x = mc(b)

    @test x == a + 1 - 2im
    @test a == 2.84 + 5.2im
end

let a, b, x
    a = 3.34f0 + 53.2f0im

    cftest(a) = ccall((:cftest, libccalltest), ComplexF32, (ComplexF32,), a)
    mc = jit(cftest, (typeof(a),))
    x = mc(a)

    @test x == a + 1 - 2im

    b = [a] # Make sure the array is alive during unsafe_load
    cfptest(b) = unsafe_load(ccall((:cfptest, libccalltest), Ptr{ComplexF32}, (Ptr{ComplexF32},), b))
    mc = jit(cfptest, (typeof(b),))
    x = mc(b)

    @test x == a + 1 - 2im
    @test a == 3.34f0 + 53.2f0im
end


## Tests for native Julia data types

let a
    a = 2.84 + 5.2im

    cptest(a) = ccall((:cptest, libccalltest), Ptr{Complex{Int}}, (Ptr{Complex{Int}},), a)
    mc = jit(cptest, (typeof(a),))
    @test_throws MethodError mc(a)
end


## Tests for various sized data types (ByVal)

mutable struct Struct1
    x::Float32
    y::Float64
end
struct Struct1I
    x::Float32
    y::Float64
end
copy(a::Struct1) = Struct1(a.x, a.y)
copy(a::Struct1I) = a

test_1_Struct1(a2,b) = ccall((:test_1, libccalltest), Struct1, (Struct1, Float32), a2, b)
test_1_Struct1I(a2,b) = ccall((:test_1, libccalltest), Struct1I, (Struct1I, Float32), a2, b)
let
for Struct in (Struct1,Struct1I)
    a = Struct(352.39422f23, 19.287577)
    b = Float32(123.456)

    a2 = copy(a)
    if Struct === Struct1
        mc = jit(test_1_Struct1, (typeof(a2),typeof(b)))
        x = mc(a2, b)
    else
        mc = jit(test_1_Struct1I, (typeof(a2),typeof(b)))
        x = mc(a2, b)
    end

    @test a2.x == a.x && a2.y == a.y
    @test !(a2 === x)

    @test x.x ≈ a.x + 1*b
    @test x.y ≈ a.y - 2*b
end
end

let a, b, x
    a = Struct1(352.39422f23, 19.287577)
    b = Float32(123.456)
    a2 = copy(a)

    test_1long_a(a2,b) = ccall((:test_1long_a, libccalltest), Struct1, (Int, Int, Int, Struct1, Float32), 2, 3, 4, a2, b)
    mc = jit(test_1long_a, (typeof(a2),typeof(b)))
    x = mc(a2, b)
    @test a2.x == a.x && a2.y == a.y
    @test !(a2 === x)
    @test x.x ≈ a.x + b + 9
    @test x.y ≈ a.y - 2*b

    test_1long_b(a2,b) = ccall((:test_1long_b, libccalltest), Struct1, (Int, Float64, Int, Struct1, Float32), 2, 3, 4, a2, b)
    mc = jit(test_1long_b, (typeof(a2),typeof(b)))
    x = mc(a2, b)
    @test a2.x == a.x && a2.y == a.y
    @test !(a2 === x)
    @test x.x ≈ a.x + b + 9
    @test x.y ≈ a.y - 2*b

    test_1long_c(a2,b) = ccall((:test_1long_c, libccalltest), Struct1, (Int, Float64, Int, Int, Struct1, Float32), 2, 3, 4, 5, a2, b)
    mc = jit(test_1long_c, (typeof(a2),typeof(b)))
    x = mc(a2, b)
    @test a2.x == a.x && a2.y == a.y
    @test !(a2 === x)
    @test x.x ≈ a.x + b + 14
    @test x.y ≈ a.y - 2*b
end

let a, b, x, y
    a = Complex{Int32}(Int32(10),Int32(31))
    b = Int32(42)

    test_2a(a,b) = ccall((:test_2a, libccalltest), Complex{Int32}, (Complex{Int32}, Int32), a, b)
    test_2b(a,b) = ccall((:test_2b, libccalltest), Complex{Int32}, (Complex{Int32}, Int32), a, b)
    mc = jit(test_2a, (typeof(a),typeof(b)))
    x = mc(a,b)
    mc = jit(test_2b, (typeof(a),typeof(b)))
    y = mc(a,b)

    @test a == Complex{Int32}(Int32(10),Int32(31))

    @test x == y
    @test x == a + b*1 - b*2im
end

let a, b, x, y, z
    a = Complex{Int64}(Int64(20),Int64(51))
    b = Int64(42)

    x = ccall((:test_3a, libccalltest), Complex{Int64}, (Complex{Int64}, Int64), a, b)
    y = ccall((:test_3b, libccalltest), Complex{Int64}, (Complex{Int64}, Int64), a, b)
    z = ccall((:test_128, libccalltest), Complex{Int64}, (Complex{Int64}, Int64), a, b)

    @test a == Complex{Int64}(Int64(20),Int64(51))

    @test x == y
    @test x == a + b*1 - b*2im

    @test z == a + 1*b
end

mutable struct Struct4
    x::Int32
    y::Int32
    z::Int32
end
struct Struct4I
    x::Int32
    y::Int32
    z::Int32
end

test_4_Struct4(a,b) = ccall((:test_4, libccalltest), Struct4, (Struct4, Int32), a, b)
test_4_Struct4I(a,b) = ccall((:test_4, libccalltest), Struct4I, (Struct4I, Int32), a, b)
let
for Struct in (Struct4,Struct4I)
    a = Struct(-512275808,882558299,-2133022131)
    b = Int32(42)

    if Struct === Struct4
        mc = jit(test_4_Struct4, (typeof(a),typeof(b)))
        x = mc(a,b)
    else
        mc = jit(test_4_Struct4I, (typeof(a),typeof(b)))
        x = mc(a,b)
    end

    @test x.x == a.x+b*1
    @test x.y == a.y-b*2
    @test x.z == a.z+b*3
end
end

mutable struct Struct5
    x::Int32
    y::Int32
    z::Int32
    a::Int32
end
struct Struct5I
    x::Int32
    y::Int32
    z::Int32
    a::Int32
end

test_5_Struct5(a,b) = ccall((:test_5, libccalltest), Struct5, (Struct5, Int32), a, b)
test_5_Struct5I(a,b) = ccall((:test_5, libccalltest), Struct5I, (Struct5I, Int32), a, b)
let
for Struct in (Struct5,Struct5I)
    a = Struct(1771319039, 406394736, -1269509787, -745020976)
    b = Int32(42)

    if Struct === Struct5
        mc = jit(test_5_Struct5, (typeof(a),typeof(b)))
        x = mc(a,b)
    else
        mc = jit(test_5_Struct5I, (typeof(a),typeof(b)))
        x = mc(a,b)
    end

    @test x.x == a.x+b*1
    @test x.y == a.y-b*2
    @test x.z == a.z+b*3
    @test x.a == a.a-b*4
end
end

mutable struct Struct6
    x::Int64
    y::Int64
    z::Int64
end
struct Struct6I
    x::Int64
    y::Int64
    z::Int64
end

test_6_Struct6(a,b) = ccall((:test_6, libccalltest), Struct6, (Struct6, Int64), a, b)
test_6_Struct6I(a,b) = ccall((:test_6, libccalltest), Struct6I, (Struct6I, Int64), a, b)
let
for Struct in (Struct6,Struct6I)
    a = Struct(-654017936452753226, -5573248801240918230, -983717165097205098)
    b = Int64(42)

    if Struct === Struct6
        mc = jit(test_6_Struct6, (typeof(a),typeof(b)))
        x = mc(a,b)
    else
        mc = jit(test_6_Struct6I, (typeof(a),typeof(b)))
        x = mc(a,b)
    end

    @test x.x == a.x+b*1
    @test x.y == a.y-b*2
    @test x.z == a.z+b*3
end
end

mutable struct Struct7
    x::Int64
    y::Cchar
end
struct Struct7I
    x::Int64
    y::Cchar
end

test_7_Struct7(a,b) = ccall((:test_7, libccalltest), Struct7, (Struct7, Int8), a, b)
test_7_Struct7I(a,b) = ccall((:test_7, libccalltest), Struct7I, (Struct7I, Int8), a, b)
let
for Struct in (Struct7,Struct7I)
    a = Struct(-384082741977533896, 'h')
    b = Int8(42)

    if Struct === Struct7
        mc = jit(test_7_Struct7, (typeof(a),typeof(b)))
        x = mc(a,b)
    else
        mc = jit(test_7_Struct7I, (typeof(a),typeof(b)))
        x = mc(a,b)
    end

    @test x.x == a.x+Int(b)*1
    @test x.y == a.y-Int(b)*2
end
end
