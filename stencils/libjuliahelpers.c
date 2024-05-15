#include "common.h"

int is_method_instance(jl_method_instance_t *mi) {
   return jl_is_method_instance(mi);
}

int is_bool(jl_value_t *b) {
   return jl_is_bool(b);
}
