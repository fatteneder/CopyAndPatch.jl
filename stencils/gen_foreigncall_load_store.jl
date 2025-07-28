function write_code(stencil_name, code)
    filename = joinpath(@__DIR__, "$stencil_name.c")
    open(filename, write=true) do file
        println(file, code)
    end
end


let
#########################################################################################
#########################################################################################
#########################################################################################
box_signatures = """
JL_DLLEXPORT jl_value_t *jl_box_bool(int8_t x) JL_NOTSAFEPOINT;
JL_DLLEXPORT jl_value_t *jl_box_int8(int8_t x) JL_NOTSAFEPOINT;
JL_DLLEXPORT jl_value_t *jl_box_uint8(uint8_t x) JL_NOTSAFEPOINT;
JL_DLLEXPORT jl_value_t *jl_box_int16(int16_t x);
JL_DLLEXPORT jl_value_t *jl_box_uint16(uint16_t x);
JL_DLLEXPORT jl_value_t *jl_box_int32(int32_t x);
JL_DLLEXPORT jl_value_t *jl_box_uint32(uint32_t x);
JL_DLLEXPORT jl_value_t *jl_box_char(uint32_t x);
JL_DLLEXPORT jl_value_t *jl_box_int64(int64_t x);
JL_DLLEXPORT jl_value_t *jl_box_uint64(uint64_t x);
JL_DLLEXPORT jl_value_t *jl_box_float32(float x);
JL_DLLEXPORT jl_value_t *jl_box_float64(double x);
# JL_DLLEXPORT jl_value_t *jl_box_voidpointer(void *x); # implemented by hand
# JL_DLLEXPORT jl_value_t *jl_box_uint8pointer(uint8_t *x); # implemented by hand
# JL_DLLEXPORT jl_value_t *jl_box_ssavalue(size_t x); # unused
# JL_DLLEXPORT jl_value_t *jl_box_slotnumber(size_t x); # unused
"""

stem = "ast_foreigncall_store_"
rgx_sig = r"^JL_DLLEXPORT jl_value_t \*(\w+)\((.+)x\)"
for line in split(box_signatures,'\n')
    isempty(line) && continue
    m = match(rgx_sig, line)
    isnothing(m) && continue
    fn_name, ctype = m[1], strip(m[2])
    m = something(match(r"jl_box_(.*)", fn_name))
    suffix = m[1]

    stencil_name = stem * suffix
    code = """
#include "common.h"

typedef union {
   uint64_t p;
   $ctype v;
} converter_$ctype;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   DEBUGSTMT(\"$stencil_name\", F, ip);
   converter_$ctype c;
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   c.p = (uint64_t)*rc;
   // printf("c.p = %p\\n", c.p);
   // $(ctype == "int64_t" ? "printf(\"c.v = %ld\\n\", c.v);" : "")
   F->ssas[ip-1] = $fn_name(c.v);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}"""
    write_code(stencil_name, code)
end


#########################################################################################
stencil_name = stem * "voidpointer"
code = """
#include "common.h"
#include <julia_threads.h> // for julia_internal.h
#include <julia_internal.h> // jl_gc_alloc

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   PATCH_VALUE(jl_value_t *, ty, _JIT_TY);
   DEBUGSTMT(\"$stencil_name\", F, ip);
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   jl_value_t *ret = jl_box_voidpointer((void *)*rc);
   if (ty) ret = jl_bitcast(ty, ret);
   F->ssas[ip-1] = ret;
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}"""
write_code(stencil_name, code)



#########################################################################################
stencil_name = stem * "uint8pointer"
code = """
#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   PATCH_VALUE(jl_value_t *, ty, _JIT_TY);
   DEBUGSTMT(\"$stencil_name\", F, ip);
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   F->ssas[ip-1] = jl_box_uint8pointer((uint8_t *)*rc);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}"""
write_code(stencil_name, code)



#########################################################################################
stencil_name = stem * "any"
code = """
#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   DEBUGSTMT(\"$stencil_name\", F, ip);
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   F->ssas[ip-1] = (jl_value_t *)*rc;
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}"""
write_code(stencil_name, code)



#########################################################################################
stencil_name = stem * "concretetype"
code = """
#include "common.h"
#include <julia_threads.h> // for julia_internal.h
#include <julia_internal.h> // jl_gc_alloc

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_retval, _JIT_I_RETVAL);
   PATCH_VALUE(jl_value_t *, ty, _JIT_TY);
   DEBUGSTMT(\"$stencil_name\", F, ip);
   // printf(\"SERS OIDA\\n\");
   ffi_arg *rc = (ffi_arg *)&F->cargs[i_retval-1];
   jl_task_t *ct = jl_get_current_task();
   size_t sz = jl_datatype_size(ty);
   jl_value_t *v = jl_gc_alloc(ct->ptls, sz, ty);
   jl_set_typeof(v, ty);
   memcpy((void *)v, (void *)rc, sz);
   F->ssas[ip-1] = v;
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}"""
write_code(stencil_name, code)

end


