#include "common.h"

void
_JIT_ENTRY(int prev_ip)
{
   DEBUGSTMT("ast_foreigncall", prev_ip);
   PATCH_VALUE(void ***,  args,      _JIT_ARGS);
   PATCH_VALUE(void **,   cargs,     _JIT_CARGS);
   PATCH_VALUE(void *,    cif,       _JIT_CIF);
   PATCH_VALUE(void *,    f,         _JIT_F);
   PATCH_VALUE(int,       ip,        _JIT_IP);
   PATCH_VALUE(int64_t *, iptrs,     _JIT_IPTRS);
   PATCH_VALUE(int64_t,   isptr_ret, _JIT_ISPTR_RET);
   PATCH_VALUE(uint32_t,  nargs,     _JIT_NARGS);
   PATCH_VALUE(void **,   ret,       _JIT_RET);
   jl_value_t **roots;
   JL_GC_PUSHARGS(roots, nargs);
   for (size_t i = 0; i < nargs; i++) {
      roots[i] = (jl_value_t *)*args[i];
      // Atm we store both isbits and non-isbits types in boxed forms,
      // i.e. args is actually a jl_value_t **.
      // But for ccalls we need to unbox those which are of non-pointer arg type.
      // For now we do this by simple dereferencing, although we should be using the unbox methods.
      // The proper fix would be to not store isbits types in boxed form, but instead
      // inline them or put the bits values into static_prms or so.
      if (iptrs[i]) {
         cargs[i] = (void *)args[i];
      } else {
         cargs[i] = (void *)*args[i];
      }
   }
   if ((int)isptr_ret)
      ffi_call((ffi_cif *)cif, f, (ffi_arg *)ret, cargs);
   else
      ffi_call((ffi_cif *)cif, f, (ffi_arg *)*ret, cargs);
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, ip);
}
