#include <inttypes.h>
#include <julia.h>
#include <ffi.h>

typedef struct {
   int ip; // 1-based
   int phioffset;
   int exc_thrown;
   jl_value_t **slots;
   jl_value_t **ssas;
   jl_value_t **tmps;
   jl_value_t **gcroots;
} frame;

#ifdef USE_GHC_CC
#define CALLING_CONV __attribute__((preserve_none))
#else
#define CALLING_CONV
#endif

#define JIT_ENTRY()                               \
    CALLING_CONV                                  \
    void _JIT_ENTRY(frame *F)

#define SET_IP(F, IP)                             \
    (F)->ip = (IP)

#define PATCH_VALUE(TYPE, NAME, ALIAS)            \
    extern void (ALIAS);                          \
    TYPE (NAME) = (TYPE)(uint64_t)&(ALIAS)

#define PATCH_JUMP(ALIAS, F)                      \
do {                                              \
    extern void (CALLING_CONV (ALIAS))(frame *);  \
    __attribute__((musttail))                     \
    return (ALIAS)((F));                          \
} while (0)

#define PATCH_CALL(ALIAS, F)                      \
    extern void (CALLING_CONV (ALIAS))(frame *);  \
    (ALIAS)((F))

#define RESET_COLOR   "\033[39m"
#define FG_GREEN      "\033[32m"
#define FG_YELLOW     "\033[33m"
#define RESET_FORMAT  "\033[0m"
#define BOLD          "\033[1m"

#ifdef JITDEBUG
#include <stdio.h>
#define DEBUGSTMT(NAME, F, IP) \
    printf(BOLD FG_YELLOW "[" FG_GREEN "JITDEBUG" FG_YELLOW "]" RESET_COLOR RESET_FORMAT \
           " ip %d -> %d: " NAME "\n", (F)->ip, (IP))
#else
#define DEBUGSTMT(NAME, F, IP)
#endif
