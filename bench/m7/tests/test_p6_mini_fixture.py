#!/usr/bin/env python3
"""(AE) test_p6_mini_fixture -- seals the arm-image witness fixture.

The mini_cell_p6 witness cell is the pre-ignition health gate baked into
layer 28 of every arm image: it drives the whole four-file contract
through the rusage launcher. Bake death #7 proved the fixture that
rode in from #13 (mini_cell/) was a single sample (a 96x1 catalog):
the rust face legitimately refuses it ("nndsvd: rank k exceeds
min(m, n)") and the vacuous status gate in the post_p1 tree's
.rust_status -- system2 returns the exit code as its VALUE, never a
"status" attribute -- disguised the rc=2 as a missing meta.csv. A
witness that dies on a degenerate input witnesses nothing, so the P6
arm witness rides a twenty-sample regeneration under a reviewable,
deterministic rule: row r0 keeps the #13 attested bytes verbatim, and
samples r1..r19 are seeded multinomial(100, .) mixtures of two
committed COSMIC profile columns from catalog.csv -- aligned across
samples, N100-faithful (100 counts per sample), and byte-stable enough
to be asserted equal to regeneration here. The legacy mini_cell/ dir
stays byte-frozen: the #13-era rehearsal manifest re-hashes it live.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]          # bench/m7
ADAPTERS = HERE / "adapters"
TOOLS = HERE / "tools"

MINI = ADAPTERS / "mini_cell_p6"
N_SAMPLES = 20
N_TOTAL = 100                                       # the N100 witness law
CHANNELS = 96


def _load(name: str):
    spec = importlib.util.spec_from_file_location(
        f"tests.{name}", str(TOOLS / f"{name}.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _fixture_text() -> str:
    p = MINI / "counts.csv"
    if not p.is_file():
        raise AssertionError(f"witness fixture missing: {p}")
    return p.read_text(encoding = "utf-8")


def test_generator_module_is_reviewable_and_pure():
    # Arrange
    gen = _load("p6_make_mini_fixture")

    # Act
    first = gen.generate_bytes()
    second = gen.generate_bytes()

    # Assert
    assert isinstance(first, bytes), "generate_bytes must return bytes"
    assert first == second, "the fixture rule is not deterministic"


def test_on_disk_fixture_equals_regeneration():
    # Arrange
    gen = _load("p6_make_mini_fixture")

    # Act
    on_disk = _fixture_text().encode("utf-8")

    # Assert
    assert on_disk == gen.generate_bytes(), (
        "committed counts.csv diverges from the generator's bytes -- "
        "regenerate with tools/p6_make_mini_fixture.py, never hand-edit")


def test_first_row_is_the_attested_13_sample_verbatim():
    # Arrange
    lines = _fixture_text().rstrip("\n").split("\n")
    legacy = [ln for ln in (ADAPTERS / "mini_cell" / "counts.csv").read_text(
        encoding = "utf-8").splitlines() if ln]

    # Act / Assert
    assert len(legacy) == 2, (
        "the byte-frozen #13 fixture must stay the attested single-sample "
        "file its rehearsal-manifest claim describes")
    assert lines[1] == legacy[1], (
        "the #13 attested r0 row must survive byte-for-byte")
    assert lines[1].split(",")[0] == "main__N100__r0"
    assert sum(int(x) for x in lines[1].split(",")[1:]) == N_TOTAL


def test_fixture_shape_and_N100_law():
    # Arrange
    lines = _fixture_text().rstrip("\n").split("\n")
    header = lines[0].split(",")

    # Assert
    assert header[0] == "sample_id"
    assert len(header) == CHANNELS + 1, "96 mutation channels + sample_id"
    assert len(lines) == N_SAMPLES + 1, f"header + {N_SAMPLES} samples"
    for i, line in enumerate(lines[1:]):
        fields = line.split(",")
        label = fields[0]
        assert label == f"main__N100__r{i}", f"bad sample lineage: {label}"
        assert all(re.fullmatch(r"[0-9]+", f) for f in fields[1:]), \
            f"non-integer counts in {label}"
        assert sum(int(f) for f in fields[1:]) == N_TOTAL, \
            f"{label} breaks the N100 witness law"


def test_samples_are_aligned_but_not_clones():
    # Arrange
    gen = _load("p6_make_mini_fixture")
    rows = [line.split(",")[1:]
            for line in _fixture_text().rstrip("\n").split("\n")[1:]]

    # Assert
    assert gen.PROFILES and all(col in _catalog_columns() for col in gen.PROFILES), (
        "the mixture must draw only from committed catalog.csv columns")
    assert len(set(map(tuple, rows))) >= 2, "all samples are identical rows"


def _catalog_columns() -> list[str]:
    head = (ADAPTERS / "mini_cell" / "catalog.csv").read_text(
        encoding = "utf-8").split("\n")[0]
    return head.split(",")


if __name__ == "__main__":
    sys.exit("run via tests.run_all")
