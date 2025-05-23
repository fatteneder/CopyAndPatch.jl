const libccalltest = joinpath(@__DIR__, "..", "stencils", "bin", "libccalltest.so")

#### These tests were crafted by me to figure things out

function mimic_test(x)
    a1 = Ref(x)
    # XXX: Without GC.@preserve the value of a15 from the LLVM backend depends on which @show is active below
    GC.@preserve a1 begin
        # @show a1
        a2 = @ccall jl_value_ptr(a1::Any)::Ptr{Cvoid}
        # @show a2
        a11 = Base.bitcast(Ptr{Int64}, a2)
        # @show a11
        a14 = @ccall libccalltest.test_echo_p(a11::Ptr{Int64})::Ptr{Int64}
        # @show a14
        a15 = Base.pointerref(a14, 1, 1)
        # @show a15
    end
    return a15
end
@testset "mimic ccall test" begin
    result = @cpjit(mimic_test, (132,))
    expected = mimic_test(132)
    @test result == expected
end

function f_ccall_array_int(v::Vector{Int32})
    n = length(v)
    return @ccall libccalltest.test_sum_vec_int(v::Ref{Cint}, n::Cint)::Cint
end
function f_ccall_array_double(v::Vector{Float64})
    n = length(v)
    return @ccall libccalltest.test_sum_vec_double(v::Ref{Cdouble}, n::Cint)::Cdouble
end
@testset "test ccall array argument" begin
    result = @cpjit(f_ccall_array_int, (Int32[1, 2, 3],))
    expected = f_ccall_array_int(Int32[1, 2, 3])
    @test result == expected
    result = @cpjit(f_ccall_array_double, (Float64[1, 2, 3],))
    expected = f_ccall_array_double(Float64[1, 2, 3])
    @test result == expected
end

#### The following tests were copied from julia/src/ccall.jl

const verbose = true
ccall((:set_verbose, libccalltest), Cvoid, (Int32,), verbose)

# Test for proper round-trip of Ref{T} type
function gen_ccall_echo(x, T, U, ret = nothing)
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
    return esc(
        quote
            @cpjit($func_name, ($x,))
        end
    )
    # :($func_name($(esc(x))))
end

macro ccall_echo_func(x, T, U)
    return gen_ccall_echo(x, T, U)
end
macro ccall_echo_load(x, T, U)
    return gen_ccall_echo(x, T, U, :unsafe_load)
end
macro ccall_echo_objref(x, T, U)
    return gen_ccall_echo(x, :(Ptr{$T}), U, :unsafe_pointer_to_objref)
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
@test @ccall_echo_load(Ref([144, 172], 2), Ptr{Int}, Ref{Int}) === 172
# that test is also ignored in julia
# # @test @ccall_echo_load(Ref([8],1,1), Ptr{Int}, Ref{Int}) === 8


# Tests for passing and returning structs

let a, ci_ary, x
    a = 20 + 51im

    ctest(a) = ccall((:ctest, libccalltest), Complex{Int}, (Complex{Int},), a)
    x = @cpjit(ctest, (a,))

    @test x == a + 1 - 2im

    ci_ary = [a] # Make sure the array is alive during unsafe_load
    cptest(ci_ary) = unsafe_load(
        ccall(
            (:cptest, libccalltest), Ptr{Complex{Int}},
            (Ptr{Complex{Int}},), ci_ary
        )
    )
    x = @cpjit(cptest, (ci_ary,))

    @test x == a + 1 - 2im
    @test a == 20 + 51im

    cptest_static(a) = ccall((:cptest_static, libccalltest), Ptr{Complex{Int}}, (Ref{Complex{Int}},), a)
    x = @cpjit(cptest_static, (a,))
    @test unsafe_load(x) == a
    @assert x !== C_NULL
    Libc.free(convert(Ptr{Cvoid}, x))
end

let a, b, x
    a = 2.84 + 5.2im

    cgtest(a) = ccall((:cgtest, libccalltest), ComplexF64, (ComplexF64,), a)
    x = @cpjit(cgtest, (a,))

    @test x == a + 1 - 2im

    b = [a] # Make sure the array is alive during unsafe_load
    cgptest(b) = unsafe_load(ccall((:cgptest, libccalltest), Ptr{ComplexF64}, (Ptr{ComplexF64},), b))
    x = @cpjit(cgptest, (b,))

    @test x == a + 1 - 2im
    @test a == 2.84 + 5.2im
end

let a, b, x
    a = 3.34f0 + 53.2f0im

    cftest(a) = ccall((:cftest, libccalltest), ComplexF32, (ComplexF32,), a)
    x = @cpjit(cftest, (a,))

    @test x == a + 1 - 2im

    b = [a] # Make sure the array is alive during unsafe_load
    cfptest(b) = unsafe_load(ccall((:cfptest, libccalltest), Ptr{ComplexF32}, (Ptr{ComplexF32},), b))
    x = @cpjit(cfptest, (b,))

    @test x == a + 1 - 2im
    @test a == 3.34f0 + 53.2f0im
end


## Tests for native Julia data types

let a
    a = 2.84 + 5.2im
    cptest(a) = ccall((:cptest, libccalltest), Ptr{Complex{Int}}, (Ptr{Complex{Int}},), a)
    @test_throws MethodError @cpjit(cptest, (a,))
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

test_1_Struct1(a2, b) = ccall((:test_1, libccalltest), Struct1, (Struct1, Float32), a2, b)
test_1_Struct1I(a2, b) = ccall((:test_1, libccalltest), Struct1I, (Struct1I, Float32), a2, b)
let
    for Struct in (Struct1, Struct1I)
        a = Struct(352.39422f23, 19.287577)
        b = Float32(123.456)

        a2 = copy(a)
        if Struct === Struct1
            x = @cpjit(test_1_Struct1, (a2, b))
        else
            x = @cpjit(test_1_Struct1I, (a2, b))
        end

        @test a2.x == a.x && a2.y == a.y
        @test !(a2 === x)

        @test x.x ≈ a.x + 1 * b
        @test x.y ≈ a.y - 2 * b
    end
end

let a, b, x
    a = Struct1(352.39422f23, 19.287577)
    b = Float32(123.456)
    a2 = copy(a)

    test_1long_a(a2, b) = ccall((:test_1long_a, libccalltest), Struct1, (Int, Int, Int, Struct1, Float32), 2, 3, 4, a2, b)
    x = @cpjit(test_1long_a, (a2, b))
    @test a2.x == a.x && a2.y == a.y
    @test !(a2 === x)
    @test x.x ≈ a.x + b + 9
    @test x.y ≈ a.y - 2 * b

    test_1long_b(a2, b) = ccall((:test_1long_b, libccalltest), Struct1, (Int, Float64, Int, Struct1, Float32), 2, 3, 4, a2, b)
    x = @cpjit(test_1long_b, (a2, b))
    @test a2.x == a.x && a2.y == a.y
    @test !(a2 === x)
    @test x.x ≈ a.x + b + 9
    @test x.y ≈ a.y - 2 * b

    test_1long_c(a2, b) = ccall((:test_1long_c, libccalltest), Struct1, (Int, Float64, Int, Int, Struct1, Float32), 2, 3, 4, 5, a2, b)
    x = @cpjit(test_1long_c, (a2, b))
    @test a2.x == a.x && a2.y == a.y
    @test !(a2 === x)
    @test x.x ≈ a.x + b + 14
    @test x.y ≈ a.y - 2 * b
