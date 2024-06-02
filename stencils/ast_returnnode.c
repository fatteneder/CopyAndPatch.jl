#include "common.h"

int
_JIT_ENTRY(int prev_ip)
{
   PATCH_VALUE(int,           ip,  _JIT_IP);
   PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
   PATCH_VALUE(jl_value_t **, val, _JIT_VAL);
   DEBUGSTMT("ast_returnnode", prev_ip, ip);
   *ret = *val;
   return ip;
}
