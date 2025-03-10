#include "common.h"

JIT_ENTRY(prev_ip)
{

   PATCH_VALUE(int,           ip,  _JIT_IP);
   PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
   DEBUGSTMT("ast_inline", prev_ip, ip);
   *ret = jl_nothing;
   PATCH_JUMP(_JIT_CONT, ip);
}
