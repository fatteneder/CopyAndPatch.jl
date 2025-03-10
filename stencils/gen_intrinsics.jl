signatures="""

JL_DLLEXPORT jl_value_t *jl_bitcast(jl_value_t *ty, jl_value_t *v);
JL_DLLEXPORT jl_value_t *jl_pointerref(jl_value_t *p, jl_value_t *i, jl_value_t *align);
JL_DLLEXPORT jl_value_t *jl_pointerset(jl_value_t *p, jl_value_t *x, jl_value_t *align, jl_value_t *i);
JL_DLLEXPORT jl_value_t *jl_atomic_fence(jl_value_t *order);
JL_DLLEXPORT jl_value_t *jl_atomic_pointerref(jl_value_t *p, jl_value_t *order);
JL_DLLEXPORT jl_value_t *jl_atomic_pointerset(jl_value_t *p, jl_value_t *x, jl_value_t *order);
JL_DLLEXPORT jl_value_t *jl_atomic_pointerswap(jl_value_t *p, jl_value_t *x, jl_value_t *order);
JL_DLLEXPORT jl_value_t *jl_atomic_pointermodify(jl_value_t *p, jl_value_t *f, jl_value_t *x, jl_value_t *order);
JL_DLLEXPORT jl_value_t *jl_atomic_pointerreplace(jl_value_t *p, jl_value_t *x, jl_value_t *expected, jl_value_t *success_order, jl_value_t *failure_order);
JL_DLLEXPORT jl_value_t *jl_cglobal(jl_value_t *v, jl_value_t *ty);
JL_DLLEXPORT jl_value_t *jl_cglobal_auto(jl_value_t *v);

JL_DLLEXPORT jl_value_t *jl_neg_int(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_add_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_sub_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_mul_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_sdiv_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_udiv_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_srem_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_urem_int(jl_value_t *a, jl_value_t *b);

JL_DLLEXPORT jl_value_t *jl_add_ptr(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_sub_ptr(jl_value_t *a, jl_value_t *b);

JL_DLLEXPORT jl_value_t *jl_neg_float(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_add_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_sub_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_mul_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_div_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_min_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_max_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_fma_float(jl_value_t *a, jl_value_t *b, jl_value_t *c);
JL_DLLEXPORT jl_value_t *jl_muladd_float(jl_value_t *a, jl_value_t *b, jl_value_t *c);

JL_DLLEXPORT jl_value_t *jl_eq_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_ne_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_slt_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_ult_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_sle_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_ule_int(jl_value_t *a, jl_value_t *b);

JL_DLLEXPORT jl_value_t *jl_eq_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_ne_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_lt_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_le_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_fpiseq(jl_value_t *a, jl_value_t *b);

JL_DLLEXPORT jl_value_t *jl_not_int(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_and_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_or_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_xor_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_shl_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_lshr_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_ashr_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_bswap_int(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_ctpop_int(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_ctlz_int(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_cttz_int(jl_value_t *a);

JL_DLLEXPORT jl_value_t *jl_sext_int(jl_value_t *ty, jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_zext_int(jl_value_t *ty, jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_trunc_int(jl_value_t *ty, jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_sitofp(jl_value_t *ty, jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_uitofp(jl_value_t *ty, jl_value_t *a);

JL_DLLEXPORT jl_value_t *jl_fptoui(jl_value_t *ty, jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_fptosi(jl_value_t *ty, jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_fptrunc(jl_value_t *ty, jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_fpext(jl_value_t *ty, jl_value_t *a);

JL_DLLEXPORT jl_value_t *jl_checked_sadd_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_checked_uadd_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_checked_ssub_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_checked_usub_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_checked_smul_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_checked_umul_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_checked_sdiv_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_checked_udiv_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_checked_srem_int(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_checked_urem_int(jl_value_t *a, jl_value_t *b);

JL_DLLEXPORT jl_value_t *jl_ceil_llvm(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_floor_llvm(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_trunc_llvm(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_rint_llvm(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_sqrt_llvm(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_sqrt_llvm_fast(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_abs_float(jl_value_t *a);
JL_DLLEXPORT jl_value_t *jl_copysign_float(jl_value_t *a, jl_value_t *b);
JL_DLLEXPORT jl_value_t *jl_flipsign_int(jl_value_t *a, jl_value_t *b);

JL_DLLEXPORT jl_value_t *jl_have_fma(jl_value_t *a);
JL_DLLEXPORT int jl_stored_inline(jl_value_t *el_type);
JL_DLLEXPORT jl_value_t *(jl_array_data_owner)(jl_array_t *a);
JL_DLLEXPORT jl_array_t *jl_array_copy(jl_array_t *ary);

JL_DLLEXPORT uintptr_t jl_object_id_(uintptr_t tv, jl_value_t *v) JL_NOTSAFEPOINT;
JL_DLLEXPORT void jl_set_next_task(jl_task_t *task) JL_NOTSAFEPOINT;
"""


let
rgx_sig = r"JL_DLLEXPORT (\w* \*)(\w*)\((.*)\)"
rgx_arg = r"(\w* \*)"
for line in split(signatures,'\n')
    isempty(line) && continue
    m = match(rgx_sig, line)
    isnothing(m) && continue
    rettype, fn_name, args = m[1], m[2], split(m[3],',')
    argtypes = SubString[]
    skip = false
    for a in args
        m = match(rgx_arg, a)
        if isnothing(m)
            skip = true
            break
        end
        push!(argtypes, m[1])
    end
    skip && continue

    rettype != "jl_value_t *" && continue
    !all(==("jl_value_t *"), argtypes) && continue
    # TODO Removed by #53765
    fn_name == "jl_arraylen" && continue
    nargs = length(argtypes)
    @assert nargs <= 6
    patch_args = join([ "PATCH_VALUE(jl_value_t **, a$i, _JIT_A$i);" for i = 1:nargs ], '\n')
    gc_push = "JL_GC_PUSH$(nargs)(" * join(["a$i" for i in 1:nargs],',') * ");"
    fn_args = join([ "*a$i" for i = 1:nargs ], ',')
    code = """
#include "common.h"
#include "julia_internal.h"
#include "julia_threads.h"

JIT_ENTRY(prev_ip)
{
PATCH_VALUE(int, ip, _JIT_IP);
$patch_args
PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
DEBUGSTMT(\"$fn_name\", prev_ip, ip);
$gc_push
*ret = $fn_name($fn_args);
JL_GC_POP();
PATCH_JUMP(_JIT_CONT, ip);
}"""
    println(code)
    filename = joinpath(@__DIR__, "$fn_name.c")
    open(filename, write=true) do file
        println(file, code)
    end
end
end
