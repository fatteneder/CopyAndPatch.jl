#include "common.h"
#include "julia_internal.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,   ip,         _JIT_IP);
   PATCH_VALUE(int *, exc_thrown, _JIT_EXC_THROWN);
   PATCH_VALUE(jl_value_t *,  scope, _JIT_SCOPE);
   PATCH_VALUE(jl_value_t **, ret,       _JIT_RET);
   DEBUGSTMT("ast_enternode", prev_ip, ip);
   jl_handler_t __eh;
   jl_task_t *ct = jl_current_task;
   jl_enter_handler(ct, &__eh);
   *ret = jl_box_ulong(jl_excstack_state(ct));
   *exc_thrown = 1; // needs to be reset by a :leave
   if (scope) {
      JL_GC_PUSH1(&scope);
      ct->scope = scope;
      if (!jl_setjmp(__eh.eh_ctx, 1)) {
         ct->eh = &__eh;
         // can't use PATCH_JUMP here, because it returns and makes subsequent longjmp calls UB
         PATCH_CALL(_JIT_CALL, ip);
         jl_unreachable();
      }
      JL_GC_POP();
   }
   else {
      if (!jl_setjmp(__eh.eh_ctx, 1)) {
         // can't use PATCH_JUMP here, because it returns and makes subsequent longjmp calls UB
         PATCH_CALL(_JIT_CALL, ip);
         jl_unreachable();
      }
   }
   jl_eh_restore_state(ct, &__eh);
   if (!(*exc_thrown)) {
      jl_eh_restore_state_noexcept(ct, &__eh);
      PATCH_JUMP(_JIT_CONT_LEAVE, ip);
   } else {
      jl_eh_restore_state(ct, &__eh);
      PATCH_JUMP(_JIT_CONT_CATCH, ip);
   }
}
