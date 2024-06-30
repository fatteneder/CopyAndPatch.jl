#include "common.h"

void
_JIT_ENTRY(int prev_ip)
{
   PATCH_VALUE(int,            ip,   _JIT_IP);
   PATCH_VALUE(jl_value_t **,  ret,  _JIT_RET);
   PATCH_VALUE(jl_value_t **,  val,  _JIT_VAL);
   DEBUGSTMT("ast_upsilonnode", prev_ip, ip);
   if (*val)
      *ret = *val;
   else
      *ret = NULL;
   PATCH_JUMP(_JIT_CONT, ip);
}
