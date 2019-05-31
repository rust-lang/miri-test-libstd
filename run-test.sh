#!/bin/bash
set -euo pipefail
#set -x

## Run a Rust libstd test suite with Miri.
## Assumes Miri to be installed.
## Usage:
##   ./run-test.sh CRATE_NAME
## Environment variables:
##   RUST_SRC: The path to the Rust source directory (containing `src`).
##     Defaults to `$(rustc --print sysroot)/lib/rustlib/src/rust`.

CRATE=${1:-}
if [[ -z "$CRATE" ]]; then
    echo "Usage: $0 CRATE_NAME"
    exit 1
fi
shift

RUST_SRC=${RUST_SRC:-$(rustc --print sysroot)/lib/rustlib/src/rust}
if ! test -d "$RUST_SRC"; then
   echo "Rust source dir ($RUST_SRC) does not exist"
   exit 1
fi
RUST_SRC=$(readlink -e "$RUST_SRC")

# update symlink
rm -f lib$CRATE
ln -s "$RUST_SRC"/src/lib$CRATE lib$CRATE

# run test
cd ${CRATE}_miri_test
XARGO_RUST_SRC="$RUST_SRC/src" cargo miri setup
MIRI_SYSROOT=~/.cache/miri/HOST cargo miri test -- -Zmiri-seed=cafedead $MIRI_EXTRA_FLAGS -- -Zunstable-options --exclude-should-panic "$@"
