#!/bin/bash
set -euo pipefail

# apply our patch
rm -rf rust-src-patched
cp -a $(rustc --print sysroot)/lib/rustlib/src/rust/ rust-src-patched
( cd rust-src-patched && patch -f -p1 < ../rust-src.diff )

# run the tests (some also without validation, to exercise those code paths in Miri)
export RUST_SRC=rust-src-patched
echo && echo "## Testing core (no validation, no Stacked Borrows, symbolic alignment)" && echo
./run-test.sh core -Zmiri-disable-validation -Zmiri-disable-stacked-borrows -Zmiri-symbolic-alignment-check -- --skip align 2>&1 | ts -i '%.s  '
echo && echo "## Testing core" && echo
./run-test.sh core 2>&1 | ts -i '%.s  '
echo && echo "## Testing alloc (symbolic alignment)" && echo
./run-test.sh alloc -Zmiri-symbolic-alignment-check 2>&1 | ts -i '%.s  '
