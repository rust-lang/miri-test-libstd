#![feature(no_core, rustc_private)]
#![no_core]
extern crate alloc as realalloc;
pub use realalloc::*;
