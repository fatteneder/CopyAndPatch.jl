// not using static causes this the value to not be inlined in the function body during compilation,
// but instead a pointer loading will be left for the linker to resolve
int a = 123;

int
_JIT_ENTRY()
{
    return a;
}
