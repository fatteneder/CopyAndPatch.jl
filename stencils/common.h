#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <julia.h>
#include <ffi.h>

#define PATCH_VALUE(TYPE, NAME, ALIAS)  \
    extern void ALIAS;                  \
    TYPE NAME = (TYPE)(uint64_t)&ALIAS;

#define PATCH_JUMP(ALIAS, IP)      \
do {                               \
    extern void (ALIAS)(int);      \
    __attribute__((musttail))      \
    return (ALIAS)(IP);            \
} while (0);

#define RESET_COLOR   "\033[39m"
#define FG_GREEN      "\033[32m"
#define FG_YELLOW     "\033[33m"
#define RESET_FORMAT  "\033[0m"
#define BOLD          "\033[1m"

#ifdef JITDEBUG
    #define DEBUGSTMT(NAME, IP) \
        printf(BOLD FG_YELLOW "[" FG_GREEN "JITDEBUG" FG_YELLOW "]" RESET_COLOR RESET_FORMAT \
               " ip %-4d reached " NAME "\n", (IP)); \
        fflush(stdout)
#else
    #define DEBUGSTMT(NAME, IP)
#endif
