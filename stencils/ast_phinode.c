#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int *, edges_from,  _JIT_EDGES_FROM);
   PATCH_VALUE(int,   ip,          _JIT_IP); // 1-based
   PATCH_VALUE(int,   ip_blockend, _JIT_IP_BLOCKEND); // 1-based
   PATCH_VALUE(int,   nedges,      _JIT_NEDGES);
   DEBUGSTMT("ast_phinode", F, ip);
   jl_value_t **vals = F->tmps;
   int prev_ip = F->ip;
   int from = prev_ip - 1; // 0-based
   int to = ip - F->phioffset - 1; // 0-based
   int edge = -1; // 0-based
   int closest = to; // implicit edge has `to <= edge - 1 < to + i`
   // this is because we could see the following IR (all 1-indexed):
   //   goto %3 unless %cond
   //   %2 = phi ...
   //   %3 = phi (1)[1 => %a], (2)[2 => %b]
   // from = 1, to = closest = 2, i = 1 --> edge = 2, edge_from = 2, from = 2
   for (int j = 0; j < nedges; j++) {
      int edge_from = edges_from[j]; // 1-indexed
      if (edge_from == from + 1) {
          if (edge == -1)
              edge = j;
      }
      // TODO We use a <= in the second test instead of <.
      // This might be a bug in src/interpreter.c, but I fail to trigger this issue there.
      else if (closest < edge_from && edge_from <= (to + F->phioffset + 0)) {
          // if we found a nearer implicit branch from fall-through,
          // that occurred since the last explicit branch,
          // we should use the value from that edge instead
          edge = j;
          closest = edge_from;
      }
   }
   if (edge > -1) {
      F->ssas[ip-1] = vals[edge];
   }
   else
      F->ssas[ip-1] = NULL;
   int hit_implicit = closest != to;
   if (hit_implicit || ip == ip_blockend) {
      F->phioffset = 0;
      SET_IP(F, ip);
   } else {
      F->phioffset += 1;
      SET_IP(F, prev_ip);
   }
   PATCH_JUMP(_JIT_CONT, F);
}
