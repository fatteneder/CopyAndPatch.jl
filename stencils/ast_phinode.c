#include "common.h"

void
_JIT_ENTRY(int prev_ip)
{
   PATCH_VALUE(int *,          edges,     _JIT_EDGES);
   PATCH_VALUE(int,            ip,        _JIT_IP);
   PATCH_VALUE(int,            chain_phi, _JIT_CHAIN_PHI);
   PATCH_VALUE(int,            nedges,    _JIT_NEDGES);
   PATCH_VALUE(jl_value_t **,  ret,       _JIT_RET);
   PATCH_VALUE(jl_value_t ***, vals,      _JIT_VALS);
   DEBUGSTMT("ast_phinode", prev_ip, ip);
   for (int ie = 0; ie < nedges; ie++) {
      if (edges[ie] == prev_ip) {
         *ret = *(vals[ie]);
         PATCH_JUMP(_JIT_CONT, chain_phi ? prev_ip : ip);
      }
   }
   jl_error("ast_phinode: This should not have happened!");
}
