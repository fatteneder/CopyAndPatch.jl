#include "common.h"
#include "julia.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(jl_value_t ** , g, _JIT_G);
   DEBUGSTMT("jl_eval_and_push_globalref", F, ip);
   jl_globalref_t *gr = (jl_globalref_t *)*g;
   jl_value_t *v = jl_get_globalref_value(gr);
   if (v == NULL)
       jl_undefined_var_error(gr->name, (jl_value_t*)gr->mod);
   F->tmps[i-1] = v;
   PATCH_JUMP(_JIT_CONT, F, ip);
}
