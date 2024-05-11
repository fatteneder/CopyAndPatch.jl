#include "common.h"

typedef union {
   uint64_t addr;
   uint32_t val;
} convert_val;

void
_JIT_ENTRY(int prev_ip) {
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(jl_value_t ***, args, _JIT_ARGS);
   PATCH_VALUE_AND_CONVERT(uint64_t, convert_val, nargs, _JIT_NARGS);
   PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
   // TODO What if nargs == 1?
   jl_value_t **argv;
   JL_GC_PUSHARGS(argv, nargs.val);
   for (size_t i = 0; i < nargs.val; i++)
       argv[i] = *(args[i]);
   *ret = jl_new_structv((jl_datatype_t *)argv[0], &argv[1], nargs.val-1);
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, ip);
}
