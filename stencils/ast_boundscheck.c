#include "common.h"

void
_JIT_ENTRY(int prev_ip)
{
   PATCH_VALUE(int,     ip,  _JIT_IP);
   PATCH_VALUE(void **, ret, _JIT_RET);
   PATCH_VALUE(void **, val, _JIT_VAL);
   DEBUGSTMT("ast_boundscheck", prev_ip, ip);
   *ret = *val;
   PATCH_JUMP(_JIT_CONT, ip);
}