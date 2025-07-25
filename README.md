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
- `julia`: exe, library and headers; need a local build of [this](https://github.com/fatteneder/julia/tree/cpjit-mmap-v3) tag which implements `exec` option for `mmap`

`clang, llvm-readobj, llvm-objdump` should be from the same `LLVM` version (and at least `LLVM 17+`).

- You can download prebuild binaries from https://github.com/llvm/llvm-project/releases/tag/llvmorg-17.0.6

> Using prebuild binaries can cause warnings like `clang: /lib64/libtinfo.so.6: no version information available (required by clang)`
> These have not been of harm yet to my tests.

- On an `apt` powered OS use `apt install clang-17 llvm-17 llvm-17-tools libffi-dev`.

Compile stencils and helpers:
```
$ cd stencils
$ source setup.sh # need to update this to your local installation
$ make
$ cd ..
$ julia --project
julia> using Pkg; Pkg.dev("/path/to/local-julia-build/Compiler"); Pkg.instantiate()
```

Test:
```
$ julia --project=CopyAndPatch
julia> include("test/runtests.jl")
```

## Dev notes

`make` options:
- `debug=1`: enable stencil's DEBUGSTMT output
- `use_ghc_cc=1`: compile stencils with the Glasgow Haskell compiler (GHC) calling convention,
  requires `clang >= 19`
- `emit_llvm=1`: also emit LLVM IR for each stencil
