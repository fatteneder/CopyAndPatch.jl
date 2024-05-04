#include "common.h"

typedef union {
   uint64_t addr;
   void (*fnptr)(int);
} convert_cont;

void _JIT_CONT(int);

void
_JIT_ENTRY(int ip) {
   PATCH_VALUE(int *, edges,  _JIT_EDGES);
   PATCH_VALUE(int,   nedges, _JIT_NEDGES);
   PATCH_VALUE(jl_value_t **, vals, _JIT_VALS);
   PATCH_VALUE(jl_value_t **, ret,  _JIT_RET);
   PATCH_VALUE(int, this_ip, _JIT_THIS_IP);
   /** PATCH_VALUE_AND_CONVERT(uint64_t, convert_cont, cont, _JIT_CONT); */
   for (int ie = 0; ie < nedges; ie++) {
      if (edges[ie] == ip) {
         *ret = vals[ie];
         do {
            __attribute__((musttail))
            return _JIT_CONT(this_ip);
            /** return cont.fnptr(this_ip); */
         } while(0);
         /** _JIT_CONT(this_ip); */
         /** return; */
      }
   }
   jl_error("jit_phinode: This should not have happened!");
}
