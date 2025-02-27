using Test

import CopyAndPatch as CP
import Base.Libc
import Libdl
import Random
import InteractiveUtils


# from https://github.com/JuliaLang/julia/issues/12711#issuecomment-912740865
function my_redirect_stdout(f::Function, io::IO)
    old_stdout = stdout
    rd, = redirect_stdout()
    task = @async write(io, rd)
    try
        ret = f()
        Libc.flush_cstdio()
        flush(stdout)
        return ret
    finally
        close(rd)
        redirect_stdout(old_stdout)
        wait(task)
    end
end


@testset "ByteVector" begin

    bvec = CP.ByteVector(1)
    bvec = CP.ByteVector(0)
    @test_throws ArgumentError CP.ByteVector(-10)

    bvec = CP.ByteVector(UInt8[])
    bvec = CP.ByteVector(UInt8[1, 2, 3])
    bvec = CP.ByteVector(UInt64[1, 2, 3, 4])
    bvec = CP.ByteVector(UInt32[1, 2, 3, 4])
    @test_throws MethodError CP.ByteVector(Any[])
    @test_throws MethodError CP.ByteVector(Int64[-1, -2, 3, 4])
    @test_throws MethodError CP.ByteVector(Int64[1, 2, 3, 4])
    @test_throws MethodError CP.ByteVector(Float64[1, 2, 3, 4])

    bvec = CP.ByteVector(123)
    @test size(bvec) == (123,)

    n = 10
    for T in (UInt8, UInt32, UInt64)
        fill!(bvec, T(0))
        sz = sizeof(T)
        for i in 1:n
            bvec[(i - 1) * sz + 1] = T(i)
        end
        expected = T.(collect(1:n))
        content = zeros(T, n)
        @static if CP.is_little_endian()
            for i in 1:n, s in 0:(sz - 1)
                content[i] |= T(bvec[sz * (i - 1) + 1 + s])
            end
        else
            # TODO Is this correct?
            for i in 1:n, s in (sz - 1):-1:0
                content[i] |= T(bvec[sz * (i - 1) + 1 + s])
            end
        end
        @test content == expected
    end
    bvec[1] = pointer_from_objref(:blabla)

    fill!(bvec, 0)
    bvec[UInt8, 1] = 0x01
    @test bvec[1] == 0x01
    bvec[UInt16, 1] = 0x0100
    @test bvec[1] == 0x00
    @test bvec[2] == 0x01
    bvec[UInt32, 1] = 0x01000100
    @test bvec[1] == 0x00
    @test bvec[2] == 0x01
    @test bvec[3] == 0x00
    @test bvec[4] == 0x01
    bvec[UInt64, 1] = 0x0100010001000100
    @test bvec[1] == 0x00
    @test bvec[2] == 0x01
    @test bvec[3] == 0x00
    @test bvec[4] == 0x01
    @test bvec[5] == 0x00
    @test bvec[6] == 0x01
    @test bvec[7] == 0x00
    @test bvec[8] == 0x01

    @test pointer(bvec.d) == pointer(bvec)
    @test pointer(bvec.d, sizeof(UInt8) * 2 + 1) == pointer(bvec, UInt8, 3)
    @test pointer(bvec.d, sizeof(UInt16) * 2 + 1) == pointer(bvec, UInt16, 3)
    @test pointer(bvec.d, sizeof(UInt32) * 2 + 1) == pointer(bvec, UInt32, 3)
    @test pointer(bvec.d, sizeof(UInt64) * 2 + 1) == pointer(bvec, UInt64, 3)

end


include("jit.jl")
include("ffi.jl")
include("ccall.jl")
