#include "common.h"

typedef union {
   uint64_t addr;
   uint32_t val;
} convert_val;

void
_JIT_ENTRY(int ip) {
   PATCH_VALUE(jl_value_t **, args, _JIT_ARGS);
   PATCH_VALUE_AND_CONVERT(uint64_t, convert_val, nargs, _JIT_NARGS);
   PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
   // TODO What if nargs == 1?
   *ret = jl_new_structv((jl_datatype_t *)args[0], &args[1], nargs.val-1);
   PATCH_JUMP(_JIT_CONT, ip+1);
}
