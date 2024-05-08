# CopyAndPatch.jl


## Preparing stencils

Prerequisites:
- `clang`
- `llvm-readobj`
- `libffi`
    - dependencies `autoconf, automake, libtool`
- `llvm-mc` (for `code_native` implementation)
- `llvm-objdump` (optional for debugging stencils)
- `julia` from [this](https://github.com/fatteneder/julia/tree/fa/prot_exec) branch (implements `exec` option for `mmap`)

LLVM dependencies should be from `LLVM 17+`.
You can download prebuild binaries from https://github.com/llvm/llvm-project/releases/tag/llvmorg-17.0.6

> Using prebuild binaries can cause warnings like `clang: /lib64/libtinfo.so.6: no version information available (required by clang)`
> These have not been of harm yet to my tests.

Prepare `libffi`:
```
$ git clone git@github.com:libffi/libffi.git
$ cd libffi
$ ./autogen.sh
$ ./configure
$ make # generates a folder <arch-triple>/include which should be added to stencils/setup.sh
```
The reason we need to build (or at least `configure`) a copy of `libffi`, although
the project uses `Libffi_jll`, is that we need the `ffi.h` header for the stencil generation.

Compile stencils and helpers:
```
$ cd stencils
$ source setup.sh # need to update this to your local installation
$ make
```

Test:
```
$ julia --project=CopyAndPatch
julia> include("test/runtests.jl")
```
