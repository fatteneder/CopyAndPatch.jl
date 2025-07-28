#include "common.h"
#include <julia_threads.h> // for julia_internal.h
#include <julia_internal.h> // jl_gc_alloc

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   PATCH_VALUE(jl_value_t *, ty, _JIT_TY);
   DEBUGSTMT("ast_foreigncall_store_concretetype", F, ip);
   // printf("SERS OIDA\n");
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   jl_task_t *ct = jl_get_current_task();
   size_t sz = jl_datatype_size(ty);
   jl_value_t *v = jl_gc_alloc(ct->ptls, sz, ty);
   jl_set_typeof(v, ty);
   memcpy((void *)v, (void *)rc, sz);
   F->ssas[ip-1] = v;
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
