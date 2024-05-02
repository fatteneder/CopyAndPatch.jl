#!/usr/bin/env bash

if [[ $(hostname) == "voidy" ]]; then
  export PATH="$HOME/llvm-project/build/bin:$PATH"
  export PATH="$HOME/wd/julia2/usr/bin:$PATH"
  export JULIA_DEPOT_PATH="$HOME/wd/julia2/usr/share/julia"
  export JULIA_INCLUDE="$HOME/wd/julia2/usr/include/julia"
  export JULIA_INCLUDE2="$HOME/wd/julia2/usr/include"
  export JULIA_INTERNAL_INCLUDE="$HOME/wd/julia2/src"
fi
