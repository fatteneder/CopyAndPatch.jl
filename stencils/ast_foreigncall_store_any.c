#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   DEBUGSTMT("ast_foreigncall_store_any", F, ip);
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   F->ssas[ip-1] = (jl_value_t *)*rc;
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
