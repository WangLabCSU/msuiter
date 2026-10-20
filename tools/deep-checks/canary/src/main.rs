//! Sanitizer canary for the Scheduled deep checks (issue #32, D1 loudness law).
//!
//! A tiny, deliberately misused program the leg harness uses as a
//! positive control: a sanitizer leg is only credible if a reviewed
//! violation of the class that sanitizer detects actually produces a
//! report. Modes (argv):
//!
//!   canary clean           no violation; a live sanitizer must stay silent
//!   canary trip <name>     perform the trip shape of sanitizer <name>
//!
//! The `unsafe` blocks here are the entire point of this crate: it exists
//! to be misused, exactly one reviewed way per leg, under a running
//! sanitizer. It is workspace-detached, publish-disabled, and built only
//! by tools/deep-checks/run_sanitizer_leg.sh -- it never reaches the
//! shipped library, the FFI shell, or the vendor baseline.

use std::env;
use std::mem;

/// Heap OOB read one past an 8-byte buffer: ASan's heap-buffer-overflow
/// class, the same class as the U-M1c-01 P0-1 off-bucket index audit.
fn trip_address() {
    let buf = vec![0x5Au8; 8];
    // Read via a volatile load so the access survives optimization; the
    // sanitizer intercepts the access itself, before any value exists.
    let past = unsafe { std::ptr::read_volatile(buf.as_ptr().wrapping_add(8)) };
    println!("canary address trip: read past-end byte {past:#04X}");
}

/// One-time init allocation rendered unreachable at process exit: LSan's
/// class. Mirrors the reviewed "leak the init table" shape so the leg's
/// leak detection is exercised against the same report path that triaged
/// the 2026-10-19 indel83 findings.
fn trip_leak() {
    let init_table = Box::new([0xA5u8; 4096]);
    mem::forget(init_table);
    println!("canary leak trip: forgot a 4096-byte init allocation");
}

fn main() {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("clean") => {
            // Same allocation traffic as the trips, all properly dropped:
            // a working sanitizer must have nothing to say.
            let healthy = vec![7u8; 64];
            let boxed = Box::new([1u8; 4096]);
            let sum: u64 = healthy.iter().fold(0, |a, &b| a + u64::from(b))
                + boxed.iter().fold(0, |a, &b| a + u64::from(b));
            println!("canary clean: {sum} (no violation performed)");
        }
        Some("trip") => match args.get(2).map(String::as_str) {
            Some("address") => trip_address(),
            Some("leak") => trip_leak(),
            other => panic!("canary: unknown trip target {other:?} (expected address|leak)"),
        },
        other => panic!("canary: unknown mode {other:?} (expected clean|trip)"),
    }
}
