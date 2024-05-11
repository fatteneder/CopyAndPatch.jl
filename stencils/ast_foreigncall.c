#include "common.h"

void
_JIT_ENTRY(int prev_ip) {
   PATCH_VALUE(int,     ip,   _JIT_IP);
   PATCH_VALUE(void *,  cif,  _JIT_CIF);
   PATCH_VALUE(void *,  f,    _JIT_F);
   PATCH_VALUE(void **, ret,  _JIT_RET);
   PATCH_VALUE(void **, args, _JIT_ARGS);
   ffi_call((ffi_cif *)cif, f, (ffi_arg *)(*ret), (*args));
   PATCH_JUMP(_JIT_CONT, ip);
}
