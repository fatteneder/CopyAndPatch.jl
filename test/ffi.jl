const libmwes = dlopen(CopyAndPatch.libmwes_path[])


@testset "libffi.ffi_type" begin

    ctypes = Any[ Cvoid, Cuchar, Cshort, Cint, Cuint, Cfloat,
                  Cdouble, Cuint, Cfloat, Cdouble, Clonglong, Culonglong,
                  ComplexF32, ComplexF64 ]
    for ct in ctypes
        p = CopyAndPatch.ffi_type(ct)
        @test p != C_NULL
    end
end


@testset "error handling" begin
    # return-on-copy requires concrete type
    @test_throws ArgumentError CopyAndPatch.Ffi_cif(AbstractArray, (Cint,))
    # Ref{Any} is invalid, use Ptr{Any}
    @test_throws ArgumentError CopyAndPatch.Ffi_cif(Ref{Any}, (Cint,))
end


@testset "ffi_call with only C types" begin
    handle = dlopen(CopyAndPatch.libmwes_path[])

    cif = CopyAndPatch.Ffi_cif(Cint, (Cint,))
    fn = dlsym(handle, :mwe_my_square)
    result = CopyAndPatch.ffi_call(cif, fn, [Int32(123)])
    expected = Int32(123)^2
    @test result == expected

    cif = CopyAndPatch.Ffi_cif(Cint, (Ptr{Cint},))
    fn = dlsym(handle, :mwe_my_square_w_ptr_arg)
    result = CopyAndPatch.ffi_call(cif, fn, [[Int32(123)]])
    expected = Int32(123)^2
    @test result == expected

    cif = CopyAndPatch.Ffi_cif(Cvoid, ())
    fn = dlsym(handle, :mwe_do_nothing)
    result = CopyAndPatch.ffi_call(cif, fn, [])
    expected = nothing
    @test result == expected

    cif = CopyAndPatch.Ffi_cif(Ptr{Cint}, (Cint,))
    fn = dlsym(handle, :mwe_alloc_an_array)
    p = C_NULL
    try
        p = CopyAndPatch.ffi_call(cif, fn, [5])
        @test p !== C_NULL
        result = unsafe_wrap(Vector{Int32}, p, (5,))
        expected = [ Int32(i-1) for i in 1:5 ]
        @test result == expected
    finally
        p !== C_NULL && Libc.free(p)
    end

    @test_throws ArgumentError("Encountered bad argument type Cvoid") CopyAndPatch.Ffi_cif(Cvoid, (Cvoid,))
end

mutable struct FFI_MutDummy
    x::String
    y::Int64
end
struct FFI_ImmutDummy
    x::String
    y::Int64
end
mutable struct my_type
    x::Cint
