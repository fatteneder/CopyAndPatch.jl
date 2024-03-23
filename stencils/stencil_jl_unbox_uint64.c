
#include "common.h"

uint64_t
_JIT_ENTRY() {
  PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
  uint64_t val = jl_unbox_uint64(_val);
  return val;
}

