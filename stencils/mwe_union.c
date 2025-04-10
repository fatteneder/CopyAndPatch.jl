#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <julia.h>


typedef struct {
   uint8_t el[16];
} union_approx;

typedef struct {
   union_approx u;
} StructUnion;

typedef union {
   uint64_t p; double val;
} setter_double;

typedef union {
   uint64_t p; int val;
} setter_int;


// This is a MWE to investigate how deal with this test case:
// https://github.com/JuliaLang/julia/blob/a0740d0984d00da8010002079224e707cdcd8ee4/test/ccall.jl#L1599C1-L1607C4
// This case was added to address: https://github.com/JuliaLang/julia/issues/46786
//
// Below we investigate a simpler case (no tuples) where
// struct StructType
//    x::Union{Cint,Cdouble}
// end
// test(x::StructUnion) = println(typeof(x.x, " ", x.x)
//
// Interestingly, the thing below works only when one of the two 'set to int/double'
// blocks is commented, but enabling both gives garbage results in both cases.
//
// I asked on slack and Keno Fischer said there is not stable C equilvant type for this case,
// hence, julia decides the ABI.
int main()
{
   jl_init();

   // declare jl type
   jl_eval_string("mutable struct StructUnion x::Union{Cint,Cdouble} end");

   // compare sizeof, offsets
   jl_eval_string("@show sizeof(StructUnion)");
   jl_eval_string("@show fieldoffset(StructUnion, 1)");
   printf("C: sizeof(StructUnion) = %ld\n", sizeof(StructUnion));
   printf("C: offsetof(StructUnion, u) = %ld\n", offsetof(StructUnion, u));

   // define test func
   jl_eval_string("test(x::StructUnion) = println(typeof(x.x), \" \", x.x)");
   jl_value_t *ptr = jl_eval_string("@cfunction(test, Cvoid, (StructUnion,))");
   void (*fptr)(StructUnion) = jl_unbox_voidpointer(ptr);

   StructUnion x;

   // set to int
   setter_int si;
   si.val = 1;
   *(uint64_t*)&x.u = si.p;
   *(uint64_t*)&((uint8_t*)&x.u)[8] = (uint64_t)0;
   printf("%#lx\n", *(uint64_t*)&x.u);
   printf("%#lx\n", *(uint64_t*)&((uint8_t*)&x.u)[8]);
   fptr(x);

   /** // set to double */
   /** setter_double sd; */
   /** sd.val = 3.0; */
   /** *(uint64_t*)&x.u = sd.p; */
   /** *(uint64_t*)&((uint8_t*)&x.u)[8] = (uint64_t)1; */
   /** printf("%#lx\n", *(uint64_t*)&x.u); */
   /** printf("%#lx\n", *(uint64_t*)&((uint8_t*)&x.u)[8]); */
   /** fptr(x); */

   jl_atexit_hook(0);
   return 0;
}
