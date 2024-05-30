#ifndef JULIAHELPERS_H
#define JULIAHELPERS_H


#include <julia.h>


jl_value_t *jlh_convert_to_jl_value(jl_value_t *ty, void *data);


#endif // JULIAHELPERS_H
