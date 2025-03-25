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
JL_DLLEXPORT jl_value_t *jl_box_voidpointer(void *x);
JL_DLLEXPORT jl_value_t *jl_box_uint8pointer(uint8_t *x);
# JL_DLLEXPORT jl_value_t *jl_box_ssavalue(size_t x);
# JL_DLLEXPORT jl_value_t *jl_box_slotnumber(size_t x);
"""

let
rgx_sig = r"^JL_DLLEXPORT (\w* \*)(\w*)\((.*)x\)"
rgx_arg = r"(\w* \*)"
for line in split(box_signatures,'\n')
    isempty(line) && continue
    m = match(rgx_sig, line)
    isnothing(m) && continue
    rettype, fn_name, argtype = m[1], m[2], m[3]
    m = something(match(r"jl_box_(.*)", fn_name))
    suffix = m[1]
    rettype != "jl_value_t *" && continue
    code = """
#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE($argtype, x, _JIT_X);
   DEBUGSTMT(\"$fn_name\", F, ip);
   F->tmps[i-1] = $fn_name(x);
   PATCH_JUMP(_JIT_CONT, F, ip);
}"""
    println(code)
    stencil_name = "jl_box_and_push_$(suffix)"
    filename = joinpath(@__DIR__, "$stencil_name.c")
    open(filename, write=true) do file
        println(file, code)
    end
end
end
