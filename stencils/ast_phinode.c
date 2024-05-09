#include "common.h"

void
_JIT_ENTRY(int ip) {
   PATCH_VALUE(int *, edges,  _JIT_EDGES);
   PATCH_VALUE(int,   nedges, _JIT_NEDGES);
   PATCH_VALUE(jl_value_t **, vals, _JIT_VALS);
   PATCH_VALUE(jl_value_t **, ret,  _JIT_RET);
   PATCH_VALUE(int, this_ip, _JIT_THIS_IP);
   for (int ie = 0; ie < nedges; ie++) {
      if (edges[ie] == ip) {
         *ret = vals[ie];
         PATCH_JUMP(_JIT_CONT, this_ip);
      }
   }
   jl_error("jit_phinode: This should not have happened!");
}