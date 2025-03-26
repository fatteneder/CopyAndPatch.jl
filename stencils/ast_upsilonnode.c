#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   PATCH_VALUE(int, ret_ip, _JIT_RET_IP); // 1-based
   DEBUGSTMT("ast_upsilonnode", F, ip);
   F->ssas[ret_ip-1] = F->tmps[0];
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
