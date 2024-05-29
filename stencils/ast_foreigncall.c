#include "common.h"
#include <julia_internal.h> // for jl_bitcast
#include <julia_threads.h>  // for julia_internal.h

void
_JIT_ENTRY(int prev_ip)
{
   DEBUGSTMT("ast_foreigncall", prev_ip);
   PATCH_VALUE(void ***,     args,        _JIT_ARGS);
   PATCH_VALUE(void ***,     cargs,       _JIT_CARGS);
   PATCH_VALUE(void *,       cif,         _JIT_CIF);
   PATCH_VALUE(void *,       f,           _JIT_F);
   PATCH_VALUE(int,          ip,          _JIT_IP);
   PATCH_VALUE(int *,        argtypes,    _JIT_ARGTYPES);
   PATCH_VALUE(int,          rettype,     _JIT_RETTYPE);
   PATCH_VALUE(jl_value_t *, rettype_ptr, _JIT_RETTYPE_PTR);
   PATCH_VALUE(uint32_t,     nargs,       _JIT_NARGS);
   PATCH_VALUE(void **,      ret,         _JIT_RET);
   for (int i = 0; i < nargs; i++) {
      // Atm we store both isbits and non-isbits types in boxed forms,
      // i.e. args is actually a jl_value_t **.
      // But for ccalls we need to unbox those which are of non-pointer arg type.
      // The proper way to it would be to not store isbits types in boxed form, but instead
      // inline them or put the bits values into static_prms or so.
      switch (argtypes[i]) {
         case -1: cargs[i] = (void **)args[i]; /* jl_value_t ** */ break;
         case 0:  cargs[i] = (void *)(uint64_t)jl_unbox_bool((jl_value_t *)args[i]); break;
         case 1:  cargs[i] = (void *)(uint64_t)jl_unbox_int8((jl_value_t *)args[i]); break;
         case 2:  cargs[i] = (void *)(uint64_t)jl_unbox_uint8((jl_value_t *)args[i]); break;
         case 3:  cargs[i] = (void *)(uint64_t)jl_unbox_int16((jl_value_t *)args[i]); break;
         case 4:  cargs[i] = (void *)(uint64_t)jl_unbox_uint16((jl_value_t *)args[i]); break;
         case 5:  cargs[i] = (void *)(uint64_t)jl_unbox_int32((jl_value_t *)args[i]); break;
         case 6:  cargs[i] = (void *)(uint64_t)jl_unbox_uint32((jl_value_t *)args[i]); break;
         case 7:  cargs[i] = (void *)(uint64_t)jl_unbox_int64((jl_value_t *)args[i]); break;
         case 8:  cargs[i] = (void *)(uint64_t)jl_unbox_uint64((jl_value_t *)args[i]); break;
         case 9:  cargs[i] = (void *)(uint64_t)jl_unbox_float32((jl_value_t *)args[i]); break;
         case 10: cargs[i] = (void *)(uint64_t)jl_unbox_float64((jl_value_t *)args[i]); break;
         case 11: cargs[i] = (void *)(uint64_t)jl_unbox_uint8pointer((jl_value_t *)args[i]); break;
         case 12: cargs[i] = (void *)(uint64_t)jl_unbox_voidpointer((jl_value_t *)args[i]); break;
         default: jl_error("ast_foreigncall: This should not have happened!");
      }
   }
   ffi_arg rc;
   ffi_call((ffi_cif *)cif, f, &rc, (void **)cargs);
   switch (rettype) {
      case -1: *ret  = (void *)rc; // jl_value_t *
      case 0:  *ret = (void *)jl_box_bool((int8_t)rc); break;
      case 1:  *ret = (void *)jl_box_int8((int8_t)rc); break;
      case 2:  *ret = (void *)jl_box_uint8((uint8_t)rc); break;
      case 3:  *ret = (void *)jl_box_int16((int16_t)rc); break;
      case 4:  *ret = (void *)jl_box_uint16((uint16_t)rc); break;
      case 5:  *ret = (void *)jl_box_int32((int32_t)rc); break;
      case 6:  *ret = (void *)jl_box_uint32((uint32_t)rc); break;
      case 7:  *ret = (void *)jl_box_int64((int64_t)rc); break;
      case 8:  *ret = (void *)jl_box_uint64((uint64_t)rc); break;
      case 9:  *ret = (void *)jl_box_float32((float)rc); break;
      case 10: *ret = (void *)jl_box_float64((double)rc); break;
      case 11: *ret = (void *)jl_box_uint8pointer((uint8_t *)rc); break;
      case 12: { *ret = (void *)jl_box_voidpointer((void *)rc);
                 if (rettype_ptr) {
                     *ret = (void **)jl_bitcast(rettype_ptr, (jl_value_t *)*ret);
                 }
               } break;
      default: jl_error("ast_foreigncall: This should not have happened!");
   }
   PATCH_JUMP(_JIT_CONT, ip);
}
