#include <stdio.h>
#include <ffi.h>
#include <inttypes.h>
#include <julia.h>

jl_value_t * my_jl_alloc_genericmemory(jl_value_t *mtype, size_t nel) {
   printf("[inside] mtype = %p\n", mtype);
   printf("[inside] nel = %d\n", (int)nel);
   jl_value_t *memory = (jl_value_t *)jl_alloc_genericmemory(mtype, nel);
   printf("[inside] memory = %p\n", memory);
   printf("[inside] typeof(memory) = %s\n", jl_typeof_str(memory));
   return memory;
}

int main() {
   printf("START\n");
   jl_init();

   ffi_cif cif;
   ffi_type *args[2];
   void *values[2];
   jl_value_t *rc;

   jl_value_t *memory_type = jl_eval_string("Memory{Int64}");
   size_t nel = 3;
   args[0] = &ffi_type_pointer;
   args[1] = &ffi_type_uint64;
   values[0] = (void *)&memory_type;
   values[1] = &nel;

   // ffi_prep_cif(ffi_cif *cif, int abi, int nargs,
   //              void *rettype, void  **argtypes);
   if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 2,
                     &ffi_type_pointer, args) == FFI_OK) {
      ffi_call(&cif, (void *)my_jl_alloc_genericmemory, (ffi_arg *)&rc, values);
      jl_value_t *memory = rc;
      printf("memory = %p\n", memory);
      printf("typeof(memory) = %s\n", jl_typeof_str(memory));
   } else {
      printf("ffi_prep_cif failed!!!\n");
      return -1;
   }

   jl_atexit_hook(0);
   printf("DONE\n");
   return 0;
}
