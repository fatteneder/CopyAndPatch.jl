#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,     ip,  _JIT_IP);
   PATCH_VALUE(void **, ret, _JIT_RET);
   DEBUGSTMT("ast_boundscheck", prev_ip, ip);
   *ret = jl_true;
   PATCH_JUMP(_JIT_CONT, ip);
}
