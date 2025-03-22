#include "common.h"
#include "julia_internal.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,            ip,    _JIT_IP);
   PATCH_VALUE(jl_value_t ***, args,  _JIT_ARGS);
   PATCH_VALUE(uint32_t,       nargs, _JIT_NARGS);
   DEBUGSTMT("ast_invoke", F, ip);
   jl_value_t **argv;
   JL_GC_PUSHARGS(argv, nargs-1);
   for (size_t i = 1; i < nargs; i++)
      argv[i-1] = *args[i];
   jl_value_t *c = *args[0];
   assert(jl_is_code_instance(c) || jl_is_method_instance(c));
   if (jl_is_code_instance(c)) {
      jl_code_instance_t *codeinst = (jl_code_instance_t*)c;
      assert(jl_atomic_load_relaxed(&codeinst->min_world) <= jl_current_task->world_age &&
             jl_current_task->world_age <= jl_atomic_load_relaxed(&codeinst->max_world));
      jl_callptr_t invoke = jl_atomic_load_acquire(&codeinst->invoke);
      if (!invoke) {
         jl_compile_codeinst(codeinst);
         invoke = jl_atomic_load_acquire(&codeinst->invoke);
      }
      if (invoke) {
         F->ssas[ip] = invoke(argv[0], &argv[1], nargs-2, codeinst);
      } else {
         if (codeinst->owner != jl_nothing) {
            jl_error("Failed to invoke or compile external codeinst");
         }
         F->ssas[ip] = jl_invoke(argv[0], &argv[1], nargs-2, jl_get_ci_mi(codeinst));
      }
   } else {
      F->ssas[ip] = jl_invoke(argv[0], &argv[1], nargs-2, (jl_method_instance_t*)c);
   }
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, F, ip);
}
