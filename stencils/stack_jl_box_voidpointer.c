
#include "common.h"

void
_JIT_ENTRY(void **stack_ptr) {
   void * val = (void *)(stack_ptr--)[0];
   jl_value_t **ret = (jl_value_t **)(stack_ptr--)[0];
   void (*continuation)(void **) = (stack_ptr--)[0];
   *ret = jl_box_voidpointer(val);
   continuation(stack_ptr);
}
