
#include "common.h"

uint16_t
_JIT_ENTRY() {
  PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
  uint16_t val = jl_unbox_uint16(_val);
  return val;
}

