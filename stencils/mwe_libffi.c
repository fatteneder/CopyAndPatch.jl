#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <ffi.h>
#include <julia.h>

jl_value_t * my_jl_alloc_genericmemory(jl_value_t *mtype, size_t nel) {
   printf("[inside] mtype = %p\n", mtype);
   printf("[inside] nel = %d\n", (int)nel);
   jl_value_t *memory = (jl_value_t *)jl_alloc_genericmemory(mtype, nel);
   printf("[inside] memory = %p\n", memory);
   printf("[inside] typeof(memory) = %s\n", jl_typeof_str(memory));
   return memory;
}

typedef struct {
   int x;
} my_type;

my_type return_my_type(int x) {
   my_type mt;
   mt.x = x;
   return mt;
}

typedef struct {
   union {
      int16_t u1;
      uint8_t u2[3];
   } u;
} NonBits46786;

NonBits46786 test_NonBits46786_by_val(NonBits46786 x) {
   x.u.u1 += (int16_t)1;
   return x;
}

NonBits46786 *test_NonBits46786_by_ref(NonBits46786 *x) {
   x->u.u1 += (int16_t)1;
   return x;
}

typedef struct {
   uint8_t tpl[3];
} StructNTuple;

/** typedef struct { */
/**    uint8_t el[16]; */
/** } union_approx; */

typedef struct {
   uint8_t el[3];
} union_approx;

typedef struct {

   /** int u; */
   union {
      int64_t i;
      uint64_t u;
   } u;
   /** int64_t u; */

   /** jl_value_t *i; */
   /** jl_value_t *u; */

   /** int64_t u; */
   /** int64_t uu; */

   /** union_approx u; */
   /** uint8_t u[16]; */

   /** union_approx u; */
} StructUnion;

