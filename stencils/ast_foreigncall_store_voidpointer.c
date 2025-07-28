#include "common.h"
#include <julia_threads.h> // for julia_internal.h
#include <julia_internal.h> // jl_gc_alloc

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   PATCH_VALUE(jl_value_t *, ty, _JIT_TY);
   DEBUGSTMT("ast_foreigncall_store_voidpointer", F, ip);
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   jl_value_t *ret = jl_box_voidpointer((void *)*rc);
   if (ty) ret = jl_bitcast(ty, ret);
   F->ssas[ip-1] = ret;
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
