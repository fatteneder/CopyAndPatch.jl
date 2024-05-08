using CopyAndPatch
using Libdl


function foreign(x::Int64)
    @ccall CopyAndPatch.libffihelpers_path[].my_square(x::Int64)::Int64
end
foreign(1)

# @noinline function g(x,y)
#     versioninfo()
#     x + y
# end
# # f(x) = nothing
# # f(x) = (x+2)*2
# # f(x) = x
# # f(x) = x+2
# # f(x) = (x+2)*3-x^3
# # f(x) = (x+2)/3
# f(x) = x < 1 ? 1 : 2
# # function f(x)
# #     versioninfo()
# #     g(x,2*x)
# #     x += log(x)
# #     (x+2)/3
# # end

# @noinline function g(x,y)
#     versioninfo()
#     x + y
# end
# # TODO Moving f(x) to here gives a segfault
# function f(x)
#     versioninfo()
#     g(x,2*x)
#     x += log(x)
#     (x+2)/3
# end
function f(x)
    versioninfo()
    x+1
end


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
# eulers_sieve(10)

# function mul2(n)
#     a = collect(1:n)
#     b = zeros(Int64, length(a))
#     for i in 1:length(a)
#         b[i] = 2*a[i]
#     end
#     return b
# end
# mul2(3)

# function mycollect(n)
#     return collect(1:n)
# end
# mycollect(3)


# function myrange(n)
#     return myrange(1:n)
# end
# mycollect(3)

function myfn1(n)
    x = 2
    if n > 3
        x *= 2
    else
        x -= 3
    end
    return x
end
# myfn1(3)

# function myfn2(n)
#     x = 2
#     if n > 3
#         x *= 2
#     else
#         x -= 3
#     end
#     return x
# end
# myfn2(3)

# memory, preserve = jit(f, (Int64,))
# memory = jit(eulers_sieve, (Int64,))
# memory = jit(mul2, (Int64,))
memory, preserve = jit(foreign, (Int64,))
# memory = jit(mycollect, (Int64,))
# memory = jit(myrange, (Int64,))
# memory = jit(myfn1, (Int64,))
# memory = jit(myfn2, (Int64,))
# memory = jit(f, (Int32,Int32))
CopyAndPatch.code_native(memory)
GC.@preserve preserve begin
    ccall(pointer(memory), Cvoid, (Cint,), 1)
end
