#!/bin/bash
set -euo pipefail

function begingroup {
  echo "::group::$@"
  set -x
}
function endgroup {
  set +x
  echo "::endgroup"
}

# Miri flags we apply everywhere
DEFAULTFLAGS="-Zrandomize-layout -Zmiri-strict-provenance"

# Some doctests don't work with the new trait solver.
export RUSTDOCFLAGS="-Znext-solver=coherence"

# make sure we keep using the current toolchain even in subdirs that have a toolchain file
export RUSTUP_TOOLCHAIN=$(rustup show active-toolchain | head -n1 | cut -f 1 -d' ')

# apply our patch
rm -rf rust-src-patched
cp -a $(rustc --print sysroot)/lib/rustlib/src/rust/ rust-src-patched
( cd rust-src-patched && patch -f -p1 < ../rust-src.diff >/dev/null ) || ( echo "Applying rust-src.diff failed!" && exit 1 )
export MIRI_LIB_SRC=$(pwd)/rust-src-patched/library

# We're not using nextest as that's very slow due to
# <https://github.com/rust-lang/miri/issues/5013>.

# run the tests (some also without validation, to exercise those code paths in Miri)
case "$1" in
core)
    # A 64bit little-endian and a 32bit big-endian target.
    # (Varying the OS is totally pointless for core.)
    for TARGET in x86_64-unknown-linux-gnu mips-unknown-linux-gnu; do
        begingroup "./run-test core --tests ($TARGET, no validation, no Stacked Borrows, symbolic alignment)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-validation -Zmiri-disable-stacked-borrows -Zmiri-symbolic-alignment-check" \
            ./run-test.sh core --target $TARGET --tests \
            -- --skip align \
            2>&1 | ts -i '%.s  '
        endgroup
        begingroup "./run-test core --tests ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS" \
            ./run-test.sh core --target $TARGET --tests \
            2>&1 | ts -i '%.s  '
        endgroup
        begingroup "./run-test core --doc ($TARGET)" && echo
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation" \
            ./run-test.sh core --target $TARGET --doc \
            2>&1 | ts -i '%.s  '
        endgroup
    done
    ;;
alloc)
    # A 64bit little-endian and a 32bit big-endian target.
    # (Varying the OS is not really worth it for alloc.)
    for TARGET in x86_64-unknown-linux-gnu mips-unknown-linux-gnu; do
        begingroup "./run-test alloc --tests ($TARGET, symbolic alignment)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-symbolic-alignment-check" \
            ./run-test.sh alloc --target $TARGET --tests \
            2>&1 | ts -i '%.s  '
        endgroup
        begingroup "./run-test alloc --doc ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation" \
            ./run-test.sh alloc --target $TARGET --doc \
            2>&1 | ts -i '%.s  '
        endgroup
    done
    ;;
std)
    # Rust CI already runs all tests (on Linux and macOS) that are not excluded via
    # `skip_missing_miri_shims`. There is no point in us repeating that here. Instead we run *all*
    # tests except those in a few modules. This is what we aim to support on all tier 1 targets.
    SKIP_MODULES="fs:: net:: process:: sys:: os::"
    # For integration tests, we cannot have an exclusion list, so we list the supported tests.
    SUPPORTED_INTEGRATION_TESTS="env env_modify error istr num path sync sync_view time thread thread_local"
    # FIXME: need to temporarily disable some tests until Miri is fixed.
    DEFAULTFLAGS="$DEFAULTFLAGS --cfg skip_unsupported_miri_tests"

    # A 64bit little-endian and a 32bit big-endian target,
    # as well as targets covering all tier 1 OSes and both ABIs on Windows.
    for TARGET in x86_64-unknown-linux-gnu mips-unknown-linux-gnu aarch64-apple-darwin i686-pc-windows-msvc x86_64-pc-windows-gnu; do
        begingroup "./run-test std --lib ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation" \
            ./run-test.sh std --target $TARGET --lib \
            -- $(for M in $SKIP_MODULES; do echo "--skip $M "; done) \
            2>&1 | ts -i '%.s  '
        endgroup
        begingroup "./run-test std --test ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation" \
            ./run-test.sh std --target $TARGET \
            $(for T in $SUPPORTED_INTEGRATION_TESTS; do echo "--test $T "; done) \
            2>&1 | ts -i '%.s  '
        endgroup
        begingroup "./run-test std --doc ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation" \
            ./run-test.sh std --target $TARGET --doc \
            -- $(for M in $SKIP_MODULES; do echo "--skip $M "; done) \
            2>&1 | ts -i '%.s  '
        endgroup
    done
    ;;
std-all)
    # Are we std yet? Run all tests in nextest ignoring failures. Skip what we already handle above.
    begingroup "run all std unit/integration tests"
    MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation -Zmiri-no-short-fd-operations" USE_NEXTEST=1 \
        ./run-test.sh std --no-fail-fast --config-file .config/nextest.toml \
        || true
    endgroup
    # And don't forget the doc tests.
    begingroup "run all std doc tests"
    MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation  -Zmiri-no-short-fd-operations" \
        ./run-test.sh std --no-fail-fast --doc \
        || true
    endgroup
    ;;
simd)
    export RUSTFLAGS="-Ainternal_features ${RUSTFLAGS:-}"
    export RUSTDOCFLAGS="-Ainternal_features ${RUSTDOCFLAGS:-}"
    export CARGO_TARGET_DIR=$(pwd)/target
    MANIFEST="$MIRI_LIB_SRC/portable-simd/Cargo.toml"

    # FIXME: disabling float non-determinism due to <https://github.com/rust-lang/portable-simd/issues/463>.
    MIRIFLAGS="$DEFAULTFLAGS -Zmiri-deterministic-floats" \
        cargo miri test --manifest-path "$MANIFEST" --tests -- --skip ptr \
        2>&1 | ts -i '%.s  '
    # This contains some pointer tests that do int/ptr casts, so we need permissive provenance.
    MIRIFLAGS="$DEFAULTFLAGS -Zmiri-permissive-provenance" \
        cargo miri test --manifest-path "$MANIFEST" --tests -- ptr \
        2>&1 | ts -i '%.s  '
    # No need to run the doc tests: they are included in libcore.
    ;;
stdarch)
    for TARGET in x86_64-unknown-linux-gnu i686-unknown-linux-gnu; do
        begingroup "Testing stdarch ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS" \
            ./run-stdarch-test.sh $TARGET \
            2>&1 | ts -i '%.s  '
        endgroup
    done
    ;;
*)
    echo "Unknown command"
    exit 1
esac
