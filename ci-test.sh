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
             ./run-test.sh core --all-targets -- --skip align 2>&1 | ts -i '%.s  '
    echo && echo "## Testing core (strict provenance, number validity)" && echo
    MIRIFLAGS="-Zmiri-strict-provenance -Zmiri-check-number-validity" \
             ./run-test.sh core --all-targets 2>&1 | ts -i '%.s  '
    # No number validity because of portable-simd scatter/gather (https://github.com/rust-lang/portable-simd/issues/271)
    echo && echo "## Testing core docs" && echo
    MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation" \
             ./run-test.sh core --doc
    ;;
alloc)
    echo && echo "## Testing alloc (symbolic alignment, strict provenance, number validity)" && echo
    MIRIFLAGS="-Zmiri-symbolic-alignment-check -Zmiri-strict-provenance -Zmiri-check-number-validity" \
             ./run-test.sh alloc --all-targets 2>&1 | ts -i '%.s  '
    echo && echo "## Testing alloc docs (number validity)" && echo
    MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation -Zmiri-check-number-validity" \
             ./run-test.sh alloc --doc
    ;;
simd)
    cd $MIRI_LIB_SRC/portable-simd
    echo && echo "## Testing portable-simd (strict provenance, number validity)" && echo
    MIRIFLAGS="-Zmiri-strict-provenance -Zmiri-check-number-validity" \
      cargo miri test --all-targets
    # No number validity because of scatter/gather (https://github.com/rust-lang/portable-simd/issues/271)
    echo && echo "## Testing portable-simd docs" && echo
    cargo miri test --doc
    ;;
*)
    echo "Unknown command"
    exit 1
esac
