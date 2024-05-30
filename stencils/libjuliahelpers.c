#include "juliahelpers.h"
#include <julia_internal.h> // jl_gc_alloc
#include <julia_threads.h> // for julia_internal.h
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h> // bool
#include <string.h> // memcpy

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

jl_value_t *jlh_convert_to_jl_value(jl_value_t *ty, void *data) {
    jl_task_t *ct = jl_get_current_task();
    unsigned sz = jl_datatype_size(ty);
    jl_value_t *v = jl_gc_alloc(ct->ptls, sz, ty);
    memcpy(jl_data_ptr(v), data, jl_datatype_size(ty));
    return v;
}
