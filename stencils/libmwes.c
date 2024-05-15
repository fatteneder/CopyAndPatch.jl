#include "common.h"
#include <ffi.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>


jl_value_t * mwe_jl_alloc_genericmemory(size_t nel) {
   printf("allocating generic memory...\n");
   jl_value_t *memory_type = jl_eval_string("Memory{Int64}");
   jl_value_t *memory = (jl_value_t *)jl_alloc_genericmemory(memory_type, nel);
   return memory;
}

int * mwe_accept_jl_type(jl_value_t *x) {
   printf("accepting a jl type...\n");
   printf("x = %p\n", x);
   printf("jl_typeof_str(x) = %s\n", jl_typeof_str(x));
   int *a = (int *)malloc(sizeof(int));
   return a;
}

int64_t mwe_my_square_jl(jl_value_t *x) {
   int64_t xx = jl_unbox_int64(x);
   printf("my_square_jl: jl_unbox_int64(x) = %d\n", xx);
   return xx*xx;
}

void mwe_whats_an_immutable() {
   jl_value_t *v = jl_eval_string("ImmutDummy(\"sers\",1)");
   printf("jl_typeof_str(v) = %s\n", jl_typeof_str(v));
   return;
}

int mwe_my_square(int x) {
   printf("my_square: x = %d\n", x);
   return x*x;
}

int mwe_my_square_w_ptr_arg(int *x) {
   printf("my_square: x = %d\n", *x);
   return (*x)*(*x);
}

int mwe_my_square_w_ptrptr_arg(int **x) {
   printf("my_square: x = %d\n", **x);
   return (**x)*(**x);
}

void mwe_do_nothing(void) {
   printf("doing nothing...\n");
}

void mwe_do_nothing_with_arg(int a) {
   printf("doing nothing with arg...\n");
   printf("a = %d\n", a);
}

int64_t * mwe_do_nothing_with_arg_and_return_ptr(int64_t a) {
   printf("doing nothing with arg and return ptr...\n");
   int64_t *b = (int64_t *)malloc(sizeof(int64_t));
   *b = 1;
   return b;
}

typedef struct _sometype_t {
   int a;
   int b;
} mwe_sometype_t;

mwe_sometype_t * mwe_do_nothing_with_arg_and_return_ptr_to_sometype(int64_t a) {
   printf("doing nothing with arg and return ptr to mwe_sometype...\n");
   mwe_sometype_t *t = (mwe_sometype_t *)malloc(sizeof(mwe_sometype_t));
   t->a = 1;
   t->b = 1;
   return t;
}
