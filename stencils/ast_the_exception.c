#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
   DEBUGSTMT("ast_the_exception", F, ip);
   *ret = jl_current_exception(jl_current_task);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
