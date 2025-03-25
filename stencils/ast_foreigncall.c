#include "common.h"
#include <stdbool.h>
#include <string.h> // memcpy
#include "julia_internal.h" // for jl_bitcast
#include "juliahelpers.h"

#define UNBOX_AND_STORE(dest, src, ctype, jl_unbox)       \
   ctype val = (jl_unbox)((jl_value_t *)(src));           \
   memcpy((dest), &val, sizeof(ctype))

#define CONVERT_AND_BOX(dest, src, ctype, jl_box)         \
   typedef union { void *p; ctype v; } converter_##ctype; \
   converter_##ctype c; c.p = (void *)src;                \
   dest = (jl_box)(c.v)

JIT_ENTRY()
{
   PATCH_VALUE(int,          ip,          _JIT_IP);
   PATCH_VALUE(void ***,     args,        _JIT_ARGS);
   PATCH_VALUE(int *,        argtypes,    _JIT_ARGTYPES);
   PATCH_VALUE(int *,        sz_argtypes, _JIT_SZARGTYPES);
   PATCH_VALUE(void ***,     cargs,       _JIT_CARGS);
   PATCH_VALUE(void *,       cif,         _JIT_CIF);
   PATCH_VALUE(void *,       f,           _JIT_F);
   PATCH_VALUE(int,          static_f,    _JIT_STATICF);
   PATCH_VALUE(void ***,     gc_roots,    _JIT_GCROOTS);
   PATCH_VALUE(int,          n_gc_roots,  _JIT_NGCROOTS);
   PATCH_VALUE(int,          rettype,     _JIT_RETTYPE);
   PATCH_VALUE(jl_value_t *, rettype_ptr, _JIT_RETTYPEPTR);
   PATCH_VALUE(void *,       ffi_retval,  _JIT_FFIRETVAL);
   PATCH_VALUE(uint32_t,     nargs,       _JIT_NARGS);
   DEBUGSTMT("ast_foreigncall", F, ip);
   jl_value_t **roots;
   JL_GC_PUSHARGS(roots, n_gc_roots);
   for (int i = 0; i < n_gc_roots; i++)
      roots[i] = (jl_value_t*)*gc_roots[i];
   for (int i = 0; i < nargs; i++) {
      // Atm we store both isbits and non-isbits types in boxed forms,
      // i.e. args is actually a jl_value_t **.
      // But for ccalls we need to unbox those which are of non-pointer arg type.
      // The proper way to it would be to not store isbits types in boxed form, but instead
      // inline them or put the bits values into static_prms or so.
      switch (argtypes[i]) {
         case -2: memcpy(cargs[i], *args[i], sz_argtypes[i]); break;
         case -1: cargs[i] = (void **)args[i]; /* jl_value_t ** */ break;
         case 0:  { UNBOX_AND_STORE(cargs[i], *args[i], bool,     jl_unbox_bool   ); } break;
         case 1:  { UNBOX_AND_STORE(cargs[i], *args[i], int8_t,   jl_unbox_int8   ); } break;
         case 2:  { UNBOX_AND_STORE(cargs[i], *args[i], uint8_t,  jl_unbox_uint8  ); } break;
         case 3:  { UNBOX_AND_STORE(cargs[i], *args[i], int16_t,  jl_unbox_int16  ); } break;
         case 4:  { UNBOX_AND_STORE(cargs[i], *args[i], uint16_t, jl_unbox_uint16 ); } break;
         case 5:  { UNBOX_AND_STORE(cargs[i], *args[i], int32_t,  jl_unbox_int32  ); } break;
         case 6:  { UNBOX_AND_STORE(cargs[i], *args[i], uint32_t, jl_unbox_uint32 ); } break;
         case 7:  { UNBOX_AND_STORE(cargs[i], *args[i], int64_t,  jl_unbox_int64  ); } break;
         case 8:  { UNBOX_AND_STORE(cargs[i], *args[i], uint64_t, jl_unbox_uint64 ); } break;
         case 9:  { UNBOX_AND_STORE(cargs[i], *args[i], float,    jl_unbox_float32); } break;
         case 10: { UNBOX_AND_STORE(cargs[i], *args[i], double,   jl_unbox_float64); } break;
         case 11: cargs[i] = (void *)(uint64_t)jl_unbox_uint8pointer((jl_value_t *)args[i]); break;
         case 12: cargs[i] = (void *)(uint64_t)jl_unbox_voidpointer((jl_value_t *)args[i]); break;
         default: jl_error("ast_foreigncall: This should not have happened!");
      }
   }
   ffi_arg *rc = (ffi_arg*)ffi_retval;
   if (static_f)
      ffi_call((ffi_cif *)cif, f, rc, (void **)cargs);
   else
      ffi_call((ffi_cif *)cif, **(void ***)f, rc, (void **)cargs);
   void **ret = (void **)&F->ssas[ip];
   switch (rettype) {
      case -2: *ret = jlh_convert_to_jl_value(rettype_ptr, (void *)rc); break;
      case -1: *ret = (void *)*rc; break; // jl_value_t *
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
      // TODO Do we need a CONVERT_AND_BOX for the pointer cases too?
      case 11: *ret = (void *)jl_box_uint8pointer((uint8_t *)*rc); break;
      case 12: { *ret = (void *)jl_box_voidpointer((void *)*rc);
                 if (rettype_ptr) *ret = (void **)jl_bitcast(rettype_ptr, (jl_value_t *)*ret);
               } break;
      default: jl_error("ast_foreigncall: This should not have happened!");
   }
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, F, ip);
}
