#!/bin/bash
set -euo pipefail

# apply our patch
rm -rf rust-src-patched
cp -a $(rustc --print sysroot)/lib/rustlib/src/rust/ rust-src-patched
( cd rust-src-patched && patch -f -p1 < ../rust-src.diff )

# run the tests (some also without validation, to exercise those code paths in Miri)
export RUST_SRC=rust-src-patched

# libcore
echo && echo "## Testing core (no validation, no Stacked Borrows, symbolic alignment)" && echo
MIRIFLAGS="-Zmiri-disable-validation -Zmiri-disable-stacked-borrows -Zmiri-symbolic-alignment-check" \
  ./run-test.sh core --all-targets -- --skip align 2>&1 | ts -i '%.s  '
echo && echo "## Testing core" && echo
MIRIFLAGS="" \
  ./run-test.sh core --all-targets 2>&1 | ts -i '%.s  '
echo && echo "## Testing core (doctests)" && echo
MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation" \
  ./run-test.sh core --doc

# liballoc
echo && echo "## Testing alloc (symbolic alignment)" && echo
MIRIFLAGS="-Zmiri-symbolic-alignment-check" \
  ./run-test.sh alloc --all-targets 2>&1 | ts -i '%.s  '
echo && echo "## Testing alloc (doctests)" && echo
MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation" \
  ./run-test.sh alloc --doc
