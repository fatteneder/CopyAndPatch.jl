#include "common.h"
#include "julia_internal.h"
#include <stdio.h>

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("ast_enternode", F, ip);
   printf("YEAYEAY\n");
   jl_value_t *scope = F->tmps[0];
   jl_handler_t __eh;
   jl_task_t *ct = jl_current_task;
   jl_enter_handler(ct, &__eh);
   F->ssas[ip-1] = jl_box_ulong(jl_excstack_state(ct));
   F->exc_thrown = 1; // needs to be reset by a :leave
   printf("SERS OIDA VODA????\n");
   printf("scope = %p\n", scope);
   if (scope) {
      JL_GC_PUSH1(&scope);
      ct->scope = scope;
      if (!jl_setjmp(__eh.eh_ctx, 1)) {
         ct->eh = &__eh;
         // can't use PATCH_JUMP here, because it returns and makes subsequent longjmp calls UB
         SET_IP(F, ip);
         PATCH_JUMP(_JIT_CALL, F);
         jl_unreachable();
      }
      JL_GC_POP();
   }
   else {
      if (!jl_setjmp(__eh.eh_ctx, 1)) {
         // can't use PATCH_JUMP here, because it returns and makes subsequent longjmp calls UB
         printf("SERS OIDA VODA????\n");
         SET_IP(F, ip);
         PATCH_JUMP(_JIT_CALL, F);
         jl_unreachable();
      }
   }
   jl_eh_restore_state(ct, &__eh);
   if (!(F->exc_thrown)) {
      jl_eh_restore_state_noexcept(ct, &__eh);
      SET_IP(F, ip);
      PATCH_JUMP(_JIT_CONT_LEAVE, F);
   } else {
      jl_eh_restore_state(ct, &__eh);
      SET_IP(F, ip);
      PATCH_JUMP(_JIT_CONT_CATCH, F);
   }
}
