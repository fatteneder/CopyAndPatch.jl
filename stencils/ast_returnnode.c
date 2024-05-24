#include "common.h"

void
_JIT_ENTRY(int prev_ip)
{
   DEBUGSTMT("ast_returnnode", prev_ip);
   PATCH_VALUE(jl_value_t **, val, _JIT_VAL);
   PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
   *ret = *val;
   return;
}
