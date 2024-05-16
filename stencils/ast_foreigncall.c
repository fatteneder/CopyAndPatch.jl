#include "common.h"

void
_JIT_ENTRY(int prev_ip) {
   PATCH_VALUE(jl_value_t ***, args,    _JIT_ARGS);
   PATCH_VALUE(void *,         cif,     _JIT_CIF);
   PATCH_VALUE(void *,         f,       _JIT_F);
   PATCH_VALUE(int,            ip,      _JIT_IP);
   PATCH_VALUE(uint32_t,       nargs,   _JIT_NARGS);
   PATCH_VALUE(jl_value_t **,  ret,     _JIT_RET);
   JL_GC_PUSH1(*ret);
   {
      jl_value_t **argv;
      JL_GC_PUSHARGS(argv, nargs);
      for (size_t i = 0; i < nargs; i++)
         argv[i] = *(args[i]);
      ffi_call((ffi_cif *)cif, f, (ffi_arg *)(*ret), (void **)argv);
      // TODO This does not work, because retused is optimized away for >= O1. Why?
      /** ffi_arg *_ret; */
      /** ffi_call((ffi_cif *)cif, f, _ret, (void **)argv); */
      /** PATCH_VALUE(int, retused, _JIT_RETUSED); */
      /** if (retused) */
      /**    *ret = (jl_value_t *)_ret; */
      JL_GC_POP();
   }
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, ip);
}
