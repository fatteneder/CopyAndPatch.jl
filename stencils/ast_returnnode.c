#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,           ip,  _JIT_IP);
   PATCH_VALUE(jl_value_t **, val, _JIT_VAL);
   DEBUGSTMT("ast_returnnode", F, ip);
   F->ssas[ip] = *val;
   F->ip = ip;
   return;
}
