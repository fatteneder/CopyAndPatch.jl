#include "common.h"

typedef union {
   uint64_t addr;
   uint32_t val;
} convert_val;

void
_JIT_ENTRY(int prev_ip) {
   PATCH_VALUE(int,            ip,    _JIT_IP);
   PATCH_VALUE(void *,         cif,   _JIT_CIF);
   PATCH_VALUE(void *,         f,     _JIT_F);
   PATCH_VALUE(jl_value_t **,  ret,   _JIT_RET);
   PATCH_VALUE(jl_value_t ***, args,  _JIT_ARGS);
   PATCH_VALUE_AND_CONVERT(uint64_t, convert_val, nargs, _JIT_NARGS);
   JL_GC_PUSH1(*ret);
   {
      jl_value_t **argv;
      JL_GC_PUSHARGS(argv, nargs.val);
      for (size_t i = 0; i < nargs.val; i++)
         argv[i] = *(args[i]);
      ffi_call((ffi_cif *)cif, f, (ffi_arg *)(*ret), (void **)argv);
      JL_GC_POP();
   }
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, ip);
}
