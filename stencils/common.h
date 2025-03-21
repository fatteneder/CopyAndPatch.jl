#include <stdint.h>
#include <inttypes.h>
#include <julia.h>
#include <ffi.h>

#ifdef USE_GHC_CC
#define CALLING_CONV __attribute__((preserve_none))
#else
#define CALLING_CONV
#endif

#define JIT_ENTRY()                               \
    CALLING_CONV                                  \
    void _JIT_ENTRY(int prev_ip)

#define PATCH_VALUE(TYPE, NAME, ALIAS)            \
    extern void (ALIAS);                          \
    TYPE (NAME) = (TYPE)(uint64_t)&(ALIAS);

#define PATCH_JUMP(ALIAS, IP)                     \
do {                                              \
    extern void (CALLING_CONV (ALIAS))(int);      \
    __attribute__((musttail))                     \
    return (ALIAS)((IP));                         \
} while (0)

#define PATCH_CALL(ALIAS, IP)                     \
    extern void (CALLING_CONV (ALIAS))(int);      \
    (ALIAS)((IP))

#define RESET_COLOR   "\033[39m"
#define FG_GREEN      "\033[32m"
#define FG_YELLOW     "\033[33m"
#define RESET_FORMAT  "\033[0m"
#define BOLD          "\033[1m"

#ifdef JITDEBUG
    #include <stdio.h>
    #define DEBUGSTMT(NAME, PREV_IP, IP) \
        printf(BOLD FG_YELLOW "[" FG_GREEN "JITDEBUG" FG_YELLOW "]" RESET_COLOR RESET_FORMAT \
               " ip %d -> %d: " NAME "\n", (PREV_IP), (IP)); \
        fflush(stdout)
#else
    #define DEBUGSTMT(NAME, PREV_IP, IP)
#endif
