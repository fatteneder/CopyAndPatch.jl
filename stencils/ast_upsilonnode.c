#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,           ip,  _JIT_IP); // 1-based
   PATCH_VALUE(jl_value_t **, val, _JIT_VAL);
   DEBUGSTMT("ast_upsilonnode", F, ip);
   if (*val)
      F->ssas[ip-1] = *val;
   else
      F->ssas[ip-1] = NULL;
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