end

let a, b, x, y
    a = Complex{Int32}(Int32(10), Int32(31))
    b = Int32(42)

    test_2a(a, b) = ccall((:test_2a, libccalltest), Complex{Int32}, (Complex{Int32}, Int32), a, b)
    test_2b(a, b) = ccall((:test_2b, libccalltest), Complex{Int32}, (Complex{Int32}, Int32), a, b)
    x = @cpjit(test_2a, (a, b))
    y = @cpjit(test_2b, (a, b))

    @test a == Complex{Int32}(Int32(10), Int32(31))

    @test x == y
    @test x == a + b * 1 - b * 2im
end

let a, b, x, y, z
    a = Complex{Int64}(Int64(20), Int64(51))
    b = Int64(42)

    test_3a(a, b) = ccall((:test_3a, libccalltest), Complex{Int64}, (Complex{Int64}, Int64), a, b)
    test_3b(a, b) = ccall((:test_3b, libccalltest), Complex{Int64}, (Complex{Int64}, Int64), a, b)
    test_128(a, b) = ccall((:test_128, libccalltest), Complex{Int64}, (Complex{Int64}, Int64), a, b)
    x = @cpjit(test_3a, (a, b))
    y = @cpjit(test_3b, (a, b))
    z = @cpjit(test_128, (a, b))

    @test a == Complex{Int64}(Int64(20), Int64(51))

    @test x == y
    @test x == a + b * 1 - b * 2im

    @test z == a + 1 * b
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

test_4_Struct4(a, b) = ccall((:test_4, libccalltest), Struct4, (Struct4, Int32), a, b)
test_4_Struct4I(a, b) = ccall((:test_4, libccalltest), Struct4I, (Struct4I, Int32), a, b)
let
    for Struct in (Struct4, Struct4I)
        a = Struct(-512275808, 882558299, -2133022131)
        b = Int32(42)

        if Struct === Struct4
            x = @cpjit(test_4_Struct4, (a, b))
        else
            x = @cpjit(test_4_Struct4I, (a, b))
        end

        @test x.x == a.x + b * 1
        @test x.y == a.y - b * 2
        @test x.z == a.z + b * 3
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

test_5_Struct5(a, b) = ccall((:test_5, libccalltest), Struct5, (Struct5, Int32), a, b)
test_5_Struct5I(a, b) = ccall((:test_5, libccalltest), Struct5I, (Struct5I, Int32), a, b)
let
    for Struct in (Struct5, Struct5I)
        a = Struct(1771319039, 406394736, -1269509787, -745020976)
        b = Int32(42)

        if Struct === Struct5
            x = @cpjit(test_5_Struct5, (a, b))
        else
            x = @cpjit(test_5_Struct5I, (a, b))
        end

        @test x.x == a.x + b * 1
        @test x.y == a.y - b * 2
        @test x.z == a.z + b * 3
        @test x.a == a.a - b * 4
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

test_6_Struct6(a, b) = ccall((:test_6, libccalltest), Struct6, (Struct6, Int64), a, b)
test_6_Struct6I(a, b) = ccall((:test_6, libccalltest), Struct6I, (Struct6I, Int64), a, b)
let
    for Struct in (Struct6, Struct6I)
        a = Struct(-654017936452753226, -5573248801240918230, -983717165097205098)
        b = Int64(42)

        if Struct === Struct6
            x = @cpjit(test_6_Struct6, (a, b))
        else
            x = @cpjit(test_6_Struct6I, (a, b))
        end

        @test x.x == a.x + b * 1
        @test x.y == a.y - b * 2
        @test x.z == a.z + b * 3
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

test_7_Struct7(a, b) = ccall((:test_7, libccalltest), Struct7, (Struct7, Int8), a, b)
test_7_Struct7I(a, b) = ccall((:test_7, libccalltest), Struct7I, (Struct7I, Int8), a, b)
let
    for Struct in (Struct7, Struct7I)
        a = Struct(-384082741977533896, 'h')
        b = Int8(42)

        if Struct === Struct7
            x = @cpjit(test_7_Struct7, (a, b))
        else
            x = @cpjit(test_7_Struct7I, (a, b))
        end

        @test x.x == a.x + Int(b) * 1
        @test x.y == a.y - Int(b) * 2
    end
end

mutable struct Struct8
    x::Int32
    y::Cchar
end
struct Struct8I
    x::Int32
    y::Cchar
end

test_8_Struct8(a, b) = ccall((:test_8, libccalltest), Struct8, (Struct8, Int8), a, b)
test_8_Struct8I(a, b) = ccall((:test_8, libccalltest), Struct8I, (Struct8I, Int8), a, b)
let
    for Struct in (Struct8, Struct8I)
        a = Struct(-384082896, 'h')
        b = Int8(42)

        if Struct === Struct8
            r8 = @cpjit(test_8_Struct8, (a, b))
        else
            r8 = @cpjit(test_8_Struct8I, (a, b))
        end

        @test r8.x == a.x + b * 1
        @test r8.y == a.y - b * 2
    end
end

mutable struct Struct9
    x::Int32
    y::Int16
end
struct Struct9I
    x::Int32
    y::Int16
end

test_9_Struct9(a, b) = ccall((:test_9, libccalltest), Struct9, (Struct9, Int16), a, b)
test_9_Struct9I(a, b) = ccall((:test_9, libccalltest), Struct9I, (Struct9I, Int16), a, b)
let
    for Struct in (Struct9, Struct9I)
        a = Struct(-394092996, -3840)
        b = Int16(42)

        if Struct === Struct9
            x = @cpjit(test_9_Struct9, (a, b))
        else
            x = @cpjit(test_9_Struct9I, (a, b))
        end

        @test x.x == a.x + b * 1
        @test x.y == a.y - b * 2
    end
end

mutable struct Struct10
    x::Cchar
    y::Cchar
    z::Cchar
    a::Cchar
end
struct Struct10I
    x::Cchar
    y::Cchar
    z::Cchar
    a::Cchar
end

test_10_Struct10(a, b) = ccall((:test_10, libccalltest), Struct10, (Struct10, Int8), a, b)
test_10_Struct10I(a, b) = ccall((:test_10, libccalltest), Struct10I, (Struct10I, Int8), a, b)
let
    for Struct in (Struct10, Struct10I)
        a = Struct('0', '1', '2', '3')
        b = Int8(2)

        if Struct === Struct10
            x = @cpjit(test_10_Struct10, (a, b))
        else
            x = @cpjit(test_10_Struct10I, (a, b))
        end

        @test x.x == a.x + b * 1
        @test x.y == a.y - b * 2
        @test x.z == a.z + b * 3
        @test x.a == a.a - b * 4
    end
