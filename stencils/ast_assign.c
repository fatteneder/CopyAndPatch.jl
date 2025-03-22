#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,           ip,  _JIT_IP);
   PATCH_VALUE(jl_value_t **, val, _JIT_VAL);
   DEBUGSTMT("ast_assign", F, ip);
   F->ssas[ip] = *val;
   PATCH_JUMP(_JIT_CONT, F, ip);
}
