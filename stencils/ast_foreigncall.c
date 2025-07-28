#include "common.h"
#include <alloca.h>
#include <stdbool.h>
#include <stdint.h>

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   PATCH_VALUE(void *, cif, _JIT_CIF);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   DEBUGSTMT("ast_foreigncall", F, ip);
   void *f = (void *)F->tmps[0];
   void **cargs = &F->cargs[0];
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   ffi_call((ffi_cif *)cif, f, rc, cargs);
   PATCH_JUMP(_JIT_CONT, F);
}
