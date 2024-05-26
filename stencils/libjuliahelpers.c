#include "common.h"
#include <stdbool.h>

int is_method_instance(jl_method_instance_t *mi) {
   return jl_is_method_instance(mi);
}

int is_bool(jl_value_t *b) {
   return jl_is_bool(b);
}


// from julia/src/codegen.cpp
bool jl_is_concrete_immutable(jl_value_t* t)
{
    return jl_is_immutable_datatype(t) && ((jl_datatype_t*)t)->isconcretetype;
}

// from julia/src/codegen.cpp
bool jl_is_pointerfree(jl_value_t* t)
{
    if (!jl_is_concrete_immutable(t))
        return 0;
    const jl_datatype_layout_t *layout = ((jl_datatype_t*)t)->layout;
    return layout && layout->npointers == 0;
}
