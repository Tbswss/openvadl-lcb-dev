#!/usr/bin/env bash

#
# generate `lcb-` prefixed symlinks to all lcb-generated binaries.
# e.g. lcb-clang will link to the lcb generated clang binary
#     same goes for all other binaries, e.g. `lcb-llc`, etc.
#

set -euo pipefail

SRC_DIR="/src/llvm-final/build/bin"
DEST_DIR="/usr/local/bin"

[ -d "$SRC_DIR" ] || { echo "warning: $SRC_DIR not found, skipping lcb-* aliases" >&2; exit 0; }

for bin in "$SRC_DIR"/*; do
  [ -f "$bin" ] && [ -x "$bin" ] || continue
  ln -sfv "$bin" "$DEST_DIR/lcb-$(basename "$bin")" 2>&1 > /dev/null
done

