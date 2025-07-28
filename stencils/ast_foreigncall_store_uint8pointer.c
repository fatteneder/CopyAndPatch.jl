#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   PATCH_VALUE(jl_value_t *, ty, _JIT_TY);
   DEBUGSTMT("ast_foreigncall_store_uint8pointer", F, ip);
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   F->ssas[ip-1] = jl_box_uint8pointer((uint8_t *)*rc);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
