#include "common.h"
#include <ffi.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>


jl_value_t * mwe_jl_alloc_genericmemory(size_t nel) {
   jl_value_t *memory_type = jl_eval_string("Memory{Int64}");
   jl_value_t *memory = (jl_value_t *)jl_alloc_genericmemory(memory_type, nel);
   return memory;
}

int64_t mwe_accept_jl_type(jl_value_t *x) {
   jl_value_t *y = jl_get_field(x, "y");
   return jl_unbox_int64(y);
}

int64_t mwe_my_square_jl(jl_value_t *x) {
   int64_t xx = jl_unbox_int64(x);
   return xx*xx;
}

int mwe_my_square(int x) {
   return x*x;
}

int mwe_my_square_w_ptr_arg(int *x) {
   return (*x)*(*x);
}

void mwe_do_nothing(void) {
   printf("doing nothing on the C side...\n");
}

int * mwe_alloc_an_array(int n) {
   int *a = (int *)malloc(sizeof(int)*n);
   for (int i = 0; i < n; i++)
      a[i] = i;
   return a;
}
