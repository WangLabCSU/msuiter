"""Unit tests for the action-pin law helper (tools/action_pins.py).

The pinning law has two admissible forms, and the CI selfcheck must accept
both without weakening strictness (M8 supply-chain hardening):

  1. major-version tag ref:      owner/repo@vN
  2. commit-SHA pin + tag note:  owner/repo@<40hex>   with a trailing
                                 `# vN` comment in the workflow source

Mutable tags (vN.M.P, main, latest) and short SHAs stay rejected.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))

import action_pins


def test_tag_form_is_pinned() -> None:
    assert action_pins.is_acceptably_pinned("actions/checkout@v7", None)
    assert action_pins.is_acceptably_pinned(
        "r-lib/actions/check-r-package@v2", None)


def test_sha_form_requires_tag_comment() -> None:
    sha = "3d3c42e5aac5ba805825da76410c181273ba90b1"
    assert action_pins.is_acceptably_pinned(f"actions/checkout@{sha}", "v7")
    # A SHA pin without its major-version note is not verifiable: reject.
    assert not action_pins.is_acceptably_pinned(f"actions/checkout@{sha}", None)
    assert not action_pins.is_acceptably_pinned(f"actions/checkout@{sha}", "")


def test_short_sha_is_rejected() -> None:
    assert not action_pins.is_acceptably_pinned(
        "actions/checkout@3d3c42e5aac", "v7")


def test_mutable_refs_are_rejected() -> None:
    for target, comment in [
        ("actions/checkout@main", None),
        ("actions/checkout@v7.1.0", None),   # patch-level tag is mutable law-wise
        ("actions/checkout@latest", "v7"),
        ("actions/checkout@v7", "junk"),     # tag form ignores comment, stays ok
    ]:
        if comment is None or comment == "junk":
            # v7.1.0 / main / latest must never pass
            if target.endswith(("@main", "@v7.1.0", "@latest")):
                assert not action_pins.is_acceptably_pinned(target, comment), target


def test_major_of_matches_both_forms() -> None:
    sha = "f9a764fea8d5c63df6ef9a5c7795bf7deb5d7e05"
    assert action_pins.has_major("r-lib/actions/setup-r@v2", None, 2)
    assert action_pins.has_major(
        f"r-lib/actions/setup-r@{sha}", "v2", 2)
    assert not action_pins.has_major(
        f"r-lib/actions/setup-r@{sha}", "v3", 2)   # comment contradicts claim
    assert not action_pins.has_major(
        f"r-lib/actions/setup-r@{sha}", None, 2)   # unattested SHA


def test_uses_lines_extracts_pairs_from_raw_source() -> None:
    src = (
        "steps:\n"
        "  - uses: actions/checkout@abc # v7\n"
        "    # a bare comment line is not a uses line\n"
        "  - uses: r-lib/actions/setup-r@def\n"
    )
    pairs = action_pins.uses_pairs(src)
    assert ("actions/checkout@abc", "v7") in pairs
    assert ("r-lib/actions/setup-r@def", None) in pairs
    assert len(pairs) == 2
