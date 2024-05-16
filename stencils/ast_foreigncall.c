#include "common.h"

void
_JIT_ENTRY(int prev_ip) {
   PATCH_VALUE(int,            ip,    _JIT_IP);
   PATCH_VALUE(void *,         cif,   _JIT_CIF);
   PATCH_VALUE(void *,         f,     _JIT_F);
   PATCH_VALUE(jl_value_t **,  ret,   _JIT_RET);
   PATCH_VALUE(jl_value_t ***, args,  _JIT_ARGS);
   PATCH_VALUE(uint32_t, nargs, _JIT_NARGS);
   JL_GC_PUSH1(*ret);
   {
      jl_value_t **argv;
      JL_GC_PUSHARGS(argv, nargs);
      for (size_t i = 0; i < nargs; i++)
         argv[i] = *(args[i]);
      ffi_call((ffi_cif *)cif, f, (ffi_arg *)(*ret), (void **)argv);
      JL_GC_POP();
   }
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, ip);
}
