#!/bin/bash
set -euo pipefail

DEFAULTFLAGS="-Zrandomize-layout -Zmiri-strict-provenance"

# make sure we keep using the current toolchain even in subdirs that have a toolchain file
export RUSTUP_TOOLCHAIN=$(rustup show active-toolchain | head -n1 | cut -f 1 -d' ')

# apply our patch
rm -rf rust-src-patched
cp -a $(rustc --print sysroot)/lib/rustlib/src/rust/ rust-src-patched
( cd rust-src-patched && patch -f -p1 < ../rust-src.diff >/dev/null ) || ( echo "Applying rust-src.diff failed!" && exit 1 )
export MIRI_LIB_SRC=$(pwd)/rust-src-patched/library

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
    SKIP="fs:: net:: process:: sys::"

    # A 64bit little-endian and a 32bit big-endian target,
    # as well as targets covering all major OSes and both ABIs on Windows.
    # rustc itself tests i686-pc-windows-msvc so we test the other.
    for TARGET in x86_64-unknown-linux-gnu mips-unknown-linux-gnu aarch64-apple-darwin i686-pc-windows-gnu x86_64-pc-windows-msvc; do
        echo "::group::Testing std ($TARGET)"
        MIRIFLAGS="$DEFAULTFLAGS -Zmiri-disable-isolation" \
            ./run-test.sh std --target $TARGET --lib --tests \
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
simd)
    export CARGO_TARGET_DIR=$(pwd)/target
    export RUSTFLAGS="-Ainternal_features ${RUSTFLAGS:-}"
    export RUSTDOCFLAGS="-Ainternal_features ${RUSTDOCFLAGS:-}"
    cd $MIRI_LIB_SRC/portable-simd

    echo "::group::Testing portable-simd"
    # FIXME: disabling float non-determinism due to <https://github.com/rust-lang/portable-simd/issues/463>.
    MIRIFLAGS="$DEFAULTFLAGS -Zmiri-deterministic-floats" \
        cargo miri test --lib --tests -- --skip ptr \
        2>&1 | ts -i '%.s  '
    # This contains some pointer tests that do int/ptr casts, so we need permissive provenance.
    MIRIFLAGS="$DEFAULTFLAGS -Zmiri-permissive-provenance" \
        cargo miri test --lib --tests -- ptr \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    echo "::group::Testing portable-simd docs"
    MIRIFLAGS="$DEFAULTFLAGS" \
        cargo miri test --doc \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
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
