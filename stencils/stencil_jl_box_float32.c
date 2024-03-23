
#include "common.h"

jl_value_t *
_JIT_ENTRY() {
  PATCH_VALUE(float, _val, _JIT_ARG);
  jl_value_t *val = jl_box_float32(_val);
  return val;
}

