#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip,    _JIT_IP); // 1-based
   PATCH_VALUE(int, hand_n_leave, _JIT_HAND_N_LEAVE);
   DEBUGSTMT("ast_leave", F, ip);
   jl_task_t *ct = jl_current_task;
   if (hand_n_leave > 0) {
      jl_handler_t *eh = ct->eh;
      while (--hand_n_leave > 0) {
         // pop GC frames for any skipped handlers
         ct->gcstack = eh->gcstack;
         eh = eh->prev;
      }
      F->exc_thrown = 0;
      jl_longjmp(eh->eh_ctx, 1);
   } else {
      SET_IP(F, ip);
      PATCH_JUMP(_JIT_CONT, F);
   }
}
