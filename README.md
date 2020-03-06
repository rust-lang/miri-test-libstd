This repository serves to run the libcore and liballoc unit test suites in [Miri](https://github.com/solson/miri/): we basically run `cargo miri test` against [coretests](https://github.com/rust-lang/rust/tree/master/src/libcore/tests), [alloctests](https://github.com/rust-lang/rust/tree/master/src/liballoc/tests) and [liballoc itself](https://github.com/rust-lang/rust/tree/master/src/liballoc) (there do not seem to be `#[test]` functions embedded in libcore).

Every night, a Travis cron job runs the tests against the latest nightly, to make sure we notice when changes in Rust or Miri break a test.

### Running the tests yourself

To run the tests yourself, make sure you have Miri installed (`rustup component add miri`) and then run:

```shell
./run-test.sh core
./run-test.sh alloc
```

This will run the test suite of the standard library of your current toolchain.
If you are working on the standard library and want to check that the tests still pass with your modifications, you can run the tests as follows:

```shell
RUST_SRC=~/path/to/rustc ./run-test.sh core # or `alloc`
```

Here, `~/path/to/rustc` should be the directory containing `x.py`.
Then the test suite will be compiled from the standard library in that directory.
Make sure that is as close to your rustup default toolchain as possible, as the toolchain will still be used to build that standard library and its test suite.

`run-test` also accepts parameters that are passed to Miri and the test runner:

```shell
RUST_SRC=~/path/to/rustc ./run-test.sh core -Zmiri-flags -- test-params
```
