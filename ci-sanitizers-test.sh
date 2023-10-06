#!/bin/bash
set -eauxo pipefail

RUSTFLAGS="-Zrandomize-layout"

if [ -z "${TARGET+x}" ]; then
    echo "Env TARGET must be set"
    exit 1
fi

if [ "$#" -ne 2 ]; then
    echo "usage: TARGET=target ./this-script.sh lib-name sanitizer-name"
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
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=address"
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
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=memory"
    ;;
memtag)
    # FIXME: alternative to MSAN with the same target restrictions as hwaddress
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=memtag"
    ecbo "we don't have a CI target for this yet"
    exit 1
    ;;
cfi)
    # CFI needs LTO and 1CGU, seems like randomize-layout enables `embed-bitcode=no`
    # which conflicts
    RUSTFLAGS=${RUSTFLAGS//-Zrandomize-layout/}
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=cfi -Clto -Ccodegen-units=1"
    ;;
kcfi)
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=kcfi"
    ;;
safestack)
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=safestack"
    ;;
shadow-call-stack)
    # FIXME: aarch64-linux-android only
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=shadow-call-stack"
    echo "we don't have a CI target for this yet"
    exit 1
    ;;
leak)
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=leak"
    ;;
thread)
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=thread"
    ;;
*)
    echo "unknown sanitizer $2"
    exit 1
esac

echo "Running tests with on target $TARGET with flags '$RUSTFLAGS'"

# run the tests (some also without validation, to exercise those code paths in Miri)
case "$1" in
core)
    echo "::group::Testing core"
    ./sanitizers-run-test.sh core --target "$TARGET" --lib --tests -- --skip align \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    
    echo "::group::Testing core"
    ./sanitizers-run-test.sh core --target "$TARGET" --lib --tests \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    
    echo "::group::Testing core docs" && echo
    ./sanitizers-run-test.sh core --target "$TARGET" --doc \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    ;;
alloc)
    echo "::group::Testing alloc"
    ./sanitizers-run-test.sh alloc --target "$TARGET" --lib --tests \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"

    echo "::group::Testing alloc docs"
    ./sanitizers-run-test.sh alloc --target "$TARGET" --doc \
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
    ./sanitizers-run-test.sh std --target "$TARGET" --lib --tests -- "$CORE" \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    
    echo "::group::Testing std core docs ($CORE on $TARGET, $SANITIZER)"
    ./sanitizers-run-test.sh std --target "$TARGET" --doc -- "$CORE" \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    
    # "sleep" has a thread leak that we have to ignore
    echo "::group::Testing remaining std (all except for $SKIP, $SANITIZER)"
    ./sanitizers-run-test.sh std --lib --tests \
        2>&1 | ts -i '%.s  '
        # -- $(for M in $CORE; do echo "--skip $M "; done) $(for M in $SKIP; do echo "--skip $M "; done) \
    echo "::endgroup::"
    
    echo "::group::Testing remaining std docs (all except for $SKIP, $SANITIZER)"
    ./sanitizers-run-test.sh std --doc \
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
    ./sanitizers-run-stdarch-test.sh "$TARGET" 2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    ;;
*)
    echo "Unknown command"
    exit 1
esac
