#!/usr/bin/env bash

if [[ $(hostname) == "voidy" ]]; then
  export PATH="$HOME/llvm-project/build/bin:$PATH"
  export PATH="$HOME/wd/julia2/usr/bin:$PATH"
  export JULIA_DEPOT_PATH="$HOME/wd/julia2/usr/share/julia"
  export JULIA_INCLUDE="$HOME/wd/julia2/usr/include"
  export JULIA_INTERNAL_INCLUDE="$HOME/wd/julia2/src"
  export LIBFFI_INCLUDE="/usr/lib64"
elif [[ $(hostname) == "fwork" ]]; then
  export PATH="$HOME/binaries/clang+llvm-17.0.6-x86_64-linux-gnu-ubuntu-22.04/bin:$PATH"
  export PATH="$HOME/wd/julia-prot-exec/usr/bin:$PATH"
  export JULIA_INCLUDE="$HOME/wd/julia-prot-exec/usr/include"
  export JULIA_LIB="$HOME/wd/julia-prot-exec/usr/lib"
  export JULIA_INTERNAL_INCLUDE="$HOME/wd/julia-prot-exec/src"
  export LIBFFI_INCLUDE="/usr/lib64"
fi
