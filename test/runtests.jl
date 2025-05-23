using Test

import CopyAndPatch as CP
import Base.Libc
import Libdl
import Random
import InteractiveUtils

# TODO Maybe move to src/ and utilize @invokelatest syntax (only need Base.destruct_callex)
macro cpjit(f, args, types::Union{Expr,Symbol,Nothing}=nothing)
    use_interp = get!(ENV, "CPJIT_USE_INTERP", "") |> isempty
    types_given, type_check = !isnothing(types), nothing
    if types_given
        type_check = quote
            if !(typeof($(args)) <: Tuple{$(types)...})
                error("@cpjit: mismatch between arguments and types")
            end
        end
    end
    if use_interp
        mc = gensym("mc")
        jit_mc = if types_given
            quote $mc = CP.jit($f, $(types)) end
        else
            quote $mc = CP.jit($f, typeof.($(args))) end
        end
        return quote
            $(type_check)
            $(jit_mc)
            $(mc)($(args)...)
        end |> esc
    else
        return quote
            $(type_check)
            CP.with_new_compiler($f, $(args)...)
        end |> esc
    end
end

include("bytevector.jl")
include("jit.jl")
include("ffi.jl")
include("ccall.jl")
