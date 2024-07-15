This repository serves to run the libcore, liballoc, and libstd test suites in [Miri](https://github.com/rust-lang/miri/).
This includes unit tests, integration tests, and doc tests, but not rustc ui tests.

Every night, a CI cron job runs the tests against the latest nightly, to make sure we notice when changes in Rust or Miri break a test.
(Some libstd tests are excluded since they rely on platform-specific APIs that Miri does not implement.)

### Running the tests yourself

To run the tests yourself, make sure you have Miri installed (`rustup component add miri`) and then run:

```shell
MIRIFLAGS="-Zmiri-disable-isolation" ./run-test.sh core
MIRIFLAGS="-Zmiri-disable-isolation" ./run-test.sh alloc
MIRIFLAGS="-Zmiri-disable-isolation" ./run-test.sh std -- --skip fs:: --skip net:: --skip process:: --skip sys::pal::
```

This will run the test suite of the standard library of your current toolchain.
It will probably take 1-2h, so if you have specific parts of the standard library you want to test, use the usual `cargo test` filter mechanisms to narrow this down:
all arguments are passed to `cargo test`, so arguments after `--` are passed to the test runner as usual.
Isolation is disabled as even in `core`, some doctests use file system accesses for demonstration purposes.
For `std`, we cannot run *all* tests since they will use networking and file system APIs that we do not support.

If you are working on the standard library and want to check that the tests pass with your modifications, set `MIRI_LIB_SRC` to the `library` folder of the checkout you are working in:

```shell
MIRI_LIB_SRC=~/path/to/rustc/library ./run-test.sh core -- test_name
```

Here, `~/path/to/rustc` should be the directory containing `x.py`.
Then the test suite will be compiled from the standard library in that directory.
Make sure that is as close to your rustup default toolchain as possible, as the toolchain will still be used to build that standard library and its test suite.
If you are getting strange build errors, `cargo clean` can often fix that.

If you want to know how long each test took to execute, add `2>&1 | ts -m -i '%.s  '` to the end of the command,
or use the test flags `-Zunstable-options --report-time` (the latter option also requires `-Zmiri-disable-isolation` in the Miri flags).
