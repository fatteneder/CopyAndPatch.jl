is_little_endian() = ENDIAN_BOM == 0x04030201


const path_libjulia = dlpath("libjulia")
function pointer_from_function(fn::Function)
    pm = pointer_from_objref(typeof(fn).name.module)
    ps = pointer_from_objref(nameof(fn))
    pf = ccall((:jl_get_global, path_libjulia), Ptr{Cvoid}, (Ptr{Cvoid},Ptr{Cvoid}), pm, ps)
    @assert pf !== C_NULL
    return pf
end
