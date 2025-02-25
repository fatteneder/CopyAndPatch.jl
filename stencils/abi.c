#include "common.h"

// JL_CALLABLE(_JIT_ENTRY)
jl_value_t *
_JIT_ENTRY(jl_value_t *F, jl_value_t **args, uint32_t nargs)
{
   PATCH_VALUE(jl_value_t **, slots,      _JIT_SLOTS);
   PATCH_VALUE(jl_value_t **, ssas,       _JIT_SSAS);
   PATCH_VALUE(int *,         phioffset,  _JIT_PHIOFFSET);
   int prev_ip = -1, ip = 0;
   DEBUGSTMT("abi", prev_ip, ip);
   slots[0] = F;
   for (int i = 0; i < (int)nargs; i++) {
      slots[i+1] = jl_fieldref(args, i);
   }
   *phioffset = 0;
   extern int _JIT_STENCIL(int);
   int ret_ip = _JIT_STENCIL(ip);
   jl_value_t *ret = ssas[ret_ip-1];
   return ret;
}
