#!/bin/bash
set -euo pipefail

## Shared setup code for CI jobs

# We need 'ts'
sudo apt-get -y install moreutils

# And of course we need Rust
if [[ "$GITHUB_EVENT_NAME" == 'schedule' ]]; then
    RUST_TOOLCHAIN=nightly-$(curl -s https://rust-lang.github.io/rustup-components-history/x86_64-unknown-linux-gnu/miri)
else
    RUST_TOOLCHAIN=$(cat rust-version)
fi
echo "Installing Rust version: $RUST_TOOLCHAIN"
rustup default $RUST_TOOLCHAIN
rustup component add rust-src miri
cargo miri setup
