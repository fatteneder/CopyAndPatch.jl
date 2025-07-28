#include "common.h"

// TODO Check if void * is legal here. Maybe we should uint64_t instead?
typedef union {
   void *p;
   uint8_t v;
} converter_uint8_t;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_tmps, _JIT_I_TMPS); // 1-based
   PATCH_VALUE(int, i_cargs, _JIT_I_CARGS); // 1-based
   PATCH_VALUE(int, i_mem, _JIT_I_MEM); // 1-based
   DEBUGSTMT("ast_foreigncall_load_uint8", F, ip);
   jl_value_t *val = F->tmps[i_tmps-1];
   converter_uint8_t c;
   c.v = jl_unbox_uint8(val);
   F->cargs[i_mem-1] = c.p;
   F->cargs[i_cargs-1] = &F->cargs[i_mem-1];
   // loads don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
