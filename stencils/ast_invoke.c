#include "common.h"

void
_JIT_ENTRY(int prev_ip)
{
   DEBUGSTMT("ast_invoke", prev_ip);
   PATCH_VALUE(jl_value_t ***, args,    _JIT_ARGS);
   PATCH_VALUE(int,            ip,      _JIT_IP);
   PATCH_VALUE(uint32_t,       nargs,   _JIT_NARGS);
   PATCH_VALUE(jl_value_t **,  ret,     _JIT_RET);
   PATCH_VALUE(int,            retused, _JIT_RETUSED);
   jl_method_instance_t *meth = (jl_method_instance_t*)(*(args[0]));
   assert(jl_is_method_instance(meth));
   jl_value_t **argv;
   JL_GC_PUSHARGS(argv, nargs-1);
   for (size_t i = 1; i < nargs; i++)
      argv[i-1] = *(args[i]);
   jl_value_t *_ret = jl_invoke(argv[0], nargs == 2 ? NULL : &argv[1], nargs-2, meth);
   JL_GC_POP();
   if (retused)
      *ret = _ret;
   PATCH_JUMP(_JIT_CONT, ip);
}
