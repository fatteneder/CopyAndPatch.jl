#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("ast_returnnode", F, ip);
   F->ssas[ip-1] = F->tmps[0];
   SET_IP(F, ip);
   return;
}
