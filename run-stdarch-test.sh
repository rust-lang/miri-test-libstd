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
    RUSTFLAGS="-C target-feature=+ssse3"
    TEST_ARGS=(
        core_arch::x86::{sse,sse2,sse3,ssse3}::
        core_arch::x86_64::{sse,sse2}::
        # FIXME add `#[cfg_attr(miri, ignore)]` to those tests in stdarch
        # These are nontemporal stores, fences, and CSR (FP env status register) accesses
        --skip test_mm_comieq_ss_vs_ucomieq_ss
        --skip test_mm_getcsr_setcsr_1
        --skip test_mm_getcsr_setcsr_2
        --skip test_mm_getcsr_setcsr_underflow
        --skip test_mm_sfence
        --skip test_mm_stream_ps
        --skip test_mm_clflush
        --skip test_mm_lfence
        --skip test_mm_maskmoveu_si128
        --skip test_mm_mfence
        --skip test_mm_stream_pd
        --skip test_mm_stream_si128
        --skip test_mm_stream_si32
        --skip test_mm_stream_si64
        # FIXME fix those in stdarch
        --skip test_mm_rcp_ss # __m128(0.24997461, 13.0, 16.0, 100.0) != __m128(0.24993896, 13.0, 16.0, 100.0)
        --skip test_mm_store1_ps # attempt to subtract with overflow
        --skip test_mm_store_ps # attempt to subtract with overflow
        --skip test_mm_storer_ps # attempt to subtract with overflow
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