end

mutable struct Struct11
    x::ComplexF32
end
struct Struct11I
    x::ComplexF32
end

test_11_Struct11(a, b) = ccall((:test_11, libccalltest), Struct11, (Struct11, Float32), a, b)
test_11_Struct11I(a, b) = ccall((:test_11, libccalltest), Struct11I, (Struct11I, Float32), a, b)
let
    for Struct in (Struct11, Struct11I)
        a = Struct(0.8877077f0 + 0.4591081f0im)
        b = Float32(42)

        if Struct === Struct11
            x = @cpjit(test_11_Struct11, (a, b))
        else
            x = @cpjit(test_11_Struct11I, (a, b))
        end

        @test x.x ≈ a.x + b * 1 - b * 2im
    end
end

mutable struct Struct12
    x::ComplexF32
    y::ComplexF32
end
struct Struct12I
    x::ComplexF32
    y::ComplexF32
end

test_12_Struct12(a, b) = ccall((:test_12, libccalltest), Struct12, (Struct12, Float32), a, b)
test_12_Struct12I(a, b) = ccall((:test_12, libccalltest), Struct12I, (Struct12I, Float32), a, b)
let
    for Struct in (Struct12, Struct12I)
        a = Struct(0.8877077f5 + 0.4591081f2im, 0.0004842868f0 - 6982.3265f3im)
        b = Float32(42)

        if Struct === Struct12
            x = @cpjit(test_12_Struct12, (a, b))
        else
            x = @cpjit(test_12_Struct12I, (a, b))
        end

        @test x.x ≈ a.x + b * 1 - b * 2im
        @test x.y ≈ a.y + b * 3 - b * 4im
    end
end

mutable struct Struct13
    x::ComplexF64
end
struct Struct13I
    x::ComplexF64
end

test_13_Struct13(a, b) = ccall((:test_13, libccalltest), Struct13, (Struct13, Float64), a, b)
test_13_Struct13I(a, b) = ccall((:test_13, libccalltest), Struct13I, (Struct13I, Float64), a, b)
let
    for Struct in (Struct13, Struct13I)
        a = Struct(42968.97560380495 - 803.0576845153616im)
        b = Float64(42)

        if Struct === Struct13
            x = @cpjit(test_13_Struct13, (a, b))
        else
            x = @cpjit(test_13_Struct13I, (a, b))
        end

        @test x.x ≈ a.x + b * 1 - b * 2im
    end
end

mutable struct Struct14
    x::Float32
    y::Float32
end
struct Struct14I
    x::Float32
    y::Float32
end

test_14_Struct14(a, b) = ccall((:test_14, libccalltest), Struct14, (Struct14, Float32), a, b)
test_14_Struct14I(a, b) = ccall((:test_14, libccalltest), Struct14I, (Struct14I, Float32), a, b)
let
    for Struct in (Struct14, Struct14I)
        a = Struct(0.024138331f0, 0.89759064f32)
        b = Float32(42)

        if Struct === Struct14
            x = @cpjit(test_14_Struct14, (a, b))
        else
            x = @cpjit(test_14_Struct14I, (a, b))
        end

        @test x.x ≈ a.x + b * 1
        @test x.y ≈ a.y - b * 2
    end
end

mutable struct Struct15
    x::Float64
    y::Float64
end
struct Struct15I
    x::Float64
    y::Float64
end

test_15_Struct15(a, b) = ccall((:test_15, libccalltest), Struct15, (Struct15, Float64), a, b)
test_15_Struct15I(a, b) = ccall((:test_15, libccalltest), Struct15I, (Struct15I, Float64), a, b)
let
    for Struct in (Struct15, Struct15I)
        a = Struct(4.180997967273657, -0.404218594294923)
        b = Float64(42)

        if Struct === Struct15
            x = @cpjit(test_15_Struct15, (a, b))
        else
            x = @cpjit(test_15_Struct15I, (a, b))
        end

        @test x.x ≈ a.x + b * 1
        @test x.y ≈ a.y - b * 2
    end
end

mutable struct Struct16
    x::Float32
    y::Float32
    z::Float32
    a::Float64
    b::Float64
    c::Float64
end
struct Struct16I
    x::Float32
    y::Float32
    z::Float32
    a::Float64
    b::Float64
    c::Float64
end

test_16_Struct16(a, b) = ccall((:test_16, libccalltest), Struct16, (Struct16, Float32), a, b)
test_16_Struct16I_quoteplz(a) = eval(:(ccall((:test_16, libccalltest), Struct16I, (Struct16I, Float32), $(QuoteNode(a)), Float32(42))))
test_16_Struct16I(a, b) = ccall((:test_16, libccalltest), Struct16I, (Struct16I, Float32), a, b)
let
    for (Struct, quoteplz) in [
            (Struct16, false),
            (Struct16I, true),
            (Struct16I, false),
        ]

        a = Struct(
            0.1604656f0, 0.6297606f0, 0.83588994f0,
            0.6460273620993535, 0.9472692581106656, 0.47328535437352093
        )
        b = Float32(42)

        if Struct === Struct16
            x = @cpjit(test_16_Struct16, (a, b))
        else
            if quoteplz
                x = @cpjit(test_16_Struct16I_quoteplz, (a,))
            else
                x = @cpjit(test_16_Struct16I, (a, b))
            end
        end

        @test x.x ≈ a.x + b * 1
        @test x.y ≈ a.y - b * 2
        @test x.z ≈ a.z + b * 3
        @test x.a ≈ a.a - b * 4
        @test x.b ≈ a.b + b * 5
        @test x.c ≈ a.c - b * 6
    end
end

mutable struct Struct17
    a::Int8
    b::Int16
end
struct Struct17I
    a::Int8
    b::Int16
end

test_17_Struct17(a, b) = ccall((:test_17, libccalltest), Struct17, (Struct17, Int8), a, b)
test_17_Struct17I(a, b) = ccall((:test_17, libccalltest), Struct17I, (Struct17I, Int8), a, b)
let
    for Struct in (Struct17, Struct17I)
        a = Struct(2, 10)
        b = Int8(2)

        if Struct === Struct17
            x = @cpjit(test_17_Struct17, (a, b))
        else
            x = @cpjit(test_17_Struct17I, (a, b))
        end

        @test x.a == a.a + b * 1
        @test x.b == a.b - b * 2
    end
end

mutable struct Struct18
    a::Int8
    b::Int8
    c::Int8
end
struct Struct18I
    a::Int8
    b::Int8
    c::Int8
end

test_18_Struct18(a, b) = ccall((:test_18, libccalltest), Struct18, (Struct18, Int8), a, b)
test_18_Struct18I(a, b) = ccall((:test_18, libccalltest), Struct18I, (Struct18I, Int8), a, b)
let
    for Struct in (Struct18, Struct18I)
        a = Struct(2, 10, -3)
        b = Int8(2)

        if Struct === Struct18
            x = @cpjit(test_18_Struct18, (a, b))
        else
            x = @cpjit(test_18_Struct18I, (a, b))
        end

        @test x.a == a.a + b * 1
        @test x.b == a.b - b * 2
        @test x.c == a.c + b * 3
    end
