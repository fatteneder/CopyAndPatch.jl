#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_tmps, _JIT_I_TMPS); // 1-based
   PATCH_VALUE(int, i_cargs, _JIT_I_CARGS); // 1-based
   PATCH_VALUE(int, i_mem, _JIT_I_MEM); // 1-based
   jl_value_t *val = F->tmps[i_tmps-1];
   DEBUGSTMT("ast_foreigncall_load_any", F, ip);
   // F->cargs[i_mem-1] = (void *)&F->tmps[i_tmps-1];
   // F->cargs[i_cargs-1] = F->cargs[i_mem-1];
   F->cargs[i_cargs-1] = (void *)&F->tmps[i_tmps-1];
   // loads don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
