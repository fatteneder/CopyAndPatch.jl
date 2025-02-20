<p align="center">
<img width="250px" src="./logo/logo.png" alt="CopyAndPatch.jl" />
</p>
<h1 align="center">
CopyAndPatch.jl
</h1>


## Preparing stencils

Prerequisites for stencil generation
- `clang`: compiler
- `llvm-readobj`: exe
- `libffi`: library and headers
- `llvm-mc`: exe (for `code_native` implementation)
- `llvm-objdump`: exe (optional for debugging stencils)
- `julia`: exe, library and headers; need a local build of [this](https://github.com/fatteneder/julia/tree/fa/prot_exec_rebase) branch which implements `exec` option for `mmap`

LLVM dependencies should be from `LLVM 17+`.
You can download prebuild binaries from https://github.com/llvm/llvm-project/releases/tag/llvmorg-17.0.6

> Using prebuild binaries can cause warnings like `clang: /lib64/libtinfo.so.6: no version information available (required by clang)`
> These have not been of harm yet to my tests.

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
