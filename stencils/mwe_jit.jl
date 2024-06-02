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

function mwe2(x::Int64)
    y = Ref(x)
    println(CopyAndPatch.value_pointer(y))
    # println("sers")
    println(CopyAndPatch.value_pointer(y))
    # println("sers")
    # println(CopyAndPatch.value_pointer(y))
    return CopyAndPatch.value_pointer(y)
    # y = Ref(x)
    # z = @ccall jl_value_ptr(y::Any)::Ptr{Nothing}
    # return z
    # z = @ccall jl_value_ptr(x::Any)::Any
    # return z
end

@noinline function g(x,y)
    versioninfo()
    x + y
end
function f(x)
    versioninfo()
    2*x
    g(x,2*x)
    x += log(x)
    (x+2)/3
end

const libccalltest = "libccalltest"
# function mimic_test(xx)
function mimic_test(x)
    # x = 32
    a1 = Ref(x)
    println(typeof(a1)) # this is Base.RefValue{Int64}, as expected
                        # however, this value also appears boxed later in pointerref and causes the wrong result
    # println("SERS ", a1)
    a2 = @ccall jl_value_ptr(a1::Any)::Ptr{Cvoid}
    a3 = Base.C_NULL
    # a4 = Core.bitcast(Core.UInt, a2)
    # a5 = Core.bitcast(Core.UInt, a3)
    a11 = Base.bitcast(Ptr{Int64}, a2)
    # tmp = Base.pointerref(a14, 1, 1)
    # a14 = @ccall libccalltest.test_echo_p(a11::Ref{Int64})::Ptr{Int64}
    # a14 = @ccall "stencils/bin/libccalltest.so".test_echo_p(a11::Ref{Int64})::Ptr{Int64}
    # a14 = @ccall "stencils/bin/libccalltest.so".test_echo_p(a11::Ptr{Cvoid})::Ptr{Cvoid}
    # a14 = @ccall "stencils/bin/libccalltest.so".test_echo_p(a11::Ptr{Int64})::Ptr{Int64}
    println("SERS OIDA ", a11)
    a14 = a11
    a14 = @ccall "stencils/bin/libccalltest.so".test_echo_p(a11::Ptr{Int64})::Ptr{Int64}
    println("SERS OIDA ", a14)
    # println("BLABLA OIDA ", typeof(a14))
    # a14 = @ccall libccalltest.test_echo_p(a11::Ptr{Int64})::Ptr{Int64}
    a15 = Base.pointerref(a14, 1, 1)
    # println(a15)
    # println(typeof(a15))
    return a15
end
# function mimic_test(x)
#     a1 = Ref(x)
#     a2 = @ccall jl_value_ptr(a1::Any)::Ptr{Nothing}
# end
# function mimic_test(x)
#     @ccall jl_value_ptr(x::Any)::Ptr{Nothing}
# end

function mimic_test_v2(x)
    ty = Base.RefValue{Int64}
    vs = pointer([CopyAndPatch.box(x)])
    nvs = 1
    r = @ccall jl_new_structv(ty::Any, vs::Ptr{Any}, nvs::Csize_t)::Any
    @ccall jl_value_ptr(r::Any)::Ptr{Cvoid}
end

function test_echo_p(p)
    @ccall "stencils/bin/libccalltest.so".test_echo_p(p::Ptr{Int64})::Ptr{Int64}
end
# mc = jit(test_echo_p, (Ptr{Int64},))


# const libccalltest = "libccalltest"
# test_echo_p(x) = unsafe_load(ccall((:test_echo_p, libccalltest), Ptr{Int}, (Ref{Int},), x))
# @noinline f_test_echo_p(x) = test_echo_p(x)

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

# display(mwe2(123))
# mc = jit(mwe2, (Int64,))

# display(foreign_1(3))
# mc = jit(foreign_1, (Int64,))
# display(foreign_2(3))
# mc = jit(foreign_2, (Int64,))
# display(foreign_3(3))
# mc = jit(foreign_3, (Int64,))
# display(foreign_w_jl_1(3))
# mc = jit(foreign_w_jl_1, (JIT_MutDummy,))

# display(f(3))
# mc = jit(f, (Int64,))

# f_test_echo_p(132)
# mc = jit(f_test_echo_p, (Int64,))
# @test @ccall_echo_load(132, Ptr{Int}, Ref{Int}) === 132

mc = jit(mimic_test, (Int64,))

# ### Observations
# # - On julia -O1 both of these return random addresses
# # - On julia -O2 (default), the first one returns a constant address always
# function mimic_test(x)
#     a1 = Ref(x)
#     a2 = @ccall jl_value_ptr(a1::Any)::Ptr{Cvoid}
#     return a2
# end
# function mimic_test_v2(x)
#     ty = Base.RefValue{Int64}
#     vs = pointer([CopyAndPatch.box(x)])
#     nvs = 1
#     r = @ccall jl_new_structv(ty::Any, vs::Ptr{Any}, nvs::Csize_t)::Any
#     @ccall jl_value_ptr(r::Any)::Ptr{Cvoid}
# end
