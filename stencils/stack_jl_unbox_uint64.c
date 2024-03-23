
#include "common.h"

void
_JIT_ENTRY(void ** stack_ptr) {
  jl_value_t *val = (jl_value_t *)(stack_ptr--)[0];
  uint64_t *ret = (uint64_t *)(stack_ptr--)[0];
  void (*continuation)(void **) = (stack_ptr--)[0];
  *ret = jl_unbox_uint64(val);
  continuation(stack_ptr);
}

