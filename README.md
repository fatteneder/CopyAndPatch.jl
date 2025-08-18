<p align="center">
<img width="250px" src="./logo/logo.png" alt="CopyAndPatch.jl" />
</p>
<h1 align="center">
CopyAndPatch.jl
</h1>


> ⚠️Only tested on `x86_64-linux` ⚠️


## Prequisites

- `julia`: need a local build of [this](https://github.com/fatteneder/julia/tree/cpjit-mmap-v3) tag which implements `exec` option for `mmap`

## Installation

```julia
julia> import Pkg
julia> Pkg.develop("/path/to/julia-build/Compiler")
julia> Pkg.build() # this can take a while, as it downloads julia's build dependencies
julia> include("test/runtests.jl")
```

## Dev notes

- If the build command fails, check the `deps/build.log` output.

- To change the julia-repo artifact update the download url in `deps/generate_artifacts.toml`,
  run the script and rebuild.

- To recompile all stencils run `import Scratch; Scratch.clear_scratchspaces!()` and rebuild.

- Running `Pkg.build()` creates a script `stencils/setup.sh` with env variables needed
for the build process. You can use it as follows
```sh
cd stencils
source setup.sh
make # rebuild stencils outside julia
cd $CPJIT_SCRATCH_DIR # inspect scratch space setup etc
```

- You can customize the build process using the `Preferences.jl` mechanism.
These options can also be used with `make`.
```toml
# CopyAndPatch.jl/LocalPreferences.toml

[CopyAndPatch]
debug=1      # enable stencil's DEBUGSTMT output
use_ghc_cc=1 # compile stencils with the Glasgow Haskell compiler (GHC) calling convention,
             # requires `clang >= 19`, required for register pinning (TBD)
emit_llvm=1  # also emit LLVM IR for each stencil, required for register pinning (TBD)
```
