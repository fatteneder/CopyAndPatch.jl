#include "common.h"
#include "julia_internal.h"
#include "julia_threads.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(jl_value_t **, a1, _JIT_A1);
   PATCH_VALUE(jl_value_t **, a2, _JIT_A2);
   PATCH_VALUE(jl_value_t **, a3, _JIT_A3);
   DEBUGSTMT("jl_pointerref", F, ip);
   JL_GC_PUSH3(a1,a2,a3);
   F->ssas[ip] = jl_pointerref(*a1,*a2,*a3);
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, F, ip);
}
