#include <ffi.h>

ffi_abi get_ffi_default_abi() {
   return FFI_DEFAULT_ABI;
}

size_t get_sizeof_ffi_cif() {
   return sizeof(ffi_cif);
}

size_t get_sizeof_ffi_arg() {
   return sizeof(ffi_arg);
}

size_t get_sizeof_ffi_type() {
   return sizeof(ffi_type);
}

void init_ffi_type_struct(ffi_type *type, ffi_type **elements) {
   type->size = 0;
   type->alignment = 0;
   type->type = FFI_TYPE_STRUCT;
   type->elements = elements;
}
