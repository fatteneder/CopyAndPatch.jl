#include "common.h"

// helpers to allocate and active frames on the stack, taken from julia/src/interpreter.c

//// general alloca rules are incompatible on C and C++, so define a macro that deals with the difference
#ifdef __cplusplus
#define JL_CPPALLOCA(var,n)                                                         \
  var = (decltype(var))alloca((n))
#else
#define JL_CPPALLOCA(var,n)                                                         \
  var = alloca((n));
#endif

#define JL_GC_ENCODE_PUSHFRAME(n)  ((((size_t)(n))<<2)|2)

#define JL_GC_PUSHFRAME(frame,locals,n)                                             \
  JL_CPPALLOCA(frame, sizeof(*frame)+(n)*sizeof(void*)+3*sizeof(jl_value_t*));      \
  ((void**)&frame[1])[0] = NULL;                                                    \
  ((void**)&frame[1])[1] = (void*)JL_GC_ENCODE_PUSHFRAME(n);                        \
  ((void**)&frame[1])[2] = jl_pgcstack;                                             \
  memset(&((void**)&frame[1])[3], 0, (n)*sizeof(jl_value_t*));                      \
  jl_pgcstack = (jl_gcframe_t*)&(((void**)&frame[1])[1]);                           \
  locals = (jl_value_t**)&((void**)&frame[1])[3];

//// we define this separately so that we can populate the frame before we add it to the backtrace
//// it's recommended to mark the containing function with NOINLINE, though not essential
#define JL_GC_ENABLEFRAME(frame) \
    jl_signal_fence(); \
    ((void**)&frame[1])[0] = __builtin_frame_address(0);

// end helpers

// JL_CALLABLE(_JIT_ENTRY)
jl_value_t *
_JIT_ENTRY(jl_value_t *F, jl_value_t **args, uint32_t nargs, jl_code_instance_t *ci)
{
   frame *f; jl_value_t **locals;
   PATCH_VALUE(int, nroots, _JIT_NROOTS);
   PATCH_VALUE(jl_value_t **, slots,      _JIT_SLOTS);
   PATCH_VALUE(jl_value_t **, ssas,       _JIT_SSAS);
   PATCH_VALUE(int *,         phioffset,  _JIT_PHIOFFSET);
   int prev_ip = -1, ip = 0;
   DEBUGSTMT("abi", prev_ip, ip);
   JL_GC_PUSHFRAME(f, locals, nroots);
   f->locals = locals;
   f->locals[0] = F;
   f->ip = 0;
   // when called from julia's invoke then args is a genuine jl_value_t ** array
   if (!jl_is_datatype(jl_typeof((jl_value_t *)args))) {
      for (int i = 0; i < (int)nargs; i++) {
         f->locals[i+1] = args[i];
      }
   }
   // when called from src/machinecode.jl we just forward the tuple of vargs to here
   else if (jl_is_tuple((jl_value_t *)args)) {
      for (int i = 0; i < (int)nargs; i++) {
         f->locals[i+1] = jl_fieldref(args, i);
      }
   }
   else {
      jl_errorf("abi stencil: encountered %s when converting args to slots",
                jl_typeof_str((jl_value_t*)args));
   }
   *phioffset = 0;
   extern void (CALLING_CONV _JIT_STENCIL)(frame *);
   _JIT_STENCIL(f);
   jl_value_t *ret = ssas[f->ip-1];
   return ret;
}
