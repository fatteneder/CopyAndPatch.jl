using CopyAndPatch
using Libffi_jll
using Libdl

# handle = dlopen(CopyAndPatch.libmwes_path[])
# cif = CopyAndPatch.Ffi_cif(Ptr{Cvoid}, (Csize_t,))
# fn = dlsym(handle, :mwe_jl_alloc_genericmemory)
# result = CopyAndPatch.ffi_call(cif, fn, [Csize_t(15)])

# handle = dlopen(dlpath("libjulia-internal.so"))
# cif = CopyAndPatch.Ffi_cif(Any, (Any,Csize_t,))
# fn = dlsym(handle, :jl_alloc_genericmemory)
# result = CopyAndPatch.ffi_call(cif, fn, [Memory{Int64},Csize_t(3)])

# const libpath = joinpath(@__DIR__, "..", "bin", "libccalltest.so")
#
# # let
# handle = dlopen(libpath)
# fnptr = dlsym(handle, :test_echo_p)
#
# r = Ref(123)
# GC.@preserve r begin
#     p = @ccall jl_value_ptr(r::Any)::Ptr{Cvoid}
#     pp = Core.Intrinsics.bitcast(Ptr{Int64}, p)
#     cif = CopyAndPatch.Ffi_cif(Ptr{Int64}, (Ptr{Int64},))
#     q = CopyAndPatch.ffi_call(cif, fnptr, [pp])
#     qq = @ccall libpath.test_echo_p(pp::Ptr{Int64})::Ptr{Int64}
#     @show q, qq
#
#     Core.Intrinsics.pointerref(q, 1, 1) |> display
#     Core.Intrinsics.pointerref(qq, 1, 1) |> display
# end
#
# # end


# mutable struct my_type
#     x::Cint
# end
# mutable struct my_type2
#     x::Cint
#     y::Cint
# end
# mutable struct my_type3
#     x::Int64
#     y::Int64
# end
# mutable struct my_type4
#     x::Int64
#     y::Int64
#     z::Int64
# end
#
# let
#     handle = dlopen(CopyAndPatch.libmwes_path[])
#     fptr = dlsym(handle, :mwe_my_type)
#     # cif = CopyAndPatch.Ffi_cif(my_type, (Cint,))
#     # CopyAndPatch.Ffi_cif(my_type2, (Cint,))
#     # CopyAndPatch.Ffi_cif(my_type3, (Cint,))
#     CopyAndPatch.Ffi_cif(my_type4, (Cint,))
#     # CopyAndPatch.ffi_call(cif, fptr, [Cint(123)])
#     # dataptr = CopyAndPatch.ffi_call(cif, fptr, [Cint(123)])
#     # mt = @ccall CopyAndPatch.libjuliahelpers_path[].gc_alloc(my_type::Any)::Any
#     # mt = @ccall CopyAndPatch.libjuliahelpers_path[].make_type_from_data(my_type::Any,dataptr::Ptr{Cvoid})::Any
# end

# let
#     handle = dlopen(CopyAndPatch.libmwes_path[])
#
#     # cif = CopyAndPatch.Ffi_cif(Clonglong, (Ptr{Cvoid},))
#     cif = CopyAndPatch.Ffi_cif(Clonglong, (Any,))
#     fn = dlsym(handle, :mwe_my_square_jl)
#     result = CopyAndPatch.ffi_call(cif, fn, [123])
#     expected = 123^2
#     result == expected
# end

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
let
    # mutable type
    handle = dlopen(CopyAndPatch.libmwes_path[])
    cif = CopyAndPatch.Ffi_cif(Clonglong, (Any,))
    fn = dlsym(handle, :mwe_accept_jl_type)
    x = FFI_MutDummy("sers",12321)
    result = CopyAndPatch.ffi_call(cif, fn, [x])
    expected = 12321
    result == expected
end
