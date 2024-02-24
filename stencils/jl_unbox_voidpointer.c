
#include "common.h"

void *
_JIT_ENTRY() {
  PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
  void * val = jl_unbox_voidpointer(_val);
  return val;
}

