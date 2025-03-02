#include "common.h"

// JL_CALLABLE(_JIT_ENTRY)
jl_value_t *
_JIT_ENTRY(jl_value_t *F, jl_value_t **args, uint32_t nargs, jl_code_instance_t *ci)
{
   PATCH_VALUE(jl_value_t **, slots,      _JIT_SLOTS);
   PATCH_VALUE(jl_value_t **, ssas,       _JIT_SSAS);
   PATCH_VALUE(int *,         phioffset,  _JIT_PHIOFFSET);
   int prev_ip = -1, ip = 0;
   DEBUGSTMT("abi", prev_ip, ip);
   slots[0] = F;
   // when called from julia's invoke then args is a genuine jl_value_t ** array
   if (!jl_is_datatype(jl_typeof((jl_value_t *)args))) {
      for (int i = 0; i < (int)nargs; i++) {
         slots[i+1] = args[i];
      }
   }
   // when called from src/machinecode.jl we just forward the tuple of vargs to here
   else if (jl_is_tuple((jl_value_t *)args)) {
      for (int i = 0; i < (int)nargs; i++) {
         slots[i+1] = jl_fieldref(args, i);
      }
   }
   else {
      jl_errorf("abi stencil: encountered %s when converting args to slots",
                jl_typeof_str((jl_value_t*)args));
   }
   *phioffset = 0;
   extern int _JIT_STENCIL(int);
   int ret_ip = _JIT_STENCIL(ip);
   jl_value_t *ret = ssas[ret_ip-1];
   return ret;
}
