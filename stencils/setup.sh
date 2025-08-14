#!/usr/bin/env bash

THISDIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
JULIA_ROOT="$THISDIR/../julia" # make sure to run git submodule init first

if [[ $(hostname) == "fwork" ]]; then
  export PATH="$HOME/binaries/clang+llvm-17.0.6-x86_64-linux-gnu-ubuntu-22.04/bin:$PATH"
  export READOBJ=llvm-readobj
  export DUMPOBJ=llvm-readobj
  export CLANG=clang
  # export PATH="$HOME/binaries/llvm-project-19.1.1.src/build/bin:$PATH"
  export PATH="$JULIA_ROOT/usr/bin:$PATH"
  export JULIA_REPO_SRC="$JULIA_ROOT/src"
  export JULIA_INCLUDE="$JULIA_ROOT/usr/include"
  export JULIA_LIB="$JULIA_ROOT/usr/lib"
  export LIBFFI_INCLUDE="/usr/lib64"
elif [[ $(hostname) == "ubi" ]]; then
  export PATH="$JULIA_ROOT/usr/bin:$PATH"
  export READOBJ=llvm-readobj-17
  export DUMPOBJ=llvm-readobj-17
  export CLANG=clang-17
  export JULIA_REPO_SRC="$JULIA_ROOT/src"
  export JULIA_INCLUDE="$JULIA_ROOT/usr/include"
  export JULIA_LIB="$JULIA_ROOT/usr/lib"
  export LIBFFI_INCLUDE="/usr/include/x86_64-linux-gnu"
fi
