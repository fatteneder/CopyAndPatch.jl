const libccalltest = joinpath(@__DIR__, "..", "stencils", "bin", "libccalltest.so")

#### These tests were crafted by me to figure things out

function mimic_test(x)
    a1 = Ref(x)
    a2 = @ccall jl_value_ptr(a1::Any)::Ptr{Cvoid}
    a11 = Base.bitcast(Ptr{Int64}, a2)
    a14 = @ccall "stencils/bin/libccalltest.so".test_echo_p(a11::Ptr{Int64})::Ptr{Int64}
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
# no segfault, but wrong result
# if Sys.WORD_SIZE == 64
    # this test is valid only for x86_64 and win64
    # @ccall_echo_func(164, IntLike, Int)
    # @test @ccall_echo_func(164, IntLike, Int).x === 164
# end
# @test @ccall_echo_func(IntLike(828), Int, IntLike) === 828
# @test @ccall_echo_func(913, Any, Any) === 913
# @test @ccall_echo_objref(553, Ptr{Any}, Any) === 553
# segfault again
# @test @ccall_echo_func(124, Ref{Int}, Any) === 124
@test @ccall_echo_load(422, Ptr{Any}, Ref{Any}) === 422
# works when skipping gc_roots
  # @test @ccall_echo_load([383], Ptr{Int}, Ref{Int}) === 383
@test @ccall_echo_load(Ref([144,172],2), Ptr{Int}, Ref{Int}) === 172
# that test is also ignored in julia
# # @test @ccall_echo_load(Ref([8],1,1), Ptr{Int}, Ref{Int}) === 8
