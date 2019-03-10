#!/bin/bash
set -euo pipefail

## Run a Rust libstd test suite with Miri.
## Assumes Miri to be installed.
## Usage:
##   ./run-test.sh CRATE_NAME
## Environment variables:
##   RUST_SRC: The path to the Rust source directory (where libstd etc. are).
##     Defaults to `$(rustc --print sysroot)/lib/rustlib/src/rust/src`.

RUST_SRC=$(readlink -e ${RUST_SRC:-$(rustc --print sysroot)/lib/rustlib/src/rust/src})
CRATE=${1:-}
shift

if [[ -z "$CRATE" ]]; then
    echo "Usage: $0 CRATE_NAME"
    exit 1
fi

rm -f rust-src
ln -s $RUST_SRC rust-src

cd lib$CRATE
XARGO_RUST_SRC=$RUST_SRC cargo miri setup
MIRI_SYSROOT=~/.cache/miri/HOST cargo miri test -- -- -Zunstable-options --exclude-should-panic "$@"
