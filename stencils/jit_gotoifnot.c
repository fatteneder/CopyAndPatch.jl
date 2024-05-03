#include "common.h"

typedef union {
   uint64_t addr;
   void (*fnptr)(void **);
} convert_cont;

void
_JIT_ENTRY(void **stack_ptr) {
   PATCH_VALUE(jl_value_t *, test, _JIT_TEST);
   PATCH_VALUE_AND_CONVERT(uint64_t, convert_cont, cont1, _JIT_CONT1);
   PATCH_VALUE_AND_CONVERT(uint64_t, convert_cont, cont2, _JIT_CONT2);
   if (test == jl_false)
      cont1.fnptr(stack_ptr);
   else if (test != jl_true)
      jl_type_error("if", (jl_value_t*)jl_bool_type, test);
   cont2.fnptr(stack_ptr);
}
