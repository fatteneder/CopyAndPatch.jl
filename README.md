# CopyAndPatch.jl


## Preparing stencils

Prerequisites:
- `clang`
- `llvm-readobj`
- `llvm-objdump` (optional for debugging stencils)
- `julia` from [this](https://github.com/fatteneder/julia/tree/fa/prot_exec) branch (implements `exec` option for `mmap`)

Compile:
```
$ cd stencils
$ source setup.sh
$ make
```

Test:
```
$ julia --project=CopyAndPatch
julia> include("stencils/jl_call0.jl")
```
