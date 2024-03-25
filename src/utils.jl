is_little_endian() = ENDIAN_BOM == 0x04030201


unwrap(g::GlobalRef) = getproperty(g.mod, g.name)
iscallable(@nospecialize(f)) = !isempty(methods(f))


# TODO Remove this, because we cannot reliably query jl_function_t * (clarified on Slack)
function pointer_from_function(fn::Function)
    pm = pointer_from_objref(typeof(fn).name.module)
    ps = pointer_from_objref(nameof(fn))
    pf = ccall((:jl_get_global, path_libjulia[]), Ptr{Cvoid}, (Ptr{Cvoid},Ptr{Cvoid}), pm, ps)
    @assert pf !== C_NULL
    return pf
end


# for debugging jl_call
box(x::Int8) = ccall((:jl_box_int8,path_libjulia[]), Ptr{Cvoid}, (Int8,), x)
box(x::Int16) = ccall((:jl_box_int16,path_libjulia[]), Ptr{Cvoid}, (Int16,), x)
box(x::Int32) = ccall((:jl_box_int32,path_libjulia[]), Ptr{Cvoid}, (Int32,), x)
box(x::Int64) = ccall((:jl_box_int64,path_libjulia[]), Ptr{Cvoid}, (Int64,), x)
box(x::UInt8) = ccall((:jl_box_uint8,path_libjulia[]), Ptr{Cvoid}, (UInt8,), x)
box(x::UInt16) = ccall((:jl_box_uint16,path_libjulia[]), Ptr{Cvoid}, (UInt16,), x)
box(x::UInt32) = ccall((:jl_box_uint32,path_libjulia[]), Ptr{Cvoid}, (UInt32,), x)
box(x::UInt64) = ccall((:jl_box_uint64,path_libjulia[]), Ptr{Cvoid}, (UInt64,), x)
box(x::Float16) = ccall((:jl_box_float16,path_libjulia[]), Ptr{Cvoid}, (Float16,), x)
box(x::Float32) = ccall((:jl_box_float32,path_libjulia[]), Ptr{Cvoid}, (Float32,), x)
box(x::Float64) = ccall((:jl_box_float64,path_libjulia[]), Ptr{Cvoid}, (Float64,), x)
unbox(::Type{Int8}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_int8,path_libjulia[]), Int8, (Ptr{Cvoid},), ptr)
unbox(::Type{Int16}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_int16,path_libjulia[]), Int16, (Ptr{Cvoid},), ptr)
unbox(::Type{Int32}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_int32,path_libjulia[]), Int32, (Ptr{Cvoid},), ptr)
unbox(::Type{Int64}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_int64,path_libjulia[]), Int64, (Ptr{Cvoid},), ptr)
unbox(::Type{UInt8}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_uint8,path_libjulia[]), UInt8, (Ptr{Cvoid},), ptr)
unbox(::Type{UInt16}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_uint16,path_libjulia[]), UInt16, (Ptr{Cvoid},), ptr)
unbox(::Type{UInt32}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_uint32,path_libjulia[]), UInt32, (Ptr{Cvoid},), ptr)
unbox(::Type{UInt64}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_uint64,path_libjulia[]), UInt64, (Ptr{Cvoid},), ptr)
unbox(::Type{Float16}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_float16,path_libjulia[]), Float16, (Ptr{Cvoid},), ptr)
unbox(::Type{Float32}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_float32,path_libjulia[]), Float32, (Ptr{Cvoid},), ptr)
unbox(::Type{Float64}, ptr::Ptr{Cvoid}) = ccall((:jl_unbox_float64,path_libjulia[]), Float64, (Ptr{Cvoid},), ptr)
