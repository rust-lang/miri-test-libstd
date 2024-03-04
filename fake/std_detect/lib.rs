#![feature(rustc_private, stdarch_internal)]
#![allow(internal_features)] // yes we are doing very internal stuff here
extern crate std_detect;
pub use std_detect::*;
