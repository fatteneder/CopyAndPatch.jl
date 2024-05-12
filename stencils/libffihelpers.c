#include <stdio.h>
#include <ffi.h>
#include <inttypes.h>

ffi_abi get_ffi_default_abi() {
   return FFI_DEFAULT_ABI;
}

size_t get_sizeof_ffi_cif() {
   return sizeof(ffi_cif);
}

int64_t my_square(int64_t x) {
   return x*x;
}

void do_nothing(void) {
   printf("doing nothing...\n");
}
