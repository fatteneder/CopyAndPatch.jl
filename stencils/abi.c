// this is essential for julia's exception handling, taken from julia/src/task.c
#ifdef _FORTIFY_SOURCE
// disable __longjmp_chk validation so that we can jump between stacks
// (which would normally be invalid to do with setjmp / longjmp)
#pragma push_macro("_FORTIFY_SOURCE")
#undef _FORTIFY_SOURCE
#include <setjmp.h>
#pragma pop_macro("_FORTIFY_SOURCE")
#endif

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
    locals = (jl_value_t**)&((void**)&frame[1])[3]

//// we define this separately so that we can populate the frame before we add it to the backtrace
//// it's recommended to mark the containing function with NOINLINE, though not essential
#define JL_GC_ENABLEFRAME(frame) \
    jl_signal_fence(); \
    ((void**)&frame[1])[0] = __builtin_frame_address(0)


#include "common.h"
/** #include "julia_internal.h" */


// JL_CALLABLE(_JIT_ENTRY)
jl_value_t *
_JIT_ENTRY(jl_value_t *f, jl_value_t **args, uint32_t nargs, jl_code_instance_t *ci)
{
   frame *F; jl_value_t **locals;
   PATCH_VALUE(jl_value_t **, slots,      _JIT_SLOTS);
   PATCH_VALUE(jl_value_t **, ssas,       _JIT_SSAS);
   PATCH_VALUE(int *,         phioffset,  _JIT_PHIOFFSET);
   JL_GC_PUSHFRAME(F, locals, 1 /*nroots*/);
   F->ip = -1;
   F->locals = locals;
   int ip = 0;
   DEBUGSTMT("abi", F, ip);
   *phioffset = 0;
   slots[0] = f;
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
   F->ip = ip;
   extern void (CALLING_CONV _JIT_STENCIL)(frame *);
   _JIT_STENCIL(F);
   JL_GC_ENABLEFRAME(F);
   jl_value_t *ret = ssas[F->ip-1];
   JL_GC_POP();
   return ret;
}
