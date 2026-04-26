#!/usr/bin/env bash

# 1. Load the necessary tools into the environment
if command -v module >/dev/null 2>&1; then
  module purge
fi
source $GFDL_BASE/src/extra/env/$GFDL_ENV
if command -v module >/dev/null 2>&1; then
  module list
fi

# Run with input file as input taken from BASH script
echo ${1}
exec ${1}/mppnccombine.x ${2}
