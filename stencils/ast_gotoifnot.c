#include "common.h"

void
_JIT_ENTRY(int prev_ip)
{
   DEBUGSTMT("ast_gotoifnot", prev_ip);
   PATCH_VALUE(int,           ip,   _JIT_IP);
   PATCH_VALUE(jl_value_t **, test, _JIT_TEST);
   if (*test == jl_false) {
      PATCH_JUMP(_JIT_CONT1, ip);
   } else if (*test != jl_true) {
      jl_type_error("if", (jl_value_t*)jl_bool_type, *test /*JL_MAYBE_UNROOTED*/);
   }
   PATCH_JUMP(_JIT_CONT2, ip);
}
