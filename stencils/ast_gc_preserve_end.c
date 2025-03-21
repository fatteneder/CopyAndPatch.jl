#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,           ip,  _JIT_IP);
   PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
   DEBUGSTMT("ast_gc_perserve_end", prev_ip, ip);
   *ret = jl_nothing;
   PATCH_JUMP(_JIT_CONT, ip);
}
