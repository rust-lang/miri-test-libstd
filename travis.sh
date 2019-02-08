#!/bin/bash
set -euo pipefail

export RUST_SRC=$(rustc --print sysroot)/lib/rustlib/src/rust/src

# apply our patch
PATCH=$(readlink -e rust-src.diff)
{ cd $RUST_SRC && patch -p1 < $PATCH }

# run the tests
./run-test.sh core
./run-test.sh alloc
