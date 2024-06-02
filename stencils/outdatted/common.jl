# TODO Remove this, because we cannot reliably query jl_function_t * (clarified on Slack)
# Only keep this around for the mwes.
function pointer_from_function(fn::Function)
    pm = pointer_from_objref(typeof(fn).name.module)
    ps = pointer_from_objref(nameof(fn))
    pf = @ccall jl_get_global(pm::Ptr{Cvoid}, ps::Ptr{Cvoid})::Ptr{Cvoid}
    @assert pf !== C_NULL
    return pf
end