end

let a, b, x
    a = Int128(0x7f00123456789abc) << 64 + typemax(UInt64)
    b = Int64(1)

    test_128(a, b) = ccall((:test_128, libccalltest), Int128, (Int128, Int64), a, b)
    x = @cpjit(test_128, (a, b))

    @test x == a + b * 1
    @test a == Int128(0x7f00123456789abc) << 64 + typemax(UInt64)
end

mutable struct Struct_Big
    x::Int
    y::Int
    z::Int8
end
struct Struct_BigI
    x::Int
    y::Int
    z::Int8
end
copy(a::Struct_Big) = Struct_Big(a.x, a.y, a.z)
copy(a::Struct_BigI) = a

test_big_Struct_Big(a2) = ccall((:test_big, libccalltest), Struct_Big, (Struct_Big,), a2)
test_big_Struct_BigI(a2) = ccall((:test_big, libccalltest), Struct_BigI, (Struct_BigI,), a2)
let
    for Struct in (Struct_Big, Struct_BigI)
        a = Struct(424, -5, Int8('Z'))
        a2 = copy(a)

        if Struct == Struct_Big
            x = @cpjit(test_big_Struct_Big, (a2,))
        else
            x = @cpjit(test_big_Struct_BigI, (a2,))
        end

        @test a2.x == a.x && a2.y == a.y && a2.z == a.z
        @test x.x == a.x + 1
        @test x.y == a.y - 2
        @test x.z == a.z - Int('A')
    end
end

let a, a2, x
    a = Struct_Big(424, -5, Int8('Z'))
    a2 = copy(a)
    test_big_long(a2) = ccall((:test_big_long, libccalltest), Struct_Big, (Int, Int, Int, Struct_Big), 2, 3, 4, a2)
    x = @cpjit(test_big_long, (a2,))
    @test a2.x == a.x && a2.y == a.y && a2.z == a.z
    @test x.x == a.x + 10
    @test x.y == a.y - 2
    @test x.z == a.z - Int('A')
end

const Struct_huge1a = NTuple{8, Int64}
const Struct_huge1b = NTuple{9, Int64}
const Struct_huge2a = NTuple{8, Cdouble}
const Struct_huge2b = NTuple{9, Cdouble}
mutable struct Struct_huge3a
    cf::NTuple{3, Complex{Cfloat}}
    f7::Cfloat
    f8::Cfloat
end
mutable struct Struct_huge3b
    cf::NTuple{7, Complex{Cfloat}}
    r8a::Cfloat
    r8b::Cfloat
end
mutable struct Struct_huge3c
    cf::NTuple{7, Complex{Cfloat}}
    r8a::Cfloat
    r8b::Cfloat
    r9::Cfloat
end
mutable struct Struct_huge4a
    r12::Complex{Cdouble}
    r34::Complex{Cdouble}
    r5::Complex{Cfloat}
    r67::Complex{Cdouble}
    r8::Cdouble
end
mutable struct Struct_huge4b
    r12::Complex{Cdouble}
    r34::Complex{Cdouble}
    r5::Complex{Cfloat}
    r67::Complex{Cdouble}
    r89::Complex{Cdouble}
end
const Struct_huge5a = NTuple{8, Complex{Cint}}
const Struct_huge5b = NTuple{9, Complex{Cint}}

function verify_huge(init, a, b)
    @test typeof(init) === typeof(a) === typeof(b)
    verbose && @show (a, b)
    # make sure a was unmodified
    for i in 1:nfields(a)
        @test getfield(init, i) === getfield(a, i)
    end
    # make sure b was modified as expected
    a1, b1 = getfield(a, 1), getfield(b, 1)
    while isa(a1, Tuple)
        @test a1[2:end] === b1[2:end]
        a1 = a1[1]
        b1 = b1[1]
    end
    if isa(a1, VecElement)
        a1 = a1.value
        b1 = b1.value
    end
    @test oftype(a1, a1 * 39) === b1
    for i in 2:nfields(a)
        @test getfield(a, i) === getfield(b, i)
    end
    return
end
macro test_huge(i, b, init)
    f = QuoteNode(Symbol("test_huge", i, b))
    ty = Symbol("Struct_huge", i, b)
    return quote
        let a = $ty($(esc(init))...), f
            f(b) = ccall(($f, libccalltest), $ty, (Cchar, $ty, Cchar), '0' + $i, a, $b[1])
            verify_huge($ty($(esc(init))...), a, @cpjit(f, (a,)))
        end
    end
end
@test_huge 1 'a' ((1, 2, 3, 4, 5, 6, 7, 8),)
@test_huge 1 'b' ((1, 2, 3, 4, 5, 6, 7, 8, 9),)
@test_huge 2 'a' ((1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0),)
@test_huge 2 'b' ((1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0),)
@test_huge 3 'a' ((1.0 + 2.0im, 3.0 + 4.0im, 5.0 + 6.0im), 7.0, 8.0)
@test_huge 3 'b' ((1.0 + 2.0im, 3.0 + 4.0im, 5.0 + 6.0im, 7.0 + 8.0im, 9.0 + 10.0im, 11.0 + 12.0im, 13.0 + 14.0im), 7.0, 8.0)
@test_huge 3 'c' ((1.0 + 2.0im, 3.0 + 4.0im, 5.0 + 6.0im, 7.0 + 8.0im, 9.0 + 10.0im, 11.0 + 12.0im, 13.0 + 14.0im), 7.0, 8.0, 9.0)
@test_huge 4 'a' (1.0 + 2.0im, 3.0 + 4.0im, 5.0f0 + 6.0f0im, 7.0 + 8.0im, 9.0)
@test_huge 4 'b' (1.0 + 2.0im, 3.0 + 4.0im, 5.0f0 + 6.0f0im, 7.0 + 8.0im, 9.0 + 10.0im)
@test_huge 5 'a' ((1 + 2im, 3 + 4im, 5 + 6im, 7 + 8im, 9 + 10im, 11 + 12im, 13 + 14im, 15 + 16im),)
@test_huge 5 'b' ((1 + 2im, 3 + 4im, 5 + 6im, 7 + 8im, 9 + 10im, 11 + 12im, 13 + 14im, 15 + 16im, 17 + 17im),)

## cfunction roundtrip

verbose && Libc.flush_cstdio()

# TODO Skipping cfunction_closure tests for now, because I don't understand them

# issue 13031
# a simplified version to develop loading the foreign function from the SSA array,
# e.g. avoids the Ref{Tuple{}} argtype appearing below
foo13031(x) = Cint(1)
simple_foo13031p = @cfunction(foo13031, Cint, (Cint,))
simple_test_foo13031p(x) = ccall(simple_foo13031p, Cint, (Cint,), x)
let
    @test @cpjit(simple_test_foo13031p, (Cint(1),)) == Cint(1)
