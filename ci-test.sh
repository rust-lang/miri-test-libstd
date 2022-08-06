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
    # A 64bit little-endian and a 32bit big-endian target.
    # (Varying the OS is totally pointless for core.)
    for TARGET in x86_64-unknown-linux-gnu mips-unknown-linux-gnu; do
        echo && echo "## Testing core ($TARGET, no validation, no Stacked Borrows, symbolic alignment)" && echo
        MIRIFLAGS="-Zmiri-disable-validation -Zmiri-disable-stacked-borrows -Zmiri-symbolic-alignment-check" \
            ./run-test.sh core --target $TARGET --lib --tests \
            -- --skip align \
            2>&1 | ts -i '%.s  '
        echo && echo "## Testing core ($TARGET, strict provenance)" && echo
        MIRIFLAGS="-Zmiri-strict-provenance" \
            ./run-test.sh core --target $TARGET --lib --tests \
            2>&1 | ts -i '%.s  '
        # Cannot use strict provenance as there are int-to-ptr casts in the doctests.
        echo && echo "## Testing core docs ($TARGET)" && echo
        MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation" \
            ./run-test.sh core --target $TARGET --doc \
            2>&1 | ts -i '%.s  '
    done
    ;;
alloc)
    # A 64bit little-endian and a 32bit big-endian target.
    # (Varying the OS is not really worth it for alloc.)
    for TARGET in x86_64-unknown-linux-gnu mips-unknown-linux-gnu; do
        echo && echo "## Testing alloc ($TARGET, symbolic alignment, strict provenance)" && echo
        MIRIFLAGS="-Zmiri-symbolic-alignment-check -Zmiri-strict-provenance" \
            ./run-test.sh alloc --target $TARGET --lib --tests \
            2>&1 | ts -i '%.s  '
        echo && echo "## Testing alloc docs ($TARGET, strict provenance)" && echo
        MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation -Zmiri-strict-provenance" \
            ./run-test.sh alloc --target $TARGET --doc \
            2>&1 | ts -i '%.s  '
    done
    ;;
std)
    # Core modules, that we are testing on a bunch of targets. These are the most OS-specific.
    # TODO: add env:: here once https://github.com/rust-lang/miri/pull/2470l propagates.
    CORE="time:: sync:: thread::"
    # Modules that we skip entirely, because they need a lot of thims we don't support.
    # TODO: remove most of these once some PRs propagate.
    # - f32, f64: needs https://github.com/rust-lang/miri/pull/2469
    # - io::error: needs https://github.com/rust-lang/miri/pull/2465
    # Additionally we skip some of the integration tests:
    # - env_home_dir: needs https://github.com/rust-lang/miri/pull/2467
    # - sleep: needs https://github.com/rust-lang/miri/pull/2466
    SKIP="fs:: net:: process:: sys:: sys_common::net:: f32:: f64:: io::error:: env_home_dir sleep"

    # hashbrown and some other things do int2ptr casts, so we need permissive provenance.
    for TARGET in x86_64-unknown-linux-gnu aarch64-apple-darwin; do
        echo "::group::Testing std core ($CORE on $TARGET)"
        MIRIFLAGS="-Zmiri-disable-isolation -Zmiri-permissive-provenance" \
            ./run-test.sh std --target $TARGET --lib --tests \
            -- $CORE \
            2>&1 | ts -i '%.s  '
        echo "::endgroup::"
        echo "::group::Testing std core docs ($CORE on $TARGET)"
        MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation -Zmiri-permissive-provenance" \
            ./run-test.sh std --target $TARGET --doc \
            -- $CORE \
            2>&1 | ts -i '%.s  '
        echo "::endgroup::"
    done
    echo "::group::Testing remaining std (except for $SKIP)"
    MIRIFLAGS="-Zmiri-disable-isolation -Zmiri-permissive-provenance" \
        ./run-test.sh std --lib --tests \
        -- $(for M in $CORE; do echo "--skip $M "; done) $(for M in $SKIP; do echo "--skip $M "; done) \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    echo "::group::Testing remaining std docs (except for $SKIP)"
    MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation -Zmiri-permissive-provenance" \
        ./run-test.sh std --doc \
        -- $(for M in $CORE; do echo "--skip $M "; done) $(for M in $SKIP; do echo "--skip $M "; done) \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
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
