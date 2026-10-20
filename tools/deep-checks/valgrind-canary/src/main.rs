// Valgrind trip canary for the loudness-law leg (issue #32 remediation).
// Commits the two violation classes memcheck adjudicates: a heap
// out-of-bounds read (reported as "Invalid read of size N bytes") and a
// definitely-lost allocation (reported under "definitely lost").
use std::env::args;
use std::hint::black_box;
use std::mem;
use std::slice::from_raw_parts;

fn read_volatile(ptr: *const u8) -> u8 {
    let mut out = 0u8;
    // The copy is the instrumented event; valgrind inspects the address
    // before the read lands, so a volatile-style copy keeps it visible.
    unsafe { std::ptr::copy_nonoverlapping(ptr, &mut out, 1); }
    black_box(out);
    out
}

fn trip_heap() {
    let buf = vec![0x5Au8; 8];
    let base = black_box(buf.as_ptr());
    // One byte past the 8-byte allocation: heap-buffer-overflow shape.
    let oob = base.wrapping_add(8);
    let window: &[u8] = unsafe { from_raw_parts(oob, 1) };
    let _sink = read_volatile(window.as_ptr());
    println!("valgrind-canary: heap trip complete");
}

fn trip_leak() {
    let leak = Box::new([0xA5u8; 4096]);
    black_box(&leak);
    // Forget the Box itself: a raw pointer would be Copy and forget() on one
    // is a no-op (clippy's forgetting_copy_types keeps that honest).
    mem::forget(leak);
    println!("valgrind-canary: leak trip complete");
}

fn clean() {
    let buf = vec![0x5Au8; 8];
    let base = black_box(buf.as_ptr());
    let _sum: usize = (0..8).map(|i| read_volatile(base.wrapping_add(i)) as usize).sum();
    let boxed = Box::new([0xA5u8; 4096]);
    black_box(&boxed);
    println!("valgrind-canary: clean run complete");
}

fn main() {
    let args: Vec<String> = args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("clean");
    let class = args.get(2).map(String::as_str).unwrap_or("");
    match (mode, class) {
        ("trip", "heap") => trip_heap(),
        ("trip", "leak") => trip_leak(),
        ("clean", _) => clean(),
        _ => panic!("usage: msuiter-valgrind-canary <clean|trip heap|trip leak>"),
    }
}