end

# issue 13031
foo13031(x) = Cint(1)
foo13031p = @cfunction(foo13031, Cint, (Ref{Tuple{}},))
test_foo13031p() = ccall(foo13031p, Cint, (Ref{Tuple{}},), ())
let
    @test @cpjit(test_foo13031p, ()) == Cint(1)
end

foo13031(x, y, z) = z
foo13031p = @cfunction(foo13031, Cint, (Ref{Tuple{}}, Ref{Tuple{}}, Cint))
test_foo13031p(x) = ccall(foo13031p, Cint, (Ref{Tuple{}}, Ref{Tuple{}}, Cint), (), (), x)
let
    @test @cpjit(test_foo13031p, (Cint(8),)) == Cint(8)
end

# issue 26078

unstable26078(x) = x > 0 ? x : "foo"
handle26078 = @cfunction(unstable26078, Int32, (Int32,))
test_handle26078(x) = ccall(handle26078, Int32, (Int32,), x)
let
    @test @cpjit(test_handle26078, (Int32(1),)) == 1
end

# issue #39804
let f = @cfunction(Base.last, String, (Tuple{Int, String},))
    # String inside a struct is a pointer even though String.size == 0
    test(tpl) = ccall(f, Ref{String}, (Tuple{Int, String},), tpl)
    @test @cpjit(test, ((1, "a string?"),), (Tuple{Int, String},)) === "a string?"
end

test_isa(x::Any) = isa(x, Ptr{Cvoid})
let
    @test @cpjit(test_isa, (C_NULL,), (Any,)) == true
    @test @cpjit(test_isa, (nothing,), (Any,)) == false
end

# issue 17219
function ccall_reassigned_ptr(ptr::Ptr{Cvoid})
    ptr = Libdl.dlsym(Libdl.dlopen(libccalltest), "test_echo_p")
    return ccall(ptr, Any, (Any,), "foo")
end
let
    @test @cpjit(ccall_reassigned_ptr, (C_NULL,), (Ptr{Cvoid},)) == "foo"
end

# TODO Skipping @threadcall tests for now, because they contain :cfunction Expr
# which do not appear here: https://docs.julialang.org/en/v1/devdocs/ast/#Lowered-form
#
# # @threadcall functionality
# threadcall_test_func(x) =
#     @threadcall((:testUcharX, libccalltest), Int32, (UInt8,), x % UInt8)
#
# let
#     @test @cpjit(threadcall_test_func, (3,)) == 1
#     @test @cpjit(threadcall_test_func, (259,)) == 1
# end
#
# # issue 17819
# # NOTE: can't use cfunction or reuse ccalltest Struct methods, as those call into the runtime
# @test @threadcall((:threadcall_args, libccalltest), Cint, (Cint, Cint), 1, 2) == 3
#
# let n=3
#     tids = Culong[]
#     @sync for i in 1:10^n
#         @async push!(tids, @threadcall(:uv_thread_self, Culong, ()))
#     end
#
#     # The work should not be done on the master thread
#     t0 = ccall(:uv_thread_self, Culong, ())
#     @test length(tids) == 10^n
#     for t in tids
#         @test t != t0
#     end
# end
#
# @test ccall(:jl_getpagesize, Clong, ()) == @threadcall(:jl_getpagesize, Clong, ())
#
# # make sure our malloc/realloc/free adapters are thread-safe and repeatable
# for i = 1:8
#     ptr = @threadcall(:jl_malloc, Ptr{Cint}, (Csize_t,), sizeof(Cint))
#     @test ptr != C_NULL
#     unsafe_store!(ptr, 3)
#     @test unsafe_load(ptr) == 3
#     ptr = @threadcall(:jl_realloc, Ptr{Cint}, (Ptr{Cint}, Csize_t,), ptr, 2 * sizeof(Cint))
#     @test ptr != C_NULL
#     unsafe_store!(ptr, 4, 2)
#     @test unsafe_load(ptr, 1) == 3
#     @test unsafe_load(ptr, 2) == 4
#     @threadcall(:jl_free, Cvoid, (Ptr{Cint},), ptr)
# end

# Pointer finalizer (issue #15408)
let A = [1]
    ccall((:set_c_int, libccalltest), Cvoid, (Cint,), 1)
    test_get_c_int() = ccall((:get_c_int, libccalltest), Cint, ())
    @test @cpjit(test_get_c_int, ()) == 1
    finalizer(cglobal((:finalizer_cptr, libccalltest), Cvoid), A)
    finalize(A)
    @test @cpjit(test_get_c_int, ()) == -1
end

# TODO How to test that?
# # Pointer finalizer at exit (PR #19911)
# let result = read(`$(Base.julia_cmd()) --startup-file=no -e "A = Ref{Cint}(42); finalizer(cglobal((:c_exit_finalizer, \"$libccalltest\"), Cvoid), A)"`, String)
#     @test result == "c_exit_finalizer: 42, 0"
# end

# SIMD Registers
# TODO Skipping all SIMD tests, not sure if that is currently possible with libffi.
# Althouhg in https://github.com/libffi/libffi/issues/408 they say they can use some SIMD on x86.

# TODO Depends on :cfunction which is yet unsupported
# # Special calling convention for `Array`
# function f17204(a)
#     b = similar(a)
#     for i in eachindex(a)
#         b[i] = a[i] + 10
#     end
#     return b
# end
# test_f17204() = ccall(@cfunction(f17204, Vector{Any}, (Vector{Any},)), Vector{Any}, (Vector{Any},), Any[1:10;])
# let
#     @test @cpjit(test_f17204, ()) == Any[11:20;]
# end

# This used to trigger incorrect ccall callee inlining.
# Not sure if there's a more reliable way to test this.
# Do not put these in a function.
@noinline g17413() = rand()
@inline f17413() = (g17413(); g17413())
test_f17413() = ccall((:test_echo_p, libccalltest), Ptr{Cvoid}, (Any,), f17413())
let
    @cpjit(test_f17413, ())
    for i in 1:3
        @cpjit(test_f17413, ())
    end
end

let r = Ref{Any}(10)
    @GC.preserve r begin
        pa = Base.unsafe_convert(Ptr{Any}, r) # pointer to value
        pv = Base.unsafe_convert(Ptr{Cvoid}, r) # pointer to data
        f1(pa) = Ptr{Cvoid}(pa)
        @test @cpjit(f1, (pa,)) != pv
        f2(pa) = unsafe_load(pa)
        @test @cpjit(f2, (pa,)) === 10
        f3(pa) = unsafe_load(Ptr{Ptr{Cvoid}}(pa))
        @test @cpjit(f3, (pa,)) === pv
        f4(pv) = unsafe_load(Ptr{Int}(pv))
        @test @cpjit(f4, (pv,)) === 10
    end
end

