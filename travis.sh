#!/bin/bash
set -euo pipefail

# apply our patch
rm -rf rust-src-patched
cp -a $(rustc --print sysroot)/lib/rustlib/src/rust/ rust-src-patched
( cd rust-src-patched && patch -f -p1 < ../rust-src.diff )

# run the tests (some also without validation, to exercise those code paths in Miri)
export RUST_SRC=rust-src-patched
echo && echo "## Testing core (without validation and Stacked Borrows)" && echo
./run-test.sh core -Zmiri-ignore-leaks -Zmiri-disable-validation -Zmiri-disable-stacked-borrows
echo && echo "## Testing core" && echo
./run-test.sh core -Zmiri-ignore-leaks
echo && echo "## Testing alloc" && echo
./run-test.sh alloc
