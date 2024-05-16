#include "common.h"

void
_JIT_ENTRY(int prev_ip) {
   PATCH_VALUE(int *,          edges,   _JIT_EDGES);
   PATCH_VALUE(int,            ip,      _JIT_IP);
   PATCH_VALUE(int,            nedges,  _JIT_NEDGES);
   PATCH_VALUE(jl_value_t **,  ret,     _JIT_RET);
   PATCH_VALUE(int,            retused, _JIT_RETUSED);
   PATCH_VALUE(jl_value_t ***, vals,    _JIT_VALS);
   for (int ie = 0; ie < nedges; ie++) {
      if (edges[ie] == prev_ip) {
         jl_value_t *_ret = *(vals[ie]);
         if (retused)
            *ret = _ret;
         PATCH_JUMP(_JIT_CONT, ip);
      }
   }
   jl_error("ast_phinode: This should not have happened!");
}