let r = Ref{Any}("123456789")
    @GC.preserve r begin
        pa = Base.unsafe_convert(Ptr{Any}, r) # pointer to value
        pv = Base.unsafe_convert(Ptr{Cvoid}, r) # pointer to data
        f1(pa) = Ptr{Cvoid}(pa)
        @test @cpjit(f1, (pa,)) != pv
        f2(pa) = unsafe_load(pa)
        @test @cpjit(f2, (pa,)) === r[]
        f3(pa) = unsafe_load(Ptr{Ptr{Cvoid}}(pa))
        @test @cpjit(f3, (pa,)) === pv
        f4(pv) = unsafe_load(Ptr{Int}(pv))
        @test @cpjit(f4, (pv,)) === length(r[])
    end
end


struct SpillPint
    a::Ptr{Cint}
    b::Ptr{Cint}
end
Base.cconvert(::Type{SpillPint}, v::NTuple{2, Cint}) =
    Base.cconvert(Ref{NTuple{2, Cint}}, v)
function Base.unsafe_convert(::Type{SpillPint}, vr)
    ptr = Base.unsafe_convert(Ref{NTuple{2, Cint}}, vr)
    return SpillPint(ptr, ptr + 4)
end

macro test_spill_n(n::Int, intargs, floatargs)
    fname_int = Symbol(:test_spill_int, n)
    fname_float = Symbol(:test_spill_float, n)
    args = [ gensym(Symbol("a$i")) for i in 1:(n + 1) ]
    unpack_args_int = vcat(
        [ :($a = ints[$i]) for (i, a) in enumerate(args[1:(end - 1)]) ],
        [:($(args[end]) = (ints[$n + 1], ints[$n + 2]))]
    )
    unpack_args_float = vcat(
        [ :($a = floats[$i]) for (i, a) in enumerate(args[1:(end - 1)]) ],
        [:($(args[end]) = (floats[$n + 1], floats[$n + 2]))]
    )
    quote
        local ints = $(esc(intargs))
        local floats = $(esc(intargs))
        f1($(args...)) = ccall(
            ($(QuoteNode(fname_int)), libccalltest), Cint,
            ($((:(Ref{Cint}) for j in 1:n)...), SpillPint),
            $(args...)
        )
        $(unpack_args_int...)
        tpl_argtypes = typeof.(tuple($(unpack_args_int...)))
        tpl_args = tuple($(args...))
        res = @cpjit(f1, tpl_args, tpl_argtypes)
        @test res == sum(ints[1:($n + 2)])

        f2($(args...)) = ccall(
            ($(QuoteNode(fname_float)), libccalltest), Float32,
            ($((:Float32 for j in 1:n)...), NTuple{2, Float32}),
            $(args...)
        )
        $(unpack_args_float...)
        tpl_argtypes = typeof.(tuple($(unpack_args_float...)))
        tpl_args = tuple($(args...))
        res = @cpjit(f1, tpl_args, tpl_argtypes)
        @test res == sum(floats[1:($n + 2)])

    end
end

# We shortened the loop length for faster tests.
let
    # for i in 1:100
    for i in 1:10
        local intargs = rand(1:10000, 14)
        local int32args = Int32.(intargs)
        local intsum = sum(intargs)
        local floatargs = rand(14)
        local float32args = Float32.(floatargs)
        local float32sum = sum(float32args)
        local float64sum = sum(floatargs)
        test_long_args_intp(intargs) = ccall(
            (:test_long_args_intp, libccalltest), Cint,
            (
                Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Cint},
                Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Cint},
                Ref{Cint}, Ref{Cint}, Ref{Cint}, Ref{Cint},
                Ref{Cint}, Ref{Cint},
            ),
            intargs[1], intargs[2], intargs[3], intargs[4],
            intargs[5], intargs[6], intargs[7], intargs[8],
            intargs[9], intargs[10], intargs[11], intargs[12],
            intargs[13], intargs[14]
        )
        @test @cpjit(test_long_args_intp, (intargs,)) == intsum
        test_long_args_int(intargs) = ccall(
            (:test_long_args_int, libccalltest), Cint,
            (
                Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint,
                Cint, Cint, Cint, Cint, Cint, Cint,
            ),
            intargs[1], intargs[2], intargs[3], intargs[4],
            intargs[5], intargs[6], intargs[7], intargs[8],
            intargs[9], intargs[10], intargs[11], intargs[12],
            intargs[13], intargs[14]
        )
        @test @cpjit(test_long_args_int, (intargs,)) == intsum
        test_long_args_float(floatargs) = ccall(
            (:test_long_args_float, libccalltest), Float32,
            (
                Float32, Float32, Float32, Float32, Float32, Float32,
                Float32, Float32, Float32, Float32, Float32, Float32,
                Float32, Float32,
            ),
            floatargs[1], floatargs[2], floatargs[3], floatargs[4],
            floatargs[5], floatargs[6], floatargs[7], floatargs[8],
            floatargs[9], floatargs[10], floatargs[11], floatargs[12],
            floatargs[13], floatargs[14]
        )
        @test @cpjit(test_long_args_float, (floatargs,)) == float32sum
        test_long_args_double(floatargs) = ccall(
            (:test_long_args_double, libccalltest), Float64,
            (
                Float64, Float64, Float64, Float64, Float64, Float64,
                Float64, Float64, Float64, Float64, Float64, Float64,
                Float64, Float64,
            ),
            floatargs[1], floatargs[2], floatargs[3], floatargs[4],
            floatargs[5], floatargs[6], floatargs[7], floatargs[8],
            floatargs[9], floatargs[10], floatargs[11], floatargs[12],
            floatargs[13], floatargs[14]
        )
        @test @cpjit(test_long_args_double, (floatargs,)) ≈ float64sum

        @test_spill_n 1 int32args float32args
        @test_spill_n 2 int32args float32args
        @test_spill_n 3 int32args float32args
        @test_spill_n 4 int32args float32args
        @test_spill_n 5 int32args float32args
        @test_spill_n 6 int32args float32args
        @test_spill_n 7 int32args float32args
        @test_spill_n 8 int32args float32args
        @test_spill_n 9 int32args float32args
        @test_spill_n 10 int32args float32args
    end
end

# Skipping various @test_throws tests, because they examine lowering and not codegen.

# test Ref{abstract_type} calling parameter passes a heap box
abstract type Abstract22734 end
struct Bits22734 <: Abstract22734
    x::Int
    y::Float64
end
function cb22734(ptr::Ptr{Cvoid})
    GC.gc()
    obj = unsafe_pointer_to_objref(ptr)::Bits22734
    return obj.x + obj.y
end
ptr22734 = @cfunction(cb22734, Float64, (Ptr{Cvoid},))
function caller22734(ptr)
    obj = Bits22734(12, 20)
    return ccall(ptr, Float64, (Ref{Abstract22734},), obj)
end
let
    @test @cpjit(caller22734, (ptr22734,)) === 32.0
end

