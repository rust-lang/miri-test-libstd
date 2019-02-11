This repository serves to run the libcore and liballoc unit test suites in [Miri](https://github.com/solson/miri/).
We carry a [patch file](rust-src.diff) against the [currently tested Rust version](rust-version) to skip tests in Miri or to fix test failures.
The patches in that file will get upstreamed, but we do not always want to wait until that happens.

Every night, a Travis cron job runs the tests against the latest nightly, to make sure we notice when changes in Rust or Miri break a test.
