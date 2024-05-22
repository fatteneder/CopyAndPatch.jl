#include "common.h"

jl_value_t *
_JIT_ENTRY(int prev_ip)
{
   DEBUGSTMT("ast_returnnode", prev_ip);
   PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
   return (ret) ? *ret : NULL;
}