# # TODO See stencils/mwe_union.c
# # to take isbitstype into account. However, they do not reliably pass, but also segfault randomly.
# # issue #46786 -- non-isbitstypes passed "by-value"
# struct NonBits46786
#     x::Union{Int16,NTuple{3,UInt8}}
# end
# let ptr = @cfunction(identity, NonBits46786, (NonBits46786,))
#     obj1 = NonBits46786((0x01,0x02,0x03))
#     test_obj2(obj1) = ccall(ptr, NonBits46786, (NonBits46786,), obj1)
#     obj = @cpjit(test_obj2, (obj1,))
#     @test obj1 === obj2
# end
# let ptr = @cfunction(identity, Base.RefValue{NonBits46786}, (Base.RefValue{NonBits46786},))
#     obj1 = Base.RefValue(NonBits46786((0x01,0x02,0x03)))
#     test_obj2(obj1) = ccall(ptr, Base.RefValue{NonBits46786}, (Base.RefValue{NonBits46786},), obj1)
#     obj2 = @cpjit(test_obj2, (obj1,))
#     # @test obj1 !== obj2
#     # @test obj1.x === obj2.x
# end

# # TODO There seems to be a problem between what code_typed outputs and what jl_cglobal consumes.
# # I.e. the former provides us with an Expr like :(Core.tuple(:global_var, Main.libccalltest)),
# # but the latter expects a Symbol.
# # Maybe this works when running with unoptimized typed output? No, it doesn't.
# # 26297#issuecomment-371165725
# #   test that the first argument to cglobal is recognized as a tuple literal even through
# #   macro expansion
# # This should be resolved by transform_ir_for_cpjit once we adapt our interpreter for
# # the jit pipeline.
#
# macro cglobal26297(sym)
#     :(cglobal(($(esc(sym)), libccalltest), Cint))
# end
# let
#     cglobal26297() = @cglobal26297(:global_var)
#     @test @cpjit(cglobal26297, ()) != C_NULL
# end

# issue #27477
@eval module Pkg27477
const libccalltest = $libccalltest
end

module Test27477
    using ..Pkg27477
    test27477() = ccall((:ctest, Pkg27477.libccalltest), Complex{Int}, (Complex{Int},), 1 + 2im)
end

let
    @test @cpjit(Test27477.test27477, ()) == 2 + 0im
end

# issue #31073
let
    function f31073()
        a = ['0']
        arr = Vector{Char}(undef, 2)
        ptr = pointer(arr)
        elsz = sizeof(Char)
        na = length(a)
        nba = na * elsz
        ptr = eval(:(ccall(:memcpy, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}, UInt), $(arr), $(a), $(nba))))
        ptr, arr
    end
    ptr, arr = @cpjit(f31073, ())
    @test isa(ptr, Ptr{Cvoid})
    @test arr[1] == '0'
end

# issue #38751
let
    function f38751!(dest::Vector{UInt8}, src::Vector{UInt8}, n::UInt)
        d, s = pointer(dest), pointer(src)
        GC.@preserve dest src ccall(:memcpy, Cvoid, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), d, s, n)
        return dest
    end
    dest = zeros(UInt8, 8)
    @test @cpjit(f38751!,
                 (dest, collect(0x01:0x08), UInt(8)),
                 (Vector{UInt8}, Vector{UInt8}, UInt)) == 0x01:0x08
    llvm = sprint(InteractiveUtils.code_llvm, f38751!, (Vector{UInt8}, Vector{UInt8}, UInt))
    @test !occursin("call void inttoptr", llvm)
end

# TODO Relevant for us?
# # issue #34061
# let o_file = tempname(), err = Base.PipeEndpoint()
#     run(pipeline(Cmd(`$(Base.julia_cmd()) --color=no --output-o=$o_file -e '
#         Base.reinit_stdio();
#         f() = ccall((:dne, :does_not_exist), Cvoid, ());
#         f()'`; ignorestatus=true), stderr=err), wait=false)
#     output = read(err, String)
#     @test occursin("""ERROR: could not load library "does_not_exist"
#     """, output)
#     @test !isfile(o_file)
# end

# pass NTuple{N,T} as Ptr{T}/Ref{T}
let
    dest = Ref((0, 0, 0))

    src = Ref((1, 2, 3))
    test_memcpy_1(dest, src) = ccall(:memcpy, Ptr{Cvoid}, (Ptr{Int}, Ptr{Int}, Csize_t), dest, src, 3 * sizeof(Int))
    @cpjit(test_memcpy_1, (dest, src))
    @test dest[] == (1, 2, 3)

    src = Ref((4, 5, 6))
    test_memcpy_2(dest, src) = ccall(:memcpy, Ptr{Cvoid}, (Ref{Int}, Ref{Int}, Csize_t), dest, src, 3 * sizeof(Int))
    @cpjit(test_memcpy_2, (dest, src))
    @test dest[] == (4, 5, 6)

    src = (7, 8, 9)
    test_memcpy_3(dest, src) = ccall(:memcpy, Ptr{Cvoid}, (Ref{Int}, Ref{Int}, Csize_t), dest, src, 3 * sizeof(Int))
    @cpjit(test_memcpy_3, (dest, src))
    @test dest[] == (7, 8, 9)
end

# Ignoring all @ccall macro parser tests

# call some c functions
@testset "run @ccall with C standard library functions" begin
    test_at_ccall_1() = @ccall(sqrt(4.0::Cdouble)::Cdouble)
    @test @cpjit(test_at_ccall_1, ()) == 2.0

    str = "hello"
    function test_at_ccall_2(str)
        buf = Ptr{UInt8}(Libc.malloc((length(str) + 1) * sizeof(Cchar)))
        @ccall strcpy(buf::Cstring, str::Cstring)::Cstring
        buf
    end
    buf = C_NULL
    try
        buf = @cpjit(test_at_ccall_2, (str,))
        @test unsafe_string(buf) == str
    finally
        buf != C_NULL && Libc.free(buf)
    end

    # test pointer interpolation
    str_identity = @cfunction(identity, Cstring, (Cstring,))
    test_at_ccall_3() = @ccall $str_identity("foo"::Cstring)::Cstring
    foo = @cpjit(test_at_ccall_3, ())
    @test unsafe_string(foo) == "foo"
    # TODO Depends on interpolation of @cfunction
    # # test interpolation of an expression that returns a pointer.
    # test_at_ccall_4() = @ccall $(@cfunction(identity, Cstring, (Cstring,)))("foo"::Cstring)::Cstring
    # foo = @cpjit(test_at_ccall_4, ())
    # @test unsafe_string(foo) == "foo"

    # test of a vararg foreigncall using @ccall
    strp = Ref{Ptr{Cchar}}(0)
    fmt = "hi+%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%hhd-%.1f-%.1f-%.1f-%.1f-%.1f-%.1f-%.1f-%.1f-%.1f\n"

    function test_at_ccall_5()
        @ccall asprintf(
            strp::Ptr{Ptr{Cchar}},
            fmt::Cstring,
            ; # begin varargs
            0x01::UInt8, 0x02::UInt8, 0x03::UInt8, 0x04::UInt8, 0x05::UInt8, 0x06::UInt8, 0x07::UInt8, 0x08::UInt8, 0x09::UInt8, 0x0a::UInt8, 0x0b::UInt8, 0x0c::UInt8, 0x0d::UInt8, 0x0e::UInt8, 0x0f::UInt8,
            1.1::Cfloat, 2.2::Cfloat, 3.3::Cfloat, 4.4::Cfloat, 5.5::Cfloat, 6.6::Cfloat, 7.7::Cfloat, 8.8::Cfloat, 9.9::Cfloat,
        )::Cint
    end
    len = @cpjit(test_at_ccall_5, ())
    str = unsafe_string(strp[], len)
    @ccall free(strp[]::Cstring)::Cvoid
    @test_broken str == "hi+1-2-3-4-5-6-7-8-9-10-11-12-13-14-15-1.1-2.2-3.3-4.4-5.5-6.6-7.7-8.8-9.9\n"
