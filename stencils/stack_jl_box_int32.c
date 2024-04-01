
#include "common.h"

typedef union {
   void *ptr;
   int32_t val;
} ptrval;

void
_JIT_ENTRY(void **stack_ptr) {
   ptrval pv = (ptrval)(stack_ptr--)[0];
   jl_value_t **ret = (jl_value_t **)(stack_ptr--)[0];
   void (*continuation)(void **) = (stack_ptr--)[0];
   *ret = jl_box_int32(pv.val);
   continuation(stack_ptr);
}
