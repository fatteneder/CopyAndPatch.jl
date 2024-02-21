using Test

import CopyAndPatch: ByteVector, MachineCode, is_little_endian


@testset "ByteVector" begin

    bvec = ByteVector(1)
    bvec = ByteVector(0)
    @test_throws ArgumentError ByteVector(-10)

    bvec = ByteVector(UInt8[])
    bvec = ByteVector(UInt8[1,2,3])
    bvec = ByteVector(UInt64[1,2,3,4])
    bvec = ByteVector(UInt32[1,2,3,4])
    @test_throws MethodError ByteVector(Any[])
    @test_throws MethodError ByteVector(Int64[-1,-2,3,4])
    @test_throws MethodError ByteVector(Int64[1,2,3,4])
    @test_throws MethodError ByteVector(Float64[1,2,3,4])

    bvec = ByteVector(123)
    @test size(bvec) == (123,)

    n = 10
    for T in (UInt8,UInt32,UInt64)
        fill!(bvec,T(0))
        sz = sizeof(T)
        for i = 1:n
            bvec[(i-1)*sz+1] = T(i)
        end
        expected = T.(collect(1:n))
        content = zeros(T, n)
        @static if is_little_endian()
            for i in 1:n, s in 0:sz-1
                content[i] |= T(bvec[sz*(i-1)+1+s])
            end
        else
            # TODO Is this correct?
            for i in 1:n, s in sz-1:-1:0
                content[i] |= T(bvec[sz*(i-1)+1+s])
            end
        end
        @test content == expected
    end
    bvec[1] = pointer_from_objref(:blabla)

end