end

@testset "Cwstring" begin
    buffer = Array{Cwchar_t}(undef, 100)
    function test_cwstring(buffer)
        @static if Sys.iswindows()
            @ccall swprintf_s(buffer::Ptr{Cwchar_t}, length(buffer)::Csize_t, "α+%ls=%hhd"::Cwstring; "β"::Cwstring, 0x0f::UInt8)::Cint
        else
            @ccall swprintf(buffer::Ptr{Cwchar_t}, length(buffer)::Csize_t, "α+%ls=%hhd"::Cwstring; "β"::Cwstring, 0x0f::UInt8)::Cint
        end
    end
    len = @cpjit(test_cwstring, (buffer,))
    Libc.systemerror("swprintf", len < 0)
    str = GC.@preserve buffer unsafe_string(pointer(buffer), len)
    @test str == "α+β=15"
    str = GC.@preserve buffer unsafe_string(Cwstring(pointer(buffer)))
    @test str == "α+β=15"
end

# issue #36458
compute_lib_name() = "libcc" * "alltest"
let
    ccall_lazy_lib_name(x) = ccall((:testUcharX, compute_lib_name()), Int32, (UInt8,), x % UInt8)
    @test @cpjit(ccall_lazy_lib_name, (3,)) == 1
    ccall_with_undefined_lib() = ccall((:time, xx_nOt_DeFiNeD_xx), Cint, (Ptr{Cvoid},), C_NULL)
    @test_throws UndefVarError(:xx_nOt_DeFiNeD_xx, @__MODULE__) @cpjit(ccall_with_undefined_lib, ())
end

@testset "transcode for UInt8 and UInt16" begin
    a = [UInt8(1), UInt8(2), UInt8(3)]
    function test_transcode_1(a)
        a16 = transcode(UInt16, a)
        a8 = transcode(UInt8, a16)
    end
    a8 = @cpjit(test_transcode_1, (a,))
    @test a8 == a
    b = [UInt16(1), UInt16(2), UInt16(3)]
    function test_transcode_2(b)
        b8 = transcode(UInt8, b)
        b16 = transcode(UInt16, b8)
    end
    b16 = @cpjit(test_transcode_2, (b,))
    @test b16 == b
end

@testset "transcode String to String" begin
    a = "Julia strings and things"
    test_transcode_3(a) = transcode(String, a)
    aa = @cpjit(test_transcode_3, (a,))
    @test aa === a
end

fn45187() = nothing

# issue 33413
@testset "cglobal lowering" begin
    # crash in cglobal33413_ptrinline[_notype]() specifically requires the library pointer be
    # retrieved inside the function; using global pointer variable doesn't trigger the crash
    function cglobal33413_ptrvar()
        libh = Libdl.dlopen(libccalltest)
        sym = Libdl.dlsym(libh, :global_var)
        return cglobal(sym, Cint)
    end
    function cglobal33413_ptrvar_notype()
        libh = Libdl.dlopen(libccalltest)
        sym = Libdl.dlsym(libh, :global_var)
        return cglobal(sym)
    end
    function cglobal33413_ptrinline()
        libh = Libdl.dlopen(libccalltest)
        return cglobal(Libdl.dlsym(libh, :global_var), Cint)
    end
    function cglobal33413_ptrinline_notype()
        libh = Libdl.dlopen(libccalltest)
        return cglobal(Libdl.dlsym(libh, :global_var))
    end
    function cglobal33413_tupleliteral()
        return cglobal((:global_var, libccalltest), Cint)
    end
    function cglobal33413_tupleliteral_notype()
        return cglobal((:global_var, libccalltest))
    end
    function cglobal33413_literal()
        return cglobal(:sin, Cint)
    end
    function cglobal33413_literal_notype()
        return cglobal(:sin)
    end
    function cglobal49142_nothing()
        return cglobal(nothing)
    end
    function cglobal45187fn()
        return cglobal((:fn, fn45187))
    end
    @test unsafe_load(@cpjit(cglobal33413_ptrvar, ())) == 1
    @test unsafe_load(@cpjit(cglobal33413_ptrinline, ())) == 1
    ## TODO This depends on the resolution of Expr as Symbols for the cglobal call
    ## should be resolved by enabling transform_ir_for_cpjit, already works using with_new_compiler
    ## e.g. @test unsafe_load(CP.with_new_compiler(cglobal33413_tupleliteral)) == 1
    # @test unsafe_load(@cpjit(cglobal33413_tupleliteral, ())) == 1
    @test unsafe_load(convert(Ptr{Cint}, @cpjit(cglobal33413_ptrvar_notype, ()))) == 1
    @test unsafe_load(convert(Ptr{Cint}, @cpjit(cglobal33413_ptrinline_notype, ()))) == 1
    ## TODO This depends on the resolution of Expr as Symbols for the cglobal call
    ## should be resolved by enabling transform_ir_for_cpjit
    ## e.g. @test unsafe_load(convert(Ptr{Cint}, CP.with_new_compiler(cglobal33413_tupleliteral_notype))) == 1
    # @test unsafe_load(convert(Ptr{Cint}, @cpjit(cglobal33413_tupleliteral_notype, ()))) == 1
    @test @cpjit(cglobal33413_literal, ()) != C_NULL
    @test @cpjit(cglobal33413_literal_notype, ()) != C_NULL
    @test_throws(TypeError, cglobal49142_nothing())
    @test_throws(TypeError, cglobal45187fn())
    @test_throws(TypeError, @eval cglobal(nothing))
    @test_throws(TypeError, @eval cglobal((:fn, fn45187)))
end

const libfrobozz = ""

function somefunction_not_found()
    return ccall((:somefunction, libfrobozz), Cvoid, ())
end

function somefunction_not_found_libc()
    return ccall(:test, Int, ())
end

@testset "library not found" begin
    if Sys.islinux()
        @test_throws "could not load symbol \"somefunction\"" somefunction_not_found()
    else
        @test_throws "could not load library \"\"" somefunction_not_found()
    end
    @test_throws "could not load symbol \"test\"" somefunction_not_found_libc()
end
