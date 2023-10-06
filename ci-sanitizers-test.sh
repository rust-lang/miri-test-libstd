#!/bin/bash
set -eauxo pipefail

# llvm-symbolizer supports v0 mangling
RUSTFLAGS="-Zrandomize-layout -Cdebuginfo=full -Csymbol-mangling-version=v0 \
    --cfg skip_slow_tests"

# see https://github.com/google/sanitizers/wiki/AddressSanitizerFlags
# and https://github.com/google/sanitizers/wiki/SanitizerCommonFlags
asan_opts_arr=(
    # catch bad global dependencies
    check_initialization_order=true
    # additional global checks
    strict_init_order=true
    detect_stack_use_after_return=true
    # we don't use cstrings much but it could be easy to miss the null
    strict_string_checks=true
    # give a bit of a hand tracing segfaults
    dump_instruction_bytes=true
    # detect operations on pointers to different objects
    detect_invalid_pointer_pairs=2
    # allow the allocator to return 0 (which we should generally handle well)
    # rather than crashing on OOM
    allocator_may_return_null=true
)

export ASAN_OPTIONS="${ASAN_OPTIONS:-} ${asan_opts_arr[*]}"


if [ -z "${TARGET+x}" ]; then
    echo "Env TARGET must be set"
    exit 1
fi

if [ "$#" -ne 2 ]; then
    echo "usage: TARGET=target ./this-script.sh lib-name sanitizer-name"
    exit 1
fi

# apply our patch
rm -rf rust-src-patched-san
cp -a "$(rustc --print sysroot)/lib/rustlib/src/rust/" rust-src-patched-san
( cd rust-src-patched-san && patch -f -p1 < ../rust-src-san.diff  ) ||
    ( echo "Applying rust-src-san.diff failed!" && exit 1 )
LIB_SRC="$(pwd)/rust-src-patched-san/library"
export LIB_SRC

# make sure we have symbolizer so we get useful traces
echo which llvm-symbolizer

case "$2" in
address)
    # ASAN poisons regions around allocated memory and memory that has been
    # freed, then tracks all pointer use to see whether poisoned regions are
    # accessed

    # FIXME: if on aarch64-{unknown}-linux-{android, gnu}, we can use `hwaddress`
    # instead of `address` which should be faster. Unfortunately we probably
    # don't have that in CI
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=address --cfg sanitizer=\"address\""
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
    # MSAN tracks memory initialization and gives an error if it is read before
    # being written. It is somewhat more fragile than other sanitizers
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=memory --cfg sanitizer=\"memory\""
    ;;
memtag)
    # FIXME: alternative to MSAN with the same target restrictions as hwaddress
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=memtag --cfg sanitizer=\"memory\""
    ecbo "we don't have a CI target for this yet"
    exit 1
    ;;
cfi)
    # CFI needs LTO and 1CGU, seems like randomize-layout enables `embed-bitcode=no`
    # which conflicts
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=cfi --cfg sanitizer=\"cfi\" \
        -Cembed-bitcode=yes -Clto -Ccodegen-units=1"
    ;;
kcfi)
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=kcfi --cfg sanitizer=\"cfi\""
    ;;
safestack)
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=safestack --cfg sanitizer=\"safestack\""
    ;;
shadow-call-stack)
    # FIXME: aarch64-linux-android only
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=shadow-call-stack \
        --cfg sanitizer=\"shadow-call-stack\""
    echo "we don't have a CI target for this yet"
    exit 1
    ;;
leak)
    # LeakSanitizer looks for memory leaks at the end. It is actually part of
    # ASAN so we don't really need to run it on its own. Integration test I guess?
    # https://clang.llvm.org/docs/AddressSanitizer.html#id8
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=leak --cfg sanitizer=\"leak\""
    ;;
thread)
    RUSTFLAGS="${RUSTFLAGS} -Zsanitizer=thread --cfg sanitizer=\"thread\""
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
    # SKIP="fs:: net:: process:: sys:: sys_common::net::"
    # Core modules, that we are testing on a bunch of targets.
    # These are the most OS-specific (among the modules we do not skip).
    # CORE="time:: sync:: thread:: env::"

    echo "::group::Testing std"
    ./sanitizers-run-test.sh std --target "$TARGET" --lib --tests --  \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    
    echo "::group::Testing std docs"
    ./sanitizers-run-test.sh std --target "$TARGET" --doc --  \
        2>&1 | ts -i '%.s  '
    echo "::endgroup::"
    
    # "sleep" has a thread leak that we have to ignore
    ;;
simd)
    cd "$LIB_SRC/portable-simd"
    export RUSTFLAGS="-Ainternal_features ${RUSTFLAGS}"
    export RUSTDOCFLAGS="-Ainternal_features ${RUSTDOCFLAGS:-}"

    echo "::group::Testing portable-simd"
    cargo test --lib --target "$TARGET" --tests -- 2>&1 | ts -i '%.s  '
    echo "::endgroup::"

    echo "::group::Testing portable-simd docs"
    cargo test --doc --target "$TARGET" 2>&1 | ts -i '%.s  '
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