end
@testset "ffi_call with Julia types" begin
    handle = dlopen(CopyAndPatch.libmwes_path[])

    cif = CopyAndPatch.Ffi_cif(Clonglong, (Any,))
    fn = dlsym(handle, :mwe_my_square_jl)
    result = CopyAndPatch.ffi_call(cif, fn, [123])
    expected = 123^2
    @test result == expected

    # mutable type
    cif = CopyAndPatch.Ffi_cif(Clonglong, (Any,))
    fn = dlsym(handle, :mwe_accept_jl_type)
    x = FFI_MutDummy("sers",12321)
    result = CopyAndPatch.ffi_call(cif, fn, [x])
    expected = 12321
    @test result == expected

    # immutable type
    cif = CopyAndPatch.Ffi_cif(Clonglong, (Any,))
    fn = dlsym(handle, :mwe_accept_jl_type)
    x = FFI_ImmutDummy("sers",12321)
    result = CopyAndPatch.ffi_call(cif, fn, [x])
    expected = 12321
    @test result == expected

    cif = CopyAndPatch.Ffi_cif(Ptr{Cvoid}, (Csize_t,))
    fn = dlsym(handle, :mwe_jl_alloc_genericmemory_carg)
    res = CopyAndPatch.ffi_call(cif, fn, [Csize_t(15)])
    result = unsafe_pointer_to_objref(res)
    @test typeof(result) <: GenericMemory
    @test length(result) == 15

    cif = CopyAndPatch.Ffi_cif(Int64, (Complex{Int64},))
    fptr = dlsym(handle, :mwe_ctest_jl_arg_c_ret)
    c = Complex{Int64}(20,51)
    result = CopyAndPatch.ffi_call(cif, fptr, [c])
    @test result == 20+51

    cif = CopyAndPatch.Ffi_cif(Complex{Int64}, (Int64,Int64))
    fptr = dlsym(handle, :mwe_ctest_c_arg_jl_ret)
    result = CopyAndPatch.ffi_call(cif, fptr, [20,51])
    @test result == c

    cif = CopyAndPatch.Ffi_cif(Any, (Csize_t,))
    fn = dlsym(handle, :mwe_jl_alloc_genericmemory_carg)
    result = CopyAndPatch.ffi_call(cif, fn, [Csize_t(15)])
    @test typeof(result) <: GenericMemory
    @test length(result) == 15

    cif = CopyAndPatch.Ffi_cif(Any, (Any,))
    fn = dlsym(handle, :mwe_jl_alloc_genericmemory_jlarg)
    result = CopyAndPatch.ffi_call(cif, fn, [Memory{Int64}])
    @test typeof(result) === Memory{Int64}
    @test length(result) == 3

    # julia struct return type
    fn = dlsym(handle, :mwe_my_type)
    cif = CopyAndPatch.Ffi_cif(my_type, (Cint,))
    result = CopyAndPatch.ffi_call(cif, fn, [Cint(123)])
    @test typeof(result) == my_type
    @test result.x == Cint(123)

    # call libjulia-internal:jl_alloc_genericmemory directly
    handle = dlopen(dlpath("libjulia-internal.so"))

    cif = CopyAndPatch.Ffi_cif(Any, (Any,Csize_t,))
    fn = dlsym(handle, :jl_alloc_genericmemory)
    result = CopyAndPatch.ffi_call(cif, fn, [Memory{Int64},Csize_t(15)])
    @test typeof(result) <: GenericMemory
    @test length(result) == 15

    # test Cstring return types
    handle = dlopen(dlpath("libjulia.so"))

    cif = CopyAndPatch.Ffi_cif(Cstring, (Any,))
    fn = dlsym(handle, :jl_typeof_str)
    x = FFI_MutDummy("sers",12321)
    result = CopyAndPatch.ffi_call(cif, fn, [x])
    expected = "FFI_MutDummy"
    @test unsafe_string(result) == expected

    cif = CopyAndPatch.Ffi_cif(Cstring, (Any,))
    fn = dlsym(handle, :jl_typeof_str)
    x = FFI_ImmutDummy("sers",12321)
    result = CopyAndPatch.ffi_call(cif, fn, [x])
    expected = "FFI_ImmutDummy"
    @test unsafe_string(result) == expected

    # some of the ccall.jl tests
    handle = dlopen(joinpath(@__DIR__, "..", "stencils", "bin", "libccalltest.so"))

    cif = CopyAndPatch.Ffi_cif(Ptr{Int64}, (Any,))
    fn = dlsym(handle, :test_echo_p)
    result = CopyAndPatch.ffi_call(cif, fn, [1])
    expected = 1
    @test unsafe_load(result) == expected

    cif = CopyAndPatch.Ffi_cif(Ref{Int64}, (Any,))
    fn = dlsym(handle, :test_echo_p)
    result = CopyAndPatch.ffi_call(cif, fn, [1])
    expected = 1
    @show result
end

@testset "intrinsics" begin
    handle = dlopen(dlpath("libjulia-internal.so"))
    cif = CopyAndPatch.Ffi_cif(Ptr{Cvoid}, (Any,Any,))
    fn = dlsym(handle, :jl_bitcast)
    result = CopyAndPatch.ffi_call(cif, fn, [UInt,C_NULL])
    expected = C_NULL
    @test CopyAndPatch.unbox(Ptr{Cvoid},result) == expected
end
