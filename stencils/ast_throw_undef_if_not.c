#include "common.h"
#include "julia_internal.h" // for jl_getfield_undefref_sym, jl_local_sym
#include "julia_threads.h"  // for julia_internal.h

JIT_ENTRY()
{
   PATCH_VALUE(int,           ip,   _JIT_IP);
   PATCH_VALUE(jl_value_t **, cond, _JIT_COND);
   PATCH_VALUE(jl_sym_t **,   var,  _JIT_VAR);
   DEBUGSTMT("ast_throw_undef_if_not", F, ip);
   assert(jl_is_bool(*cond));
   if (*cond == jl_false) {
      if (*var == jl_getfield_undefref_sym)
         jl_throw(jl_undefref_exception);
      else
         jl_undefined_var_error(*var, (jl_value_t*)jl_local_sym);
   }
   F->ssas[ip] = jl_nothing;
   PATCH_JUMP(_JIT_CONT, F, ip);
}
