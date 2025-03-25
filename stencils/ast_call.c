#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,            ip,    _JIT_IP); // 1-based
   PATCH_VALUE(jl_value_t ***, args,  _JIT_ARGS);
   PATCH_VALUE(uint32_t,       nargs, _JIT_NARGS);
   DEBUGSTMT("ast_call", F, ip);
   jl_value_t **argv;
   JL_GC_PUSHARGS(argv, nargs);
   for (size_t i = 0; i < nargs; i++)
      argv[i] = *args[i];
   F->ssas[ip-1] = jl_apply(argv, nargs);
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, F, ip);
}
