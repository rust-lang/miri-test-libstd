#!/bin/bash
set -eauxo pipefail

## Shared setup code for CI jobs

# We need 'ts' and 'llvm-symbolizer'
sudo apt-get -y install moreutils llvm
echo

# And of course we need Rust
if [[ "$GITHUB_EVENT_NAME" == 'schedule' ]]; then
    RUST_TOOLCHAIN=nightly
else
    RUST_TOOLCHAIN=$(cat rust-version)
fi
echo "Installing Rust version: $RUST_TOOLCHAIN"
rustup toolchain install "$RUST_TOOLCHAIN" --component rust-src
rustup override set "$RUST_TOOLCHAIN"
