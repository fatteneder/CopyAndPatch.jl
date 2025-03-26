#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,           ip,   _JIT_IP); // 1-based
   DEBUGSTMT("ast_gotoifnot", F, ip);
   jl_value_t *test = F->tmps[0];
   if (test == jl_false) {
      SET_IP(F, ip);
      PATCH_JUMP(_JIT_CONT1, F);
   } else if (test != jl_true) {
      jl_type_error("if", (jl_value_t*)jl_bool_type, test /*JL_MAYBE_UNROOTED*/);
   }
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT2, F);
}
