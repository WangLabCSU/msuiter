//! Structured error type for engine (and catalog) kernels (U-M0-09).
//!
//! FFI contract 5 (`docs/ARCHITECTURE.md` §2): every kernel returns
//! `Result<_, MsError>`; kernels never call throwing R APIs and never panic
//! across the boundary. Only the FFI shell converts an `MsError` into an R
//! condition, so a kernel failure always fails the whole call — no partial
//! results.
//!
//! The payload mirrors the R-side error-class convention
//! `msuiter_error_<topic>` (ARCHITECTURE §3.5) and its i/j/c information
//! triple: `topic` names the failure family, `i` / `j` carry 1-based
//! positional context (row / column, element index, chunk number — the two
//! axes of the failing lookup), and `message` is the human-readable context.
//! The FFI boundary pins the R condition *class* to `msuiter_error_rust`
//! for the whole Rust layer and ships `topic` inside the condition payload
//! (see `src/rust/src/condition.rs`).

use std::fmt;

/// A kernel-level failure with structured, R-facing context.
///
/// Plain value type: no backtrace, no R handles, cheap to construct and
/// compare in tests. `PartialEq` support is deliberate — golden/error tests
/// assert the structured payload, not a string.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MsError {
    /// Machine-readable failure family (e.g. `"bounds"`, `"na"`,
    /// `"argument"`, `"interrupted"`).
    pub topic: String,
    /// Human-readable, English description (the `c`/context segment in R).
    pub message: String,
    /// First positional index, 1-based (R convention); `None` when absent.
    pub i: Option<i64>,
    /// Second positional index, 1-based (R convention); `None` when absent.
    pub j: Option<i64>,
}

impl MsError {
    /// Create an error for the given failure family and context message.
    pub fn new(topic: &str, message: impl Into<String>) -> Self {
        Self {
            topic: topic.to_owned(),
            message: message.into(),
            i: None,
            j: None,
        }
    }

    /// Attach a 1-based first index (row / element / chunk).
    pub fn with_i(mut self, i: i64) -> Self {
        self.i = Some(i);
        self
    }

    /// Attach a 1-based second index (column).
    pub fn with_j(mut self, j: i64) -> Self {
        self.j = Some(j);
        self
    }

    /// The failure family (borrows; useful in match-based dispatch).
    pub fn topic(&self) -> &str {
        &self.topic
    }
}

impl fmt::Display for MsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)?;
        match (self.i, self.j) {
            (Some(i), Some(j)) => write!(f, " (i={i}, j={j})"),
            (Some(i), None) => write!(f, " (i={i})"),
            (None, Some(j)) => write!(f, " (j={j})"),
            (None, None) => Ok(()),
        }
    }
}

impl std::error::Error for MsError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_with_topic_and_message() {
        let e = MsError::new("bounds", "index outside matrix");
        assert_eq!(e.topic, "bounds");
        assert_eq!(e.topic(), "bounds");
        assert_eq!(e.message, "index outside matrix");
        assert_eq!(e.i, None);
        assert_eq!(e.j, None);
    }

    #[test]
    fn builder_chains_indices() {
        let e = MsError::new("bounds", "boom").with_i(3).with_j(7);
        assert_eq!(e.i, Some(3));
        assert_eq!(e.j, Some(7));
        // Overwrite semantics: the last writer wins.
        let e = e.with_i(9);
        assert_eq!(e.i, Some(9));
    }

    #[test]
    fn display_includes_indices_when_present() {
        assert_eq!(MsError::new("bounds", "boom").to_string(), "boom");
        assert_eq!(
            MsError::new("bounds", "boom").with_i(2).to_string(),
            "boom (i=2)"
        );
        assert_eq!(
            MsError::new("bounds", "boom").with_j(4).to_string(),
            "boom (j=4)"
        );
        assert_eq!(
            MsError::new("bounds", "boom").with_i(2).with_j(5).to_string(),
            "boom (i=2, j=5)"
        );
    }

    #[test]
    fn comparable_and_clonable_for_golden_tests() {
        let a = MsError::new("na", "NaN found").with_i(1).with_j(2);
        let b = a.clone();
        assert_eq!(a, b);
        assert_ne!(a, MsError::new("na", "NaN found").with_i(1).with_j(3));
    }

    #[test]
    fn usable_as_std_error() {
        fn fallible() -> Result<(), MsError> {
            Err(MsError::new("argument", "bad input"))
        }
        let boxed: Box<dyn std::error::Error> = fallible().unwrap_err().into();
        assert!(boxed.to_string().contains("bad input"));
    }
}
