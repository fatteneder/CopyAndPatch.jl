#include <ffi.h>

ffi_abi get_ffi_default_abi() {
   return FFI_DEFAULT_ABI;
}

size_t get_sizeof_ffi_cif() {
   return sizeof(ffi_cif);
}
