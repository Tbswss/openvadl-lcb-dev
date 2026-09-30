#!/usr/bin/env bash

set -e

cd /compiler-explorer && make EXTRA_ARGS='--language c' 2>&1 > /dev/null  & 

# needed by embench
ln -svf /openvadl/output/lcb /src 2>&1 > /dev/null
ln -svf /openvadl/vadl/test/resources/embench /src/embench 2>&1 > /dev/null
ln -svf /openvadl/vadl/test/resources/embench /embench 2>&1 > /dev/null
