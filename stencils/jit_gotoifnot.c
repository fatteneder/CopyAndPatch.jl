#include "common.h"

void
_JIT_ENTRY(int ip) {
   PATCH_VALUE(jl_value_t *, test, _JIT_TEST);
   if (test == jl_false)
      PATCH_JUMP(_JIT_CONT1, ip+1);
   else if (test != jl_true)
      jl_type_error("if", (jl_value_t*)jl_bool_type, test);
   PATCH_JUMP(_JIT_CONT2, ip+1);
}
