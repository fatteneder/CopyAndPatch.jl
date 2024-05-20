#include "common.h"

void
_JIT_ENTRY(int prev_ip) {
   PATCH_VALUE(void ***, args,      _JIT_ARGS);
   PATCH_VALUE(void *,   cif,       _JIT_CIF);
   PATCH_VALUE(void *,   f,         _JIT_F);
   PATCH_VALUE(int,      ip,        _JIT_IP);
   PATCH_VALUE(int64_t,  isptr_ret, _JIT_ISPTR_RET);
   PATCH_VALUE(uint32_t, nargs,     _JIT_NARGS);
   PATCH_VALUE(void **,  ret,       _JIT_RET);
   // TODO Found that when I don't properly type cast isptr_ret below,
   // then it is optimized away. Might this be the same reason as to why
   // the pointers where optimized away in other stencils?
   {
      jl_value_t **argv;
      JL_GC_PUSHARGS(argv, nargs+1);
      argv[0] = *ret;
      for (size_t i = 0; i < nargs; i++)
         argv[i+1] = *(args[i]);
      // TODO Why do we have to distinguish types for ret, but not for args?
      void *rc;
      if ((int)isptr_ret)
         rc = (void *)ret;
      else
         rc = (void *)*ret;
      ffi_call((ffi_cif *)cif, f, (ffi_arg *)rc, (void **)(&argv[1]));
      JL_GC_POP();
   }
   PATCH_JUMP(_JIT_CONT, ip);
}
