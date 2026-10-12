"""Action-pin law for third-party `uses:` references (M8 supply-chain hardening).

Two pinning forms are admissible, and the law is the same strictness for both:

  1. major-version tag ref:      owner/repo@vN
  2. commit-SHA pin:             owner/repo@<40hex>  — admissible only when the
                                 workflow line carries its major-version note
                                 as a trailing comment `# vN`, so the pin stays
                                 auditable against the repo's declared majors.

Mutable refs (branches, patch-level tags, latest) and short SHAs are rejected:
a floating tag resolves in the COMMIT namespace at run time and can move under
the workflow. The SHA form additionally survives annotated-tag retargeting.
"""

import re

_FULL_SHA = re.compile(r"[0-9a-f]{40}\Z")
_TAG_MAJOR = re.compile(r"@v(\d+)\Z")
_COMMENT_MAJOR = re.compile(r"\Av(\d+)\Z")
_USES_LINE = re.compile(r"uses:\s*([^\s#]+)(?:\s*#\s*([^\s#]+))?")


def uses_pairs(source):
    """(target, comment|None) pairs for every `uses:` line in raw YAML source."""
    return tuple(
        (match.group(1), match.group(2))
        for match in _USES_LINE.finditer(source)
    )


def major_of(target, comment):
    """Declared major version int, or None when the pin is not admissible.

    Tag form reads the major from the ref itself; SHA form reads it from the
    mandatory trailing `# vN` note (absent or malformed note -> not verifiable
    -> not admissible).
    """
    if not target:
        return None
    tag = _TAG_MAJOR.search(target)
    if tag is not None:
        return int(tag.group(1))
    path, _, sha = target.partition("@")
    if _FULL_SHA.match(sha or "") is None:
        return None
    note = _COMMENT_MAJOR.match((comment or "").strip())
    return None if note is None else int(note.group(1))


def has_major(target, comment, major):
    """True iff the pin is admissible and declares exactly `major`."""
    return major_of(target, comment) == int(major)


def is_acceptably_pinned(target, comment):
    """True iff the ref is pinned per the law above."""
    return major_of(target, comment) is not None
