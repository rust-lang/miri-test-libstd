#!/bin/bash
set -eauxo pipefail

## Run a Rust libstd test suite with Miri.
## Usage:
##   ./run-test.sh CRATE_NAME CARGO_TEST_ARGS
## Environment variables:
##   LIB_SRC: The path to the Rust library directory (`library`).
##     Defaults to `$(rustc --print sysroot)/lib/rustlib/src/rust/library`.

CRATE=${1:-}
if [[ -z "$CRATE" ]]; then
    echo "Usage: $0 CRATE_NAME"
    exit 1
fi
shift

# compute the library directory
LIB_SRC=${LIB_SRC:-$(rustc --print sysroot)/lib/rustlib/src/rust/library}
if ! test -d "$LIB_SRC/core"; then
    echo "Rust source dir ($LIB_SRC) does not contain a 'core' subdirectory."
    echo "Set LIB_SRC to the Rust source directory, or install the rust-src component."
    exit 1
fi
# macOS does not have a useful readlink/realpath so we have to use Python instead...
LIB_SRC=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$LIB_SRC")
export LIB_SRC

# update symlink
rm -f library
ln -s "$LIB_SRC" library

# use the rust-src lockfile
cp "$LIB_SRC/../Cargo.lock" Cargo.lock

echo "running test with RUSTFLAGS ${RUSTFLAGS}"

# run test
cd "./${CRATE}_run_test"
cargo test -vvv "$@"
