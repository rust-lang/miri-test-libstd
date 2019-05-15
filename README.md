This repository serves to run the libcore and liballoc unit test suites in [Miri](https://github.com/solson/miri/): we basically run `cargo miri test` against [coretests](https://github.com/rust-lang/rust/tree/master/src/libcore/tests), [alloctests](https://github.com/rust-lang/rust/tree/master/src/liballoc/tests) and [liballoc itself](https://github.com/rust-lang/rust/tree/master/src/liballoc) (there do not seem to be `#[test]` functions embedded in libcore).
We carry a [patch file](rust-src.diff) against the [currently tested Rust version](rust-version) to skip tests in Miri or to fix test failures.
The patches in that file will get upstreamed, but we do not always want to wait until that happens.

Every night, a Travis cron job runs the tests against the latest nightly, to make sure we notice when changes in Rust or Miri break a test.
