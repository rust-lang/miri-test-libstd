#!/bin/bash
set -euo pipefail

## Run stdarch test suite with Miri.
## Assumes Miri to be installed.
## Usage:
##   ./run-stdarch-test.sh TARGET
## Environment variables:
##   MIRI_LIB_SRC: The path to the Rust `library` directory (optional).
##   RUSTFLAGS: rustc flags (optional)
##   MIRIFLAGS: Miri flags (optional)

if [ $# -ne 1 ]; then
    echo "Usage: $0 TARGET"
    exit 1
fi

export TARGET="$1"

case "$TARGET" in
i586-*|i686-*|x86_64-*)
    TARGET_RUSTFLAGS="-C target-feature=+avx2,+avx512vl,+vaes,+sse4.2"
    TEST_ARGS=(
        core_arch::x86::{sse,sse2,sse3,ssse3,sse41,sse42,avx,avx2,aes,vaes}::
        core_arch::x86_64::{sse,sse2,sse41,sse42,avx,avx2}::
        # FIXME not yet implemented
        --skip test_mm_clflush # could be implemented as a no-op?
        --skip test_mm_aeskeygenassist_si128
        --skip _stream # non-temporal stores are using inline assembly
    )
    ;;
*)
    echo "Unknown target $TARGET"
    exit 1
esac

export RUSTFLAGS="${RUSTFLAGS:-} $TARGET_RUSTFLAGS -Ainternal_features"

# Make sure all tested target features are enabled
export MIRIFLAGS="${MIRIFLAGS:-} -Zmiri-env-set=STDARCH_TEST_EVERYTHING=1"

# Set library source dir
export MIRI_LIB_SRC=${MIRI_LIB_SRC:-$(rustc --print sysroot)/lib/rustlib/src/rust/library}

export CARGO_TARGET_DIR=$(pwd)/target
cargo miri test \
    --manifest-path=$MIRI_LIB_SRC/stdarch/crates/core_arch/Cargo.toml \
    --target "$TARGET" \
    -- "${TEST_ARGS[@]}"
