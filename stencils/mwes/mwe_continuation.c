#include <stdio.h>
#include "common.h"

void
_JIT_ENTRY(void **stack_ptr)
{
    void (*continuation)(void **) = stack_ptr[0];
    stack_ptr--;
    continuation(stack_ptr);
}
