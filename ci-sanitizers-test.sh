#!/bin/bash
set -eauxo pipefail

DEFAULTFLAGS="-Zrandomize-layout"

if [ -Z "${TARGET+x}" ]; then
    echo "Env TARGET must be set"
    exit 1
fi

# apply our patch
rm -rf rust-src-patched
cp -a "$(rustc --print sysroot)/lib/rustlib/src/rust/" rust-src-patched
( cd rust-src-patched && patch -f -p1 < ../rust-src.diff >/dev/null ) || ( echo "Applying rust-src.diff failed!" && exit 1 )
LIB_SRC="$(pwd)/rust-src-patched/library"
export LIB_SRC

case "$2" in
address)
    # FIXME: if on aarch64-{unknown}-linux-{android, gnu}, we can use `hwaddress`
    # instead of `address` which should be faster. Unfortunately we probably
    # don't have that in CI
    SANITIZER=address
    ;;
hwaddress)
    # see above
    echo "we don't have a CI target for this yet"
    exit 1
    ;;
kasan)
    echo "we aren't a kernel, can't use kasan"
    exit 1
    ;;
memory)
    SANITIZER=memory
    ;;
memtag)
    # FIXME: alternative to MSAN with the same target restrictions as hwaddress
    SANITIZER=memtag
    ecbo "we don't have a CI target for this yet"
    exit 1
    ;;
cfi)
    SANITIZER=cfi
    # cfi needs LTO
    EXTRAFLAGS="-Clto"
    ;;
kcfi)
    SANITIZER=kcfi
    ;;
safestack)
    # FIXME: aarch64-linux-android only
    SANITIZER=safestack
    ;;
shadow-call-stack)
    SANITIZER=shadow-call-stack
    echo "we don't have a CI target for this yet"
    exit 1
    ;;
leak)
    SANITIZER=leak
    ;;
thread)
    SANITIZER=thread
    ;;
*)
    echo "unknown sanitizer $2"
    exit 1
esac

export RUSTFLAGS="$DEFAULTFLAGS -Zsanitizer=$SANITIZER $EXTRAFLAGS"

echo "Running tests with sanitizer=$SANITIZER on target $TARGET"

# run the tests (some also without validation, to exercise those code paths in Miri)
case "$1" in
core)
    echo "::group::Testing core"
    ./run-test.sh core --target "$TARGET" --lib --tests -- --skip align \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    
    echo "::group::Testing core"
    ./run-test.sh core --target "$TARGET" --lib --tests \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    
    echo "::group::Testing core docs" && echo
    ./run-test.sh core --target "$TARGET" --doc \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    ;;
alloc)
    echo "::group::Testing alloc"
        ./run-test.sh alloc --target "$TARGET" --lib --tests \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"

    echo "::group::Testing alloc docs"
        ./run-test.sh alloc --target "$TARGET" --doc \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    ;;
std)
    # Modules that we skip entirely, because they need a lot of shims we don't support.
    SKIP="fs:: net:: process:: sys:: sys_common::net::"
    # Core modules, that we are testing on a bunch of targets.
    # These are the most OS-specific (among the modules we do not skip).
    CORE="time:: sync:: thread:: env::"

    echo "::group::Testing std core ($CORE on $TARGET)"
    ./run-test.sh std --target "$TARGET" --lib --tests \
        -- $CORE \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    
    echo "::group::Testing std core docs ($CORE on $TARGET, $SANITIZER)"
        ./run-test.sh std --target "$TARGET" --doc \
        -- $CORE \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    
    # "sleep" has a thread leak that we have to ignore
    echo "::group::Testing remaining std (all except for $SKIP, $SANITIZER)"
        ./run-test.sh std --lib --tests \
        2>&1 | ts -i '%.s  '
        # -- $(for M in $CORE; do echo "--skip $M "; done) $(for M in $SKIP; do echo "--skip $M "; done) \
    echo "::endgroup::"
    
    echo "::group::Testing remaining std docs (all except for $SKIP, $SANITIZER)"
        ./run-test.sh std --doc \
        2>&1 | ts -i '%.s  '
        # -- $(for M in $CORE; do echo "--skip $M "; done) $(for M in $SKIP; do echo "--skip $M "; done) \
    echo "::endgroup::"
    ;;
simd)
    cd "$LIB_SRC/portable-simd"
    export RUSTFLAGS="-Ainternal_features ${RUSTFLAGS}"
    export RUSTDOCFLAGS="-Ainternal_features ${RUSTDOCFLAGS:-}"

    echo "::group::Testing portable-simd"
    cargo test --lib --tests -- --skip ptr 2>&1 | ts -i '%.s  '
    # This contains some pointer tests that do int/ptr casts, so we need permissive provenance.
    cargo test --lib --tests -- ptr 2>&1 | ts -i '%.s  '
    echo "::endgroup::"

    echo "::group::Testing portable-simd docs"
    cargo test --doc 2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    ;;
stdarch)
    echo "::group::Testing stdarch"
    ./run-stdarch-test.sh "$TARGET" 2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    ;;
*)
    echo "Unknown command"
    exit 1
esac
