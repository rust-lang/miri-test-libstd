#!/bin/bash
set -euo pipefail

# Miri flags we apply everywhere
DEFAULTFLAGS="-Zrandomize-layout -Zmiri-strict-provenance"

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
        # There are no library tests in core, and the integration tests are in a separate crate.
        echo "::group::Testing coretests ($TARGET, no validation, no Stacked Borrows, symbolic alignment)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-validation -Zmiri-disable-stacked-borrows -Zmiri-symbolic-alignment-check" \
            ./run-test.sh coretests --target $TARGET --tests \
            -- --skip align \
            2>&1 | ts -i '%.s  '
        echo "::endgroup::"
        echo "::group::Testing coretests ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS" \
            ./run-test.sh coretests --target $TARGET --tests \
            2>&1 | ts -i '%.s  '
        echo "::endgroup::"
        echo "::group::Testing core docs ($TARGET)" && echo
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation" \
            ./run-test.sh core --target $TARGET --doc \
            2>&1 | ts -i '%.s  '
        echo "::endgroup::"
    done
    ;;
alloc)
    # A 64bit little-endian and a 32bit big-endian target.
    # (Varying the OS is not really worth it for alloc.)
    for TARGET in x86_64-unknown-linux-gnu mips-unknown-linux-gnu; do
        echo "::group::Testing alloctests ($TARGET, symbolic alignment)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-symbolic-alignment-check" \
            ./run-test.sh alloctests --target $TARGET --tests \
            2>&1 | ts -i '%.s  '
        echo "::endgroup::"
        echo "::group::Testing alloc docs ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation" \
            ./run-test.sh alloc --target $TARGET --doc \
            2>&1 | ts -i '%.s  '
        echo "::endgroup::"
    done
    ;;
std)
    # Modules that we skip because they need a lot of shims we don't support.
    SKIP="fs:: net:: process:: sys:: os::windows::"

    # A 64bit little-endian and a 32bit big-endian target,
    # as well as targets covering all major OSes and both ABIs on Windows.
    # rustc itself tests i686-pc-windows-msvc so we test the other.
    for TARGET in x86_64-unknown-linux-gnu mips-unknown-linux-gnu aarch64-apple-darwin i686-pc-windows-gnu x86_64-pc-windows-msvc; do
        echo "::group::Testing std ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation" \
            ./run-test.sh std --target $TARGET --tests \
            -- $(for M in $SKIP; do echo "--skip $M "; done) \
            2>&1 | ts -i '%.s  '
        echo "::endgroup::"
        echo "::group::Testing std docs ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation" \
            ./run-test.sh std --target $TARGET --doc \
            -- $(for M in $SKIP; do echo "--skip $M "; done) \
            2>&1 | ts -i '%.s  '
        echo "::endgroup::"
    done
    ;;
std-all)
    # Are we std yet? Run the tests we are skipping above.
    MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation -Zmiri-no-short-fd-operations" USE_NEXTEST=1 \
        ./run-test.sh std --no-fail-fast --config-file .config/nextest.toml \
        -- fs:: net:: process:: sys:: || true
    # And don't forget the doc tests.
    MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation  -Zmiri-no-short-fd-operations" \
        ./run-test.sh std --no-fail-fast --doc -- fs:: net:: process:: sys:: || true
    ;;
simd)
    export RUSTFLAGS="-Ainternal_features ${RUSTFLAGS:-}"
    export RUSTDOCFLAGS="-Ainternal_features ${RUSTDOCFLAGS:-}"
    export CARGO_TARGET_DIR=$(pwd)/target
    MANIFEST="$MIRI_LIB_SRC/portable-simd/Cargo.toml"

    echo "::group::Testing portable-simd"
    # FIXME: disabling float non-determinism due to <https://github.com/rust-lang/portable-simd/issues/463>.
    MIRIFLAGS="$DEFAULTFLAGS -Zmiri-deterministic-floats" \
        cargo miri test --manifest-path "$MANIFEST" --tests -- --skip ptr \
        2>&1 | ts -i '%.s  '
    # This contains some pointer tests that do int/ptr casts, so we need permissive provenance.
    MIRIFLAGS="$DEFAULTFLAGS -Zmiri-permissive-provenance" \
        cargo miri test --manifest-path "$MANIFEST" --tests -- ptr \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    # No need to run the doc tests: they are included in libcore.
    ;;
stdarch)
    for TARGET in x86_64-unknown-linux-gnu i686-unknown-linux-gnu; do
        echo "::group::Testing stdarch ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS" \
            ./run-stdarch-test.sh $TARGET \
            2>&1 | ts -i '%.s  '
        echo "::endgroup::"
    done
    ;;
*)
    echo "Unknown command"
    exit 1
esac
