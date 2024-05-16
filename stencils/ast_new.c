#include "common.h"

void
_JIT_ENTRY(int prev_ip) {
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(jl_value_t ***, args, _JIT_ARGS);
   PATCH_VALUE(uint32_t, nargs, _JIT_NARGS);
   PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
   // TODO What if nargs == 1?
   jl_value_t **argv;
   JL_GC_PUSHARGS(argv, nargs);
   for (size_t i = 0; i < nargs; i++)
       argv[i] = *(args[i]);
   *ret = jl_new_structv((jl_datatype_t *)argv[0], &argv[1], nargs-1);
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, ip);
}
