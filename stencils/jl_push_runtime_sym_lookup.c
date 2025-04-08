#include "common.h"
#include "julia_internal.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,           ip,       _JIT_IP);
   PATCH_VALUE(int,           i,        _JIT_I); // 1-based
   PATCH_VALUE(int,           i_gc,     _JIT_I_GC); // 1-based
   PATCH_VALUE(jl_module_t *, mod,      _JIT_MOD);
   PATCH_VALUE(jl_value_t *,  lib_expr, _JIT_LIB_EXPR);
   PATCH_VALUE(const char *,  f_name,   _JIT_F_NAME);
   DEBUGSTMT("jl_push_runtime_sym_lookup", F, ip);
   // TODO cache result
   jl_value_t *lib_val = jl_toplevel_eval(mod, lib_expr);
   F->gcroots[i_gc-1] = lib_val;
   F->tmps[i-1] = jl_lazy_load_and_lookup(lib_val, f_name);
   // push operations don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
