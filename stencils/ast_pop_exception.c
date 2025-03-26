#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,           ip,         _JIT_IP); // 1-based
   PATCH_VALUE(jl_value_t **, prev_state, _JIT_PREV_STATE);
   DEBUGSTMT("ast_pop_exception", F, ip);
   jl_task_t *ct = jl_current_task;
   size_t _prev_state = jl_unbox_ulong(*prev_state);
   jl_restore_excstack(ct, _prev_state);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
