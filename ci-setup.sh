#!/bin/bash
set -euo pipefail

## Shared setup code for CI jobs

# We need 'ts'
sudo apt-get -y install moreutils
echo

# And of course we need Rust
if [[ "$GITHUB_EVENT_NAME" == 'schedule' ]]; then
    RUST_TOOLCHAIN=nightly
else
    RUST_TOOLCHAIN=$(cat rust-version)
fi
echo "Installing Rust version: $RUST_TOOLCHAIN"
rustup toolchain install "$RUST_TOOLCHAIN$ --component miri
rustup override set "$RUST_TOOLCHAIN$"
cargo miri setup
