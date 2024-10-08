#include "common.h"
#include <julia_internal.h>

void
_JIT_ENTRY(int prev_ip)
{
   PATCH_VALUE(int,   ip,         _JIT_IP);
   PATCH_VALUE(int *, exc_thrown, _JIT_EXC_THROWN);
   PATCH_VALUE(jl_value_t *,  new_scope, _JIT_NEW_SCOPE);
   PATCH_VALUE(jl_value_t **, ret,       _JIT_RET);
   DEBUGSTMT("ast_enternode", prev_ip, ip);
   jl_handler_t __eh;
   jl_task_t *ct = jl_current_task;
   jl_enter_handler(&__eh);
   *ret = jl_box_ulong(jl_excstack_state());
   *exc_thrown = 1; // needs to be reset by a :leave
   if (new_scope) {
      jl_value_t *old_scope = ct->scope;
      JL_GC_PUSH1(&old_scope);
      ct->scope = new_scope;
      if (!jl_setjmp(__eh.eh_ctx, 1)) {
         // can't use PATCH_JUMP here, because it returns and makes subsequent longjmp calls UB
         PATCH_CALL(_JIT_CALL, ip);
         jl_unreachable();
      }
      ct->scope = old_scope;
      JL_GC_POP();
   }
   else {
      if (!jl_setjmp(__eh.eh_ctx, 1)) {
         // can't use PATCH_JUMP here, because it returns and makes subsequent longjmp calls UB
         PATCH_CALL(_JIT_CALL, ip);
         jl_unreachable();
      }
   }
   jl_eh_restore_state(&__eh);
   if (!(*exc_thrown)) {
      PATCH_JUMP(_JIT_CONT_LEAVE, ip);
   } else {
      PATCH_JUMP(_JIT_CONT_CATCH, ip);
   }
}