let
#########################################################################################
#########################################################################################
#########################################################################################
unbox_signatures = """
JL_DLLEXPORT int8_t jl_unbox_bool(jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT int8_t jl_unbox_int8(jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT uint8_t jl_unbox_uint8(jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT int16_t jl_unbox_int16(jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT uint16_t jl_unbox_uint16(jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT int32_t jl_unbox_int32(jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT uint32_t jl_unbox_uint32(jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT int64_t jl_unbox_int64(jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT uint64_t jl_unbox_uint64(jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT float jl_unbox_float32(jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT double jl_unbox_float64(jl_value_t *v) JL_NOTSAFEPOINT;
# JL_DLLEXPORT void *jl_unbox_voidpointer(jl_value_t *v) JL_NOTSAFEPOINT; # implemented by hand
# JL_DLLEXPORT uint8_t *jl_unbox_uint8pointer(jl_value_t *v) JL_NOTSAFEPOINT; # implemented by hand
"""

stem = "ast_foreigncall_load_"
rgx_sig = r"^JL_DLLEXPORT (\w+) (\w+)\(jl_value_t \*v\)"
for line in split(unbox_signatures,'\n')
    isempty(line) && continue
    m = match(rgx_sig, line)
    isnothing(m) && continue
    ctype, fn_name = m[1], m[2]
    m = something(match(r"jl_unbox_(.*)", fn_name))
    suffix = m[1]

    stencil_name = stem * suffix
    code = """
#include "common.h"

// TODO Check if void * is legal here. Maybe we should uint64_t instead?
typedef union {
   void *p;
   $ctype v;
} converter_$ctype;

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_tmps, _JIT_I_TMPS); // 1-based
   PATCH_VALUE(int, i_cargs, _JIT_I_CARGS); // 1-based
   PATCH_VALUE(int, i_mem, _JIT_I_MEM); // 1-based
   DEBUGSTMT(\"$stencil_name\", F, ip);
   jl_value_t *val = F->tmps[i_tmps-1];
   converter_$ctype c;
   c.v = $fn_name(val);
   F->cargs[i_mem-1] = c.p;
   F->cargs[i_cargs-1] = &F->cargs[i_mem-1];
   // loads don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}"""
    write_code(stencil_name, code)
end



#########################################################################################
stencil_name = stem * "voidpointer"
code = """
#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_tmps, _JIT_I_TMPS); // 1-based
   PATCH_VALUE(int, i_cargs, _JIT_I_CARGS); // 1-based
   PATCH_VALUE(int, i_mem, _JIT_I_MEM); // 1-based
   DEBUGSTMT(\"$stencil_name\", F, ip);
   jl_value_t *val = F->tmps[i_tmps-1];
   F->cargs[i_mem-1] = jl_unbox_voidpointer(val);
   F->cargs[i_cargs-1] = &F->cargs[i_mem-1];
   // loads don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}"""
write_code(stencil_name, code)



#########################################################################################
stencil_name = stem * "uint8pointer"
code = """
#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_tmps, _JIT_I_TMPS); // 1-based
   PATCH_VALUE(int, i_cargs, _JIT_I_CARGS); // 1-based
   PATCH_VALUE(int, i_mem, _JIT_I_MEM); // 1-based
   DEBUGSTMT(\"$stencil_name\", F, ip);
   jl_value_t *val = F->tmps[i_tmps-1];
   F->cargs[i_mem-1] = (void *)jl_unbox_uint8pointer(val);
   F->cargs[i_cargs-1] = &F->cargs[i_mem-1];
   // loads don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}"""
write_code(stencil_name, code)



#########################################################################################
stencil_name = stem * "concretetype"
code = """
#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_tmps, _JIT_I_TMPS); // 1-based
   PATCH_VALUE(int, i_cargs, _JIT_I_CARGS); // 1-based
   PATCH_VALUE(int, i_mem, _JIT_I_MEM); // 1-based
   PATCH_VALUE(jl_value_t *, ty, _JIT_TY);
   DEBUGSTMT(\"$stencil_name\", F, ip);
   jl_value_t *val = F->tmps[i_tmps-1];
   size_t sz = jl_datatype_size(ty);
   // void *v = alloca(sz);
   // memcpy(v, (void *)val, sz);
   // F->cargs[i_mem-1] = v;
   memcpy(&F->cargs[i_mem-1], (void *)val, sz);
   F->cargs[i_cargs-1] = &F->cargs[i_mem-1];
   // loads don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}"""
write_code(stencil_name, code)

stencil_name = stem * "any"
code = """
#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i_tmps, _JIT_I_TMPS); // 1-based
   PATCH_VALUE(int, i_cargs, _JIT_I_CARGS); // 1-based
   PATCH_VALUE(int, i_mem, _JIT_I_MEM); // 1-based
   jl_value_t *val = F->tmps[i_tmps-1];
   DEBUGSTMT(\"$stencil_name\", F, ip);
   // F->cargs[i_mem-1] = (void *)&F->tmps[i_tmps-1];
   // F->cargs[i_cargs-1] = F->cargs[i_mem-1];
   F->cargs[i_cargs-1] = (void *)&F->tmps[i_tmps-1];
   // loads don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}"""
write_code(stencil_name, code)

end
