//! These are *not* taken from std, they are hand-written.
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;

// Regression test for https://github.com/rust-lang/rust/issues/98498.
#[test]
fn scope_race() {
    for _ in 0..100 {
        let a_bool = AtomicBool::new(false);

        thread::scope(|s| {
            for _ in 0..5 {
                s.spawn(|| a_bool.load(Ordering::Relaxed));
            }

            for _ in 0..5 {
                s.spawn(|| a_bool.load(Ordering::Relaxed));
            }
        });
    }
}

/// Test for Arc::drop bug (https://github.com/rust-lang/rust/issues/55005)
#[test]
fn arc_drop() {
    // The bug seems to take up to 700 iterations to reproduce with most seeds (tested 0-9).
    for _ in 0..700 {
        let arc_1 = Arc::new(());
        let arc_2 = arc_1.clone();
        let thread = thread::spawn(|| drop(arc_2));
        let mut i = 0;
        while i < 256 {
            i += 1;
        }
        drop(arc_1);
        thread.join().unwrap();
    }
}
