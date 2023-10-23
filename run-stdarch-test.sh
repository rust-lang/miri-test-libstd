#!/bin/bash
set -euo pipefail

## Run stdarch test suite with Miri.
## Assumes Miri to be installed.
## Usage:
##   ./run-test.sh TARGET
## Environment variables:
##   MIRI_LIB_SRC: The path to the Rust library directory (`library`).
##   RUSTFLAGS: rustc flags (optional)
##   MIRIFLAGS: Miri flags (optional)

if [ $# -ne 1 ]; then
    echo "Usage: $0 TARGET"
    exit 1
fi

export TARGET="$1"

case "$TARGET" in
i586-*|i686-*|x86_64-*)
    RUSTFLAGS="-C target-feature=+ssse3,+avx512vl,+vaes"
    TEST_ARGS=(
        core_arch::x86::{sse,sse2,sse3,ssse3,aes,vaes}::
        core_arch::x86_64::{sse,sse2}::
        # FIXME not yet implemented
        --skip test_mm_clflush # could be implemented as a no-op?
        --skip test_mm_aeskeygenassist_si128
    )
    ;;
*)
    echo "Unknown target $TARGET"
    exit 1
esac

export RUSTFLAGS="${RUSTFLAGS:-} -Ainternal_features"

# Make sure all tested target features are enabled
export STDARCH_TEST_EVERYTHING=1
# Needed to pass the STDARCH_TEST_EVERYTHING environment variable
export MIRIFLAGS="${MIRIFLAGS:-} -Zmiri-disable-isolation"

cd $MIRI_LIB_SRC/stdarch
cargo miri test \
    --target "$TARGET" \
    --manifest-path=crates/core_arch/Cargo.toml \
    -- "${TEST_ARGS[@]}"
