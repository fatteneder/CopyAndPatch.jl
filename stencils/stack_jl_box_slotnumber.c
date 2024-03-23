
#include "common.h"

typedef union {
  void *ptr;
  size_t val;
} ptrval;

void
_JIT_ENTRY(void ** stack_ptr) {
  ptrval val = (ptrval)(stack_ptr--)[0];
  jl_value_t **ret = (jl_value_t **)(stack_ptr--)[0];
  void (*continuation)(void **) = (stack_ptr--)[0];
  *ret = jl_box_slotnumber(val.val);
  continuation(stack_ptr);
}

