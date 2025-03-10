#include "common.h"
#include "julia_internal.h" // asan_unpoison_task_stack

JIT_ENTRY(prev_ip)
{
   PATCH_VALUE(int,   ip,           _JIT_IP);
   PATCH_VALUE(int,   hand_n_leave, _JIT_HAND_N_LEAVE);
   PATCH_VALUE(int *, exc_thrown,   _JIT_EXC_THROWN);
   DEBUGSTMT("ast_leave", prev_ip, ip);
   jl_task_t *ct = jl_current_task;
   if (hand_n_leave > 0) {
      jl_handler_t *eh = ct->eh;
      while (--hand_n_leave > 0) {
         // pop GC frames for any skipped handlers
         ct->gcstack = eh->gcstack;
         eh = eh->prev;
      }
      *exc_thrown = 0;
      asan_unpoison_task_stack(ct, &eh->eh_ctx);
      jl_longjmp(eh->eh_ctx, 1);
   } else {
      PATCH_JUMP(_JIT_CONT, ip);
   }
}
