"""Group (L) companion -- the sigprofiler entrypoint probe (RB-09(3)(ii)).

Floor anchors must exist PER TOOL, so the sigprofiler floor gets its own
entrypoint probe. This module is parameterization only -- the assessment
chain, sidecar schema and witness provenance extras are the certified code
of probe_sigminer_cell_argv.run_probe -- so the offline law here pins the
parameterization itself: the registry row must be admissible (ready, digest
pinned) and the emitted cell stamp must speak the sigprofiler tool.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # bench/m7
import tools.probe_sigprofiler_cell_argv as probe              # noqa: E402
from competitors import registry                                # noqa: E402


def test_sigprofiler_registry_row_is_admissible():
    spec = registry.lookup("sigprofiler")
    assert spec.status == "ready" and spec.image_digest.startswith("sha256:")
    assert spec.image_ref == "m7-sigprofiler:spa-1.1.5"


def test_probe_reuses_the_certified_shared_core():
    from tools.probe_sigminer_cell_argv import run_probe
    assert probe.run_probe is run_probe, (
        "the sigprofiler probe must not fork the assessment chain")


def test_parse_args_defaults_are_the_pilot_shape():
    args = probe.parse_args([])
    assert args.arm == "main" and args.n_point == 100 and args.reps == 1
    floor = probe.parse_args(["--arm", "comp_pole", "--n", "1000000",
                              "--reps", "100"])
    assert floor.reps == 100 and floor.n_point == 1_000_000
