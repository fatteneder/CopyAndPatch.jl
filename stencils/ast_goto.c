#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   DEBUGSTMT("ast_goto", F, ip);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
