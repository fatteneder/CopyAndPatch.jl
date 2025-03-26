#include "common.h"
#include "julia.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(jl_globalref_t *, gr, _JIT_GR);
   DEBUGSTMT("jl_eval_and_push_globalref", F, ip);
   jl_value_t *v = jl_get_globalref_value(gr);
   if (v == NULL)
       jl_undefined_var_error(gr->name, (jl_value_t*)gr->mod);
   F->tmps[i-1] = v;
   // push operations don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
