using CopyAndPatch
using Libdl


function eulers_sieve(n)
    qs = collect(1:n)
    ms = zeros(Int64, length(qs))
    p = 2
    while true
        for i in 2*p:p:n
            ms[i] = 1
        end
        next_p = nothing
        # @show ms, qs
        for i in 1:length(qs)
            # @show p, i, ms[i]
            if ms[i] == 0 && i > p
                next_p = i
                break
            end
        end
        isnothing(next_p) && break
        p = next_p
    end
    ps = [ q for (i,q) in enumerate(qs) if ms[i] == 0 ]
    ps
end

function myarray(n)
    # return [1, 2]
    return [1]
end

function mytuple(n)
    tpl = (n,2*n)
    println(tpl)
    return tpl
end

function myrange(n)
    return 1:n
end

function myfn1(n)
    x = 2
    if n > 3
        x *= 2
    else
        x -= 3
    end
    return x
end

function myalloc(n::UInt64)
    # @ccall jl_alloc_genericmemory(Memory{Int64}::Any, n::UInt64)::Ref{Memory{Int64}}
    println(CopyAndPatch.value_pointer(Memory{Int64}))
    @ccall jl_alloc_genericmemory(Memory{Int64}::Any, n::UInt64)::Ref{Memory{Int64}}
    return 1
end

# function mytestalloc1(n::UInt64)
#     @ccall CopyAndPatch.libmwes_path[].mwe_jl_alloc_genericmemory_carg(n::UInt64)::Ref{Memory{Int64}}
# end

function mytestalloc2(n::UInt64)
    memory = CopyAndPatch.value_pointer(Memory{Int64})
    println("SERS ", memory)
    @ccall CopyAndPatch.libmwes_path[].mwe_jl_alloc_genericmemory_jlarg(memory::Ptr{Memory{Int64}})::Ref{Memory{Int64}}
    # @ccall CopyAndPatch.libmwes_path[].mwe_jl_alloc_genericmemory_jlarg(Memory{Int64}::Any)::Ref{Memory{Int64}}
end

# function foreign_carg(n::Int64)
#     @ccall CopyAndPatch.libmwes_path[].mwe_foreign_carg(n::Int64)::Cint
# end

# function foreign_jlarg(n::Int64)
#     @ccall CopyAndPatch.libmwes_path[].mwe_foreign_jlarg(n::Any)::Cint
# end

function mycconvert(x)
    Ref{Int64}(x)
    # Base.cconvert(Ref{Int64}, x)
end

function mybitcast(x)
    Core.bitcast(UInt, x)
end

function my_value_pointer(x::Int64)
    return CopyAndPatch.value_pointer(x)
    # y = Ref(x)
    # return CopyAndPatch.value_pointer(y)
    # y = Ref(x)
    # z = @ccall jl_value_ptr(y::Any)::Ptr{Nothing}
    # return z
    # z = @ccall jl_value_ptr(x::Any)::Any
    # return z
end

# mc = jit(mycollect, (Int64,))
# mc = jit(myarray, (Int64,))
# mc = jit(myalloc, (UInt64,))
# mc = jit(mytestalloc1, (UInt64,))
# mc = jit(mytestalloc2, (UInt64,))
# mc = jit(mycconvert, (UInt64,))
# mc = jit(mytuple, (Int64,))
# mc = jit(myrange, (Int64,))

# @show mycconvert(C_NULL)
# mc = jit(mycconvert, (Ptr{Nothing},))

# mybitcast(C_NULL)
# mc = jit(mybitcast, (Ptr{Nothing},))

# display(my_value_pointer(123))
# mc = jit(my_value_pointer, (Int64,))

# display(my_data_pointer(1))
# mc = jit(my_data_pointer, (Int64,))

# display(foreign_1(3))
# mc = jit(foreign_1, (Int64,))
# display(foreign_2(3))
# mc = jit(foreign_2, (Int64,))
# display(foreign_3(3))
# mc = jit(foreign_3, (Int64,))
display(foreign_w_jl_1(3))
mc = jit(foreign_w_jl_1, (JIT_MutDummy,))
