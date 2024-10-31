#!/usr/bin/env bash

if [[ $(hostname) == "voidy" ]]; then
  JULIA_ROOT="$HOME/wd/julia2"
  export PATH="$HOME/llvm-project/build/bin:$PATH"
  export PATH="$JULIA_ROOT/usr/bin:$PATH"
  export JULIA_DEPOT_PATH="$JULIA_ROOT/usr/share/julia"
  export JULIA_INCLUDE="$JULIA_ROOT/usr/include"
  export JULIA_LIB="$JULIA_ROOT/usr/lib"
  export JULIA_INTERNAL_INCLUDE="$JULIA_ROOT/src"
  export LIBFFI_INCLUDE="/usr/lib64"
elif [[ $(hostname) == "fwork" ]]; then
  JULIA_ROOT="$HOME/wd/julia3"
  export PATH="$HOME/binaries/clang+llvm-17.0.6-x86_64-linux-gnu-ubuntu-22.04/bin:$PATH"
  export PATH="$JULIA_ROOT/usr/bin:$PATH"
  export JULIA_INCLUDE="$JULIA_ROOT/usr/include"
  export JULIA_LIB="$JULIA_ROOT/usr/lib"
  export JULIA_INTERNAL_INCLUDE="$JULIA_ROOT/src"
  export LIBFFI_INCLUDE="/usr/lib64"
fi
