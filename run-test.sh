#!/bin/bash
set -euo pipefail
#set -x

## Run a Rust libstd test suite with Miri.
## Assumes Miri to be installed.
## Usage:
##   ./run-test.sh CRATE_NAME CARGO_TEST_ARGS
## Environment variables:
##   RUST_SRC: The path to the Rust source directory (containing `src`).
##     Defaults to `$(rustc --print sysroot)/lib/rustlib/src/rust` or
##     `$(rustc --print sysroot)/../../..`, which ever exists.  (The former
##     works for distributed toolchains, the latter for locally built ones.)

CRATE=${1:-}
if [[ -z "$CRATE" ]]; then
    echo "Usage: $0 CRATE_NAME"
    exit 1
fi
shift

DEFAULT_RUST_SRC=$(rustc --print sysroot)/lib/rustlib/src/rust
RUST_SRC=${RUST_SRC:-$DEFAULT_RUST_SRC}
if ! test -f "$RUST_SRC/Cargo.lock"; then
    echo "Rust source dir ($RUST_SRC) does not contain a Cargo.lock file."
    echo "Set RUST_SRC to the Rust source directory, or install the rust-src component."
    exit 1
fi
if readlink -e . &>/dev/null; then
    RUST_SRC=$(readlink -e "$RUST_SRC")
fi

# update symlink
rm -f lib$CRATE
ln -s "$RUST_SRC"/library/$CRATE lib$CRATE

# run test
cd ${CRATE}_miri_test
XARGO_RUST_SRC="$RUST_SRC/library" cargo miri setup
MIRI_SYSROOT=~/.cache/miri/HOST cargo miri test "$@"
