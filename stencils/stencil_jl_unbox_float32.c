
#include "common.h"

float
_JIT_ENTRY() {
  PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
  float val = jl_unbox_float32(_val);
  return val;
}

