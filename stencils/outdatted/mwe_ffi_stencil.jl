using CopyAndPatch
using Libdl

# TODO separate issue
# Atm we can jit and immediately run a function.
# However, it seems that in the case that GC collects between jitting and running,
# immutable values that were (statically) patched might be moved and so we run into a segfaul.
# How to fix that?
# Just push them into static_prms? I guess for a bitstype we can just memcpy the contents
# of the value_pointer. But do we copy for arbitrary immutable types?
# This problem must be solveable, because Julia itself should suffer from the same problem.
# That is, it also inlines any such values.
#
# To test if this is really the reason for the segfaults,
# you can play with GC.enable() and GC.gc().

function foreign(n::Int64)
    # DONE with v1 and v2
    # @ccall CopyAndPatch.libmwes_path[].mwe_foreign_carg_cret(n::Clonglong)::Clonglong
    @ccall CopyAndPatch.libmwes_path[].mwe_foreign_carg_jlret(n::Clonglong)::Any
end
foreign(3)
mc = jit(foreign, (Int64,))

# function foreign(n::Vector{Int64})
#     @ccall CopyAndPatch.libmwes_path[].mwe_foreign_cptr_cret(n::Ptr{Int64})::Clonglong
# end
# foreign([1,2])
# mc = jit(foreign, (Vector{Int64},))

# mutable struct Dummy
#     x
# end
# struct ImmutDummy2
#     x
# end
# function foreign(n)
#     @ccall CopyAndPatch.libmwes_path[].mwe_foreign_jlarg_cret(n::Any)::Clonglong
#     # @ccall CopyAndPatch.libmwes_path[].mwe_foreign_jlarg_jlret(n::Any)::Any
# end
# foreign(ImmutDummy2(1))
# mc = jit(foreign, (ImmutDummy2,))
