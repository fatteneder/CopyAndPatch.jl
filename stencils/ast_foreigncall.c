#include "common.h"
#include "julia_internal.h" // for jl_bitcast
#include "juliahelpers.h"
#include <alloca.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h> // memcpy

#define UNBOX_AND_STORE(dest, src, ctype, jl_unbox)       \
   ctype val = (jl_unbox)((src));           \
   (dest) = alloca(sizeof(ctype));                        \
   memcpy((dest), &val, sizeof(ctype))

#define CONVERT_AND_BOX(dest, src, ctype, jl_box)         \
   typedef union { void *p; ctype v; } converter_##ctype; \
   converter_##ctype c; c.p = (void *)src;                \
   (dest) = (jl_box)(c.v)

JIT_ENTRY()
{
   PATCH_VALUE(int,          ip,          _JIT_IP); // 1-based
   PATCH_VALUE(int *,        argtypes,    _JIT_ARGTYPES);
   PATCH_VALUE(int *,        sz_argtypes, _JIT_SZARGTYPES);
   PATCH_VALUE(void *,       cif,         _JIT_CIF);
   PATCH_VALUE(int,          rettype,     _JIT_RETTYPE);
   PATCH_VALUE(jl_value_t *, rettype_ptr, _JIT_RETTYPEPTR);
   PATCH_VALUE(void *,       ffi_retval,  _JIT_FFIRETVAL);
   PATCH_VALUE(uint32_t,     nargs,       _JIT_NARGS);
   DEBUGSTMT("ast_foreigncall", F, ip);
   jl_value_t **args = F->tmps;
   void *cargs[nargs];
   for (int i = 0; i < nargs; i++) {
      // Atm we store both isbits and non-isbits types in boxed forms,
      // i.e. args is actually a jl_value_t **.
      // But for ccalls we need to unbox those which are of non-pointer arg type.
      // The proper way to it would be to not store isbits types in boxed form, but instead
      // inline them or put the bits values into static_prms or so.
      switch (argtypes[i]) {
         case -2: { cargs[i] = alloca(sz_argtypes[i]);
                    memcpy(cargs[i], args[i], sz_argtypes[i]);                      } break;
         case -1: { cargs[i] = (void *)&args[i];                                    } break;
         case 0:  { UNBOX_AND_STORE(cargs[i], args[i], bool,     jl_unbox_bool   ); } break;
         case 1:  { UNBOX_AND_STORE(cargs[i], args[i], int8_t,   jl_unbox_int8   ); } break;
         case 2:  { UNBOX_AND_STORE(cargs[i], args[i], uint8_t,  jl_unbox_uint8  ); } break;
         case 3:  { UNBOX_AND_STORE(cargs[i], args[i], int16_t,  jl_unbox_int16  ); } break;
         case 4:  { UNBOX_AND_STORE(cargs[i], args[i], uint16_t, jl_unbox_uint16 ); } break;
         case 5:  { UNBOX_AND_STORE(cargs[i], args[i], int32_t,  jl_unbox_int32  ); } break;
         case 6:  { UNBOX_AND_STORE(cargs[i], args[i], uint32_t, jl_unbox_uint32 ); } break;
         case 7:  { UNBOX_AND_STORE(cargs[i], args[i], int64_t,  jl_unbox_int64  ); } break;
         case 8:  { UNBOX_AND_STORE(cargs[i], args[i], uint64_t, jl_unbox_uint64 ); } break;
         case 9:  { UNBOX_AND_STORE(cargs[i], args[i], float,    jl_unbox_float32); } break;
         case 10: { UNBOX_AND_STORE(cargs[i], args[i], double,   jl_unbox_float64); } break;
         case 11: { cargs[i] = (void *)jl_unbox_uint8pointer((jl_value_t *)&args[i]); } break;
         case 12: { cargs[i] = (void *)jl_unbox_voidpointer((jl_value_t *)&args[i]);  } break;
         default: jl_error("ast_foreigncall: This should not have happened!");
      }
   }
   void *f = F->tmps[nargs];
   ffi_arg *rc = (ffi_arg*)ffi_retval;
   ffi_call((ffi_cif *)cif, f, rc, cargs);
   jl_value_t **ret = &F->ssas[ip-1];
   switch (rettype) {
      case -2: { // TODO This really needed?
                 *ret = jlh_convert_to_jl_value(rettype_ptr, (void *)rc);
               } break;
      case -1: { *ret = (jl_value_t *)*rc;                             } break;
      case 0:  { CONVERT_AND_BOX(*ret, *rc, int8_t,   jl_box_bool);    } break;
      case 1:  { CONVERT_AND_BOX(*ret, *rc, int8_t,   jl_box_int8);    } break;
      case 2:  { CONVERT_AND_BOX(*ret, *rc, uint8_t,  jl_box_uint8);   } break;
      case 3:  { CONVERT_AND_BOX(*ret, *rc, int16_t,  jl_box_int16);   } break;
      case 4:  { CONVERT_AND_BOX(*ret, *rc, uint16_t, jl_box_uint16);  } break;
      case 5:  { CONVERT_AND_BOX(*ret, *rc, int32_t,  jl_box_int32);   } break;
      case 6:  { CONVERT_AND_BOX(*ret, *rc, uint32_t, jl_box_uint32);  } break;
      case 7:  { CONVERT_AND_BOX(*ret, *rc, int64_t,  jl_box_int64);   } break;
      case 8:  { CONVERT_AND_BOX(*ret, *rc, uint64_t, jl_box_uint64);  } break;
      case 9:  { CONVERT_AND_BOX(*ret, *rc, float,    jl_box_float32); } break;
      case 10: { CONVERT_AND_BOX(*ret, *rc, double,   jl_box_float64); } break;
      case 11: { *ret = jl_box_uint8pointer((uint8_t *)*rc);           } break;
      case 12: { *ret = jl_box_voidpointer((void *)*rc);
                 if (rettype_ptr) *ret = jl_bitcast(rettype_ptr, *ret);
                 } break;
      default: jl_error("ast_foreigncall: This should not have happened!");
   }
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
