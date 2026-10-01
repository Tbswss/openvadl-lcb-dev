#!/usr/bin/env bash

#
# add the embench files as "examples" to compiler explorer, making them
# easier to access
#

mkdir -p /compiler-explorer/embench-examples/c
for f in /embench/src/*/*.c; do
  bench=$(basename "$(dirname "$f")")
  ln -sf "$f" "/compiler-explorer/embench-examples/c/${bench}_$(basename "$f")"
done
