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

mutable struct MutDummy
    x::String
    y::Int64
end
struct ImmutDummy
    x::String
    y::Int64
end
@testset "ffi_call with Julia types" begin
    handle = dlopen(CopyAndPatch.libmwes_path[])

    cif = CopyAndPatch.Ffi_cif(Clonglong, (Ptr{Cvoid},))
    fn = dlsym(handle, :mwe_my_square_jl)
    result = CopyAndPatch.ffi_call(cif, fn, [123])
    expected = 123^2
    @test result == expected

    # mutable type
    cif = CopyAndPatch.Ffi_cif(Clonglong, (Ptr{Cvoid},))
    fn = dlsym(handle, :mwe_accept_jl_type)
    x = MutDummy("sers",12321)
    result = CopyAndPatch.ffi_call(cif, fn, [x])
    expected = 12321
    @test result == expected

    # immutable type
    cif = CopyAndPatch.Ffi_cif(Clonglong, (Ptr{Cvoid},))
    fn = dlsym(handle, :mwe_accept_jl_type)
    x = ImmutDummy("sers",12321)
    result = CopyAndPatch.ffi_call(cif, fn, [x])
    expected = 12321
    @test result == expected

    cif = CopyAndPatch.Ffi_cif(Ptr{Cvoid}, (Csize_t,))
    fn = dlsym(handle, :mwe_jl_alloc_genericmemory)
    result = CopyAndPatch.ffi_call(cif, fn, [Csize_t(15)])
    # TODO How to convert this to a julia type?

    # test Cstring return types
    handle = dlopen(dlpath("libjulia.so"))

    cif = CopyAndPatch.Ffi_cif(Cstring, (Ptr{Cvoid},))
    fn = dlsym(handle, :jl_typeof_str)
    x = MutDummy("sers",12321)
    result = CopyAndPatch.ffi_call(cif, fn, [x])
    expected = "MutDummy"
    @test unsafe_string(result) == expected

    cif = CopyAndPatch.Ffi_cif(Cstring, (Ptr{Cvoid},))
    fn = dlsym(handle, :jl_typeof_str)
    x = ImmutDummy("sers",12321)
    result = CopyAndPatch.ffi_call(cif, fn, [x])
    expected = "ImmutDummy"
    @test unsafe_string(result) == expected
end