int main() {
   printf("START\n");
   jl_init();

   {
      ffi_cif cif;
      ffi_type *args[2];
      void *values[2];
      ffi_arg rc;
      /** jl_value_t *rc; */

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
         ffi_call(&cif, (void *)my_jl_alloc_genericmemory, &rc, values);
         jl_value_t *memory = (jl_value_t *)rc;
         printf("memory = %p\n", memory);
         printf("typeof(memory) = %s\n", jl_typeof_str(memory));
      } else {
         printf("ffi_prep_cif failed!!!\n");
         return -1;
      }
   }

   {
      ffi_cif cif;
      ffi_type *args[1];
      void *values[1];
      ffi_arg rc;

      jl_value_t *x = jl_eval_string("Base.RefValue{Int64}(1)");
      args[0] = &ffi_type_pointer;
      values[0] = (void *)&x;
      printf("x = %p\n", x);
      printf("&x = %p\n", &x);
      printf("jl_typeof_str(x) = %s\n", jl_typeof_str(x));

      if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1,
                       &ffi_type_pointer, args) == FFI_OK) {
         printf("values[0] %p\n", values[0]);
         printf("&x == values[0] ? %d\n", &x == values[0]);
         void **xx = values[0];
         printf("(jl_value_t *)*xx %p\n", (jl_value_t *)*xx);
         printf("jl_typeof_str(*xx) = %s\n", jl_typeof_str((jl_value_t *)*xx));
         ffi_call(&cif, (void *)jl_value_ptr, &rc, values);
         printf("rc = %p\n", (void *)rc);
         jl_value_t *ptr = (jl_value_t *)rc;
         printf("jl_unbox_int64(ptr) = %ld\n", jl_unbox_int64(ptr));
         // again
         ffi_call(&cif, (void *)jl_value_ptr, &rc, values);
         printf("rc = %p\n", (void *)rc);
      } else {
         printf("ffi_prep_cif failed!!!\n");
         return -1;
      }
   }

   {
      ffi_cif cif;
      ffi_type *args[1];
      void *values[1];
      ffi_type ret;
      void *rc = malloc(sizeof(my_type));

      ffi_type *elements[2];
      elements[0] = &ffi_type_sint;
      elements[1] = NULL;
      ret.size = ret.alignment = 0;
      ret.type = FFI_TYPE_STRUCT;
      ret.elements = elements;

      int x = 123;
      args[0] = &ffi_type_sint;
      values[0] = &x;
      if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1,
                       &ret, args) == FFI_OK) {
         ffi_call(&cif, (void *)jl_value_ptr, (ffi_arg*)rc, values);
         my_type *mt = (my_type*)rc;
         printf("mt->x = %d\n", mt->x);
      } else {
         printf("ffi_prep_cif failed!!!\n");
         return -1;
      }
   }

   // example for struct with union and c-array fields
   {
      ffi_cif cif;
      ffi_type *args[1];
      void *values[1];

      ffi_type NonBits46786_type;
      ffi_type *elements[4];
      // for structs with union members we have to reserve space for the largest element of that union, cf. https://stackoverflow.com/a/40366088
      // here: sizeof(uint8_t[3]) > sizeof(uint16_t)
      // to mimic c arrays we have to 'unroll' the array's elements into the type declaration: https://stackoverflow.com/a/43525176
      elements[0] = &ffi_type_uint8;
      elements[1] = &ffi_type_uint8;
      elements[2] = &ffi_type_uint8;
      elements[3] = NULL;
      NonBits46786_type.size = NonBits46786_type.alignment = 0;
      NonBits46786_type.type = FFI_TYPE_STRUCT;
      NonBits46786_type.elements = elements;

      NonBits46786 x;
      x.u.u1 = (uint16_t)1;
      printf("x.u.u1 = %d\n", x.u.u1);

      // pass-by-value
      {
         NonBits46786 rc;
         args[0] = &NonBits46786_type;
         values[0] = &x;
         if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1,
                          &NonBits46786_type, args) == FFI_OK) {
            ffi_call(&cif, (void *)test_NonBits46786_by_val, (ffi_arg*)&rc, values);
            NonBits46786 xx = (NonBits46786)rc;
            printf("xx.u.u1 = %d\n", xx.u.u1);
         } else {
            printf("ffi_prep_cif failed!!!\n");
            return -1;
         }
      }

      // pass-by-ref
      {
         NonBits46786 *rc;
         NonBits46786 *xx = &x;
         args[0] = (ffi_type *)&ffi_type_pointer;
         values[0] = (void *)&xx;
         if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1,
                          &ffi_type_pointer, args) == FFI_OK) {
            ffi_call(&cif, (void *)test_NonBits46786_by_ref, (ffi_arg*)&rc, values);
            NonBits46786 *xx = (NonBits46786 *)rc;
            printf("xx.u.u1 = %d\n", xx->u.u1);
         } else {
            printf("ffi_prep_cif failed!!!\n");
            return -1;
         }
      }

   }

   // some example to better understand julia issue #46786 -- non-isbitstypes passed "by-value"
   {
      ffi_cif cif;
      ffi_type *args[1];
      void *values[1];

      {
         void *ptr = jl_eval_string("@cfunction(identity, Cint, (Cint,))");
         printf("ptr = %d\n", jl_is_cpointer(ptr));
         printf("ptr = %s\n", jl_typeof_str(ptr));
         printf("ptr = %p\n", ptr);
         int (*fptr)(int) = jl_unbox_voidpointer(ptr);
         int x = 1;
         printf("x = %d\n", x);
         int y = fptr(x);
         printf("y = %d\n", y);
      }

      {
         void *ptr = jl_eval_string("struct StructNTuple x::NTuple{3,UInt8} end;"
                                    "@cfunction(identity, StructNTuple, (StructNTuple,))");
         printf("ptr = %d\n", jl_is_cpointer(ptr));
         printf("ptr = %s\n", jl_typeof_str(ptr));
         printf("ptr = %p\n", ptr);
         StructNTuple (*fptr)(StructNTuple) = jl_unbox_voidpointer(ptr);
         StructNTuple x;
         x.tpl[0] = (uint16_t)0;
         x.tpl[1] = (uint16_t)1;
         x.tpl[2] = (uint16_t)2;
         printf("x.tpl = (%d,%d,%d)\n", x.tpl[0], x.tpl[1], x.tpl[2]);
         StructNTuple y = fptr(x);
         printf("y.tpl = (%d,%d,%d)\n", y.tpl[0], y.tpl[1], y.tpl[2]);
      }

      {
         // declare type and compare size, offsets
         jl_eval_string("struct StructUnion x::Union{Cint,Cuint} end");
         jl_eval_string("@show sizeof(StructUnion)");
         jl_eval_string("@show fieldoffset(StructUnion, 1)");
         printf("sizeof(StructUnion) = %ld\n", sizeof(StructUnion));
         printf("offset(StructUnion, 0) = %ld\n", offsetof(StructUnion, u));
         jl_eval_string("helper(x::StructUnion) = println(\"SERS OIDA\")");
         void *ptr = jl_eval_string("@cfunction(helper, Cvoid, (StructUnion,))");
         printf("ptr = %d\n", jl_is_cpointer(ptr));
         printf("ptr = %s\n", jl_typeof_str(ptr));
         printf("ptr = %p\n", ptr);
         StructUnion (*fptr)(StructUnion) = jl_unbox_voidpointer(ptr);
         StructUnion x;
         printf("x = %p\n", &x);
         fptr(x);
      }

      // also see mwe_union.c
   }

   jl_atexit_hook(0);
   printf("DONE\n");
   return 0;
}
