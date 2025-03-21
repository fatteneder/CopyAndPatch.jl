#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,           ip,  _JIT_IP);
   PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
   PATCH_VALUE(jl_value_t **, val, _JIT_VAL);
   DEBUGSTMT("ast_assign", prev_ip, ip);
   *ret = *val;
   PATCH_JUMP(_JIT_CONT, ip);
}
