#!/bin/bash
set -euo pipefail

# apply our patch
rm -rf rust-src-patched
cp -a $(rustc --print sysroot)/lib/rustlib/src/rust/ rust-src-patched
( cd rust-src-patched && patch -f -p1 < ../rust-src.diff )
export MIRI_LIB_SRC=$(pwd)/rust-src-patched/library

# run the tests (some also without validation, to exercise those code paths in Miri)
case "$1" in
core)
    echo && echo "## Testing core (no validation, no Stacked Borrows, symbolic alignment)" && echo
    MIRIFLAGS="-Zmiri-disable-validation -Zmiri-disable-stacked-borrows -Zmiri-symbolic-alignment-check" \
        ./run-test.sh core --lib --tests \
        -- --skip align \
        2>&1 | ts -i '%.s  '
    echo && echo "## Testing core (strict provenance)" && echo
    MIRIFLAGS="-Zmiri-strict-provenance" \
        ./run-test.sh core --lib --tests \
        2>&1 | ts -i '%.s  '
    # Cannot use strict provenance as there are int-to-ptr casts in the doctests.
    echo && echo "## Testing core docs" && echo
    MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation" \
        ./run-test.sh core --doc \
        2>&1 | ts -i '%.s  '
    ;;
alloc)
    echo && echo "## Testing alloc (symbolic alignment, strict provenance)" && echo
    MIRIFLAGS="-Zmiri-symbolic-alignment-check -Zmiri-strict-provenance" \
        ./run-test.sh alloc --lib --tests \
        2>&1 | ts -i '%.s  '
    echo && echo "## Testing alloc docs (strict provenance)" && echo
    MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation -Zmiri-strict-provenance" \
        ./run-test.sh alloc --doc \
        2>&1 | ts -i '%.s  '
    ;;
std)
    # Only test a few things here with permissive flags, we are still testing the waters.
    MODULES="env:: ffi:: buffered:: sync:: thread:: error:: collections:: backtrace::"
    echo && echo "## Testing std ($MODULES)" && echo
    MIRIFLAGS="-Zmiri-disable-isolation -Zmiri-permissive-provenance" \
        ./run-test.sh std --lib --tests \
        -- $MODULES \
        2>&1 | ts -i '%.s  '
    echo && echo "## Testing std docs ($MODULES)" && echo
    MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation -Zmiri-permissive-provenance" \
        ./run-test.sh std --doc \
        -- $MODULES \
        2>&1 | ts -i '%.s  '
    ;;
simd)
    cd $MIRI_LIB_SRC/portable-simd
    echo && echo "## Testing portable-simd (strict provenance)" && echo
    MIRIFLAGS="-Zmiri-strict-provenance" \
        cargo miri test --lib --tests \
        2>&1 | ts -i '%.s  '
    echo && echo "## Testing portable-simd docs (strict provenance)" && echo
    MIRIFLAGS="-Zmiri-strict-provenance" \
        cargo miri test --doc \
        2>&1 | ts -i '%.s  '
    ;;
*)
    echo "Unknown command"
    exit 1
esac
