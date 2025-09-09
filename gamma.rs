#![feature(float_gamma)]

fn main() {
  dbg!(std::hint::black_box(-0.5f32).gamma());
}
