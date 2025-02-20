#include "common.h"

void
_JIT_ENTRY(int prev_ip)
{
   PATCH_VALUE(int,           ip,         _JIT_IP);
   PATCH_VALUE(jl_value_t **, prev_state, _JIT_PREV_STATE);
   DEBUGSTMT("ast_pop_exception", prev_ip, ip);
   jl_task_t *ct = jl_current_task;
   size_t _prev_state = jl_unbox_ulong(*prev_state);
   jl_restore_excstack(ct, _prev_state);
   PATCH_JUMP(_JIT_CONT, ip);
}
