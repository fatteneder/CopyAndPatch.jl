#include "common.h"
#include "julia_internal.h" // for jl_getfield_undefref_sym, jl_local_sym

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("ast_throw_undef_if_not", F, ip);
   jl_sym_t *var = (jl_sym_t *)F->tmps[0];
   jl_value_t *cond = F->tmps[1];
   assert(jl_is_bool(cond));
   if (cond == jl_false) {
      if (var == jl_getfield_undefref_sym)
         jl_throw(jl_undefref_exception);
      else
         jl_undefined_var_error(var, (jl_value_t*)jl_local_sym);
   }
   F->ssas[ip-1] = jl_nothing;
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
