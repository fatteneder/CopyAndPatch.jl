#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,           ip,  _JIT_IP);
   PATCH_VALUE(jl_value_t **, val, _JIT_VAL);
   DEBUGSTMT("ast_upsilonnode", F, ip);
   if (*val)
      F->ssas[ip] = *val;
   else
      F->ssas[ip] = NULL;
   PATCH_JUMP(_JIT_CONT, F, ip);
}
