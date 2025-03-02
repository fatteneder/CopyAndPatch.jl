module FromGPUCompiler


# Stuff in here is taken from GPUCompiler.jl @ a0fd55d7f22f8906f8a91a788492240d4b9b0f24,
# including comments and doc strings, but modified to obey style-guide.md rules.


import Base
import Core.Compiler as CC


@inline function signature_type_by_tt(ft::Type, tt::Type)
    u = Base.unwrap_unionall(tt)::DataType
    return Base.rewrap_unionall(Tuple{ft, u.parameters...}, tt)
end


"""
    methodinstance(ft::Type, tt::Type, [world::UInt])

Look up the method instance that corresponds to invoking the function with type `ft` with
argument typed `tt`. If the `world` argument is specified, the look-up is static and will
always return the same result. If the `world` argument is not specified, the look-up is
dynamic and the returned method instance will depende on the current world age. If no method
is found, a `MethodError` is thrown.

This function is highly optimized, and results do not need to be cached additionally.

Only use this function with concrete signatures, i.e., using the types of values you would
pass at run time. For non-concrete signatures, use `generic_methodinstance` instead.

"""
methodinstance


function generic_methodinstance(
        @nospecialize(ft::Type), @nospecialize(tt::Type),
        world::Integer = Base.tls_world_age()
    )
    sig = signature_type_by_tt(ft, tt)

    match, _ = CC._findsup(sig, nothing, world)
    match === nothing && throw(MethodError(ft, tt, world))

    mi = CC.specialize_method(match)

    return mi::MethodInstance
end


# on 1.11 (JuliaLang/julia#52572, merged as part of JuliaLang/julia#52233) we can use
# Julia's cached method lookup to simply look up method instances at run time.
# @static if VERSION >= v"1.11.0-DEV.1552"

# XXX: version of Base.method_instance that uses a function type
@inline function methodinstance(
        @nospecialize(ft::Type), @nospecialize(tt::Type),
        world::Integer = Base.tls_world_age()
    )
    sig = signature_type_by_tt(ft, tt)
    @assert Base.isdispatchtuple(sig)   # JuliaLang/julia#52233

    mi = ccall(
        :jl_method_lookup_by_tt, Any,
        (Any, Csize_t, Any),
        sig, world, #=method_table=# nothing
    )
    mi === nothing && throw(MethodError(ft, tt, world))
    mi = mi::Base.MethodInstance

    # `jl_method_lookup_by_tt` and `jl_method_lookup` can return a unspecialized mi
    if !Base.isdispatchtuple(mi.specTypes)
        mi = CC.specialize_method(mi.def, sig, mi.sparam_vals)::Base.MethodInstance
    end

    return mi
end


end
