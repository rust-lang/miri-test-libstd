#!/bin/bash
set -euo pipefail
#set -x

## Run a Rust libstd test suite with Miri.
## Assumes Miri to be installed.
## Usage:
##   ./run-test.sh CRATE_NAME
## Environment variables:
##   RUST_SRC: The path to the Rust source directory (where libstd etc. are).
##     Defaults to `$(rustc --print sysroot)/lib/rustlib/src/rust/src`.

CRATE=${1:-}
if [[ -z "$CRATE" ]]; then
    echo "Usage: $0 CRATE_NAME"
    exit 1
fi
shift

RUST_SRC=$(readlink -m ${RUST_SRC:-$(rustc --print sysroot)/lib/rustlib/src/rust/src})
if ! test -d "$RUST_SRC"; then
   echo "Rust source dir ($RUST_SRC) does not exist"
   exit 1
fi

rm -f rust-src
ln -s $RUST_SRC rust-src

cd lib$CRATE
XARGO_RUST_SRC=$RUST_SRC cargo miri setup
MIRI_SYSROOT=~/.cache/miri/HOST cargo miri test -- -Zmiri-seed=cafedead -- -Zunstable-options --exclude-should-panic "$@"
