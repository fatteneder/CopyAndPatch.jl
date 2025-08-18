#include "juliahelpers.h"
#include <julia_internal.h> // jl_gc_alloc
#include <julia_threads.h> // for julia_internal.h
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h> // bool
#include <string.h> // memcpy

jl_value_t *jlh_convert_to_jl_value(jl_value_t *ty, void *data) {
    jl_task_t *ct = jl_get_current_task();
    size_t sz = jl_datatype_size(ty);
    jl_value_t *v = jl_gc_alloc(ct->ptls, sz, ty);
    jl_set_typeof(v, ty);
    memcpy((void *)v, data, sz);
    return v;
}
