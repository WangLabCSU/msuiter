"""The skip-not-skip sentinel (design memo §6).

A competitor that cannot run must produce an *explicit, reported* refusal —
never a generic crash, never a zero-execution "success", never a silent
pass. The presence of the refusal mechanism is itself under test
(tests/test_adapters.py): a test may not go green because the exception
went missing.
"""

from __future__ import annotations


class AdapterUnavailable(RuntimeError):
    """Raised by an adapter when its competitor cannot execute.

    Legitimate reasons (design memo §5/§6):
      * the pinned image is absent from the local image store;
      * the image digest was never captured from ``docker image inspect``
        (reads ``PENDING-VERIFY`` → treated as not-ready; inventing a
        digest is prohibited);
      * unresolved provenance (status ``pending-verify``, e.g. Signal
        until the PI supplies package coordinates);
      * the docker CLI/daemon is not available on this host.

    The orchestrator prints ``SKIP <competitor> (<reason>)`` and tallies
    skips separately; a cell the protocol requires to be adjudicated that
    comes back SKIP fails the run exit code.
    """
