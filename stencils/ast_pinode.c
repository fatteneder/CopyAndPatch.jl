#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,     ip,  _JIT_IP);
   // TODO should be jl_value_t **, no?
   PATCH_VALUE(void **, val, _JIT_VAL);
   DEBUGSTMT("ast_pinode", F, ip);
   F->ssas[ip] = *val;
   PATCH_JUMP(_JIT_CONT, F, ip);
}
