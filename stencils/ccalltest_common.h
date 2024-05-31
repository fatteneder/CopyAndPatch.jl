// This file was copied from https://github.com/JuliaLang/julia/blob/master/src/ccalltest_common.h
// This file is a part of Julia. License is MIT: https://julialang.org/license
#include <stdio.h>
#include <stdlib.h>
#include <complex.h>
#include <stdint.h>
#include <inttypes.h>

// #include "../src/support/platform.h"
// #include "../src/support/dtypes.h"

// Borrow definition from `support/dtypes.h`
#ifdef _OS_WINDOWS_
#  define DLLEXPORT __declspec(dllexport)
#else
# if defined(_OS_LINUX_) && !defined(_COMPILER_CLANG_)
// Clang and ld disagree about the proper relocation for STV_PROTECTED, causing
// linker errors.
#  define DLLEXPORT __attribute__ ((visibility("protected")))
# else
#  define DLLEXPORT __attribute__ ((visibility("default")))
# endif
#endif

// Copied this from src/support/platform.h, needed for standalone compilation
#if defined(_CPU_X86_64_)
#  define _P64
#elif defined(_CPU_X86_)
#  define _P32
#elif defined(_OS_WINDOWS_)
/* Not sure how to determine pointer size on Windows running ARM. */
#  if _WIN64
#    define _P64
#  else
#    define _P32
#  endif
#elif __SIZEOF_POINTER__ == 8
#    define _P64
#elif __SIZEOF_POINTER__ == 4
#    define _P32
#else
#  error pointer size not known for your platform / compiler
#endif

#ifdef _P64
#define jint int64_t
#define PRIjint PRId64
#else
#define jint int32_t
#define PRIjint PRId32
#endif
