
#include "common.h"

void
_JIT_ENTRY(void **stack_ptr) {
   uint8_t * val = (uint8_t *)(stack_ptr--)[0];
   jl_value_t **ret = (jl_value_t **)(stack_ptr--)[0];
   void (*continuation)(void **) = (stack_ptr--)[0];
   *ret = jl_box_uint8pointer(val);
   continuation(stack_ptr);
}
