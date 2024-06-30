#include "common.h"

void
_JIT_ENTRY(int prev_ip)
{
   PATCH_VALUE(int,    ip,         _JIT_IP);
   PATCH_VALUE(size_t, prev_state, _JIT_PREV_STATE);
   DEBUGSTMT("ast_pop_exception", prev_ip, ip);
   jl_restore_excstack(prev_state);
   PATCH_JUMP(_JIT_CONT, ip);
}
