This repository serves to run the libcore and liballoc unit test suites in [Miri](https://github.com/solson/miri/): we basically run `cargo miri test` against [coretests](https://github.com/rust-lang/rust/tree/master/src/libcore/tests), [alloctests](https://github.com/rust-lang/rust/tree/master/src/liballoc/tests) and [liballoc itself](https://github.com/rust-lang/rust/tree/master/src/liballoc) (there do not seem to be `#[test]` functions embedded in libcore).

Every night, a Travis cron job runs the tests against the latest nightly, to make sure we notice when changes in Rust or Miri break a test.

You can also run the libstd test suites, but note that large parts of them will fail due to relying on platform-specific APIs that Miri does not implement.

### Running the tests yourself

To run the tests yourself, make sure you have Miri installed (`rustup component add miri`) and then run:

```shell
./run-test.sh core --all-targets
./run-test.sh alloc --all-targets
```

This will run the test suite of the standard library of your current toolchain.
`--all-targets` means that doc tests are skipped; those should use separate Miri flags as there are some (expected) memory leaks.

If you are working on the standard library and want to check that the tests pass with your modifications, set `MIRI_LIB_SRC` to the `library` folder of the checkout you are working in:

```shell
MIRI_LIB_SRC=~/path/to/rustc/library ./run-test.sh core --all-targets
```

Here, `~/path/to/rustc` should be the directory containing `x.py`.
Then the test suite will be compiled from the standard library in that directory.
Make sure that is as close to your rustup default toolchain as possible, as the toolchain will still be used to build that standard library and its test suite.
If you are getting strange build errors, `cargo clean` can often fix that.

`run-test` also accepts parameters that are passed to `cargo test` and the test runner,
and `MIRIFLAGS` can be used as usual to pass parameters to Miri:

```shell
MIRIFLAGS="-Zmiri-ignore-leaks -Zmiri-disable-isolation" ./run-test.sh alloc --doc -- --skip vec
```

If you want to know how long each test took to execute, add `2>&1 | ts -m -i '%.s  '` to the end of the command.
