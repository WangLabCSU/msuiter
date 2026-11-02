"""Authoritative-runner fail-closed laws for tools/run_primary_pi.sh (G0-P lane).

Every law is an observation on a live subprocess of the runner, never a text
grep of its bytes: the negatives must fire for their named cause, and the
paired controls (valid env passes the pre-flight; pristine digests pass)
prove the instruments are not vacuous. The mock face (G0_PI_REHEARSAL=mock,
mandatory G0_PI_REPS) exercises the full orchestration without docker.

User-supplied F3 files are located via G0_PI_USER_CACHE, else the in-tree
cache, else the sibling main checkout (the worktree lane layout).
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent          # bench/g0/tests
G0_DIR = HERE.parent                            # bench/g0
RUNNER = G0_DIR / "tools" / "run_primary_pi.sh"
ROLLUP = G0_DIR / "tools" / "rollup_timings.py"
VERIFIER = G0_DIR / "tools" / "verify_hardware_pin.py"

PIN_SIG = ("80e911998764667dcb715e7390671e32aa2bbe657a43be398e5e8319305ba29e")
PIN_CAT = ("733e38c50b94f7dc59cef15eb042fc4359a818314fb3efb3824a7c54642c3f60")
CANON_PIN = "10 vCPU / 8 GB class"
NINE_COL_HEADER = ("cell,tool,arm,n,seconds,status,cpu_seconds,host,hw_profile")


def _user_cache() -> Path:
    env = os.environ.get("G0_PI_USER_CACHE")
    here = Path(__file__).resolve()
    cands = ([Path(env)] if env else []) + [
        here.parents[1] / "cache",
        here.parents[4].parent / "msuiter" / "bench" / "g0" / "cache",
    ]
    for c in cands:
        if (c / "g0_signatures.csv").is_file() and (c / "g0_catalog.csv").is_file():
            return c
    raise AssertionError(
        "user-supplied F3 files unlocatable (set G0_PI_USER_CACHE) — the "
        "authoritative-runner laws cannot attest digests without them")


def _tmpdir(tag: str) -> Path:
    return Path(tempfile.mkdtemp(prefix=f"g0pi_{tag}_"))


def _run(env_over: dict, expect_rc: int | None = None):
    env = os.environ.copy()
    env["G0_PI_PREFLIGHT"] = "1"
    for k, v in env_over.items():
        if v is None:
            env.pop(k, None)
        else:
            env[k] = str(v)
    p = subprocess.run(["sh", str(RUNNER)], cwd=str(G0_DIR), env=env,
                       capture_output=True, text=True, timeout=900)
    out = (p.stdout or "") + (p.stderr or "")
    if expect_rc is not None and p.returncode != expect_rc:
        raise AssertionError(f"rc={p.returncode} != {expect_rc}\n{out[-1200:]}")
    return p, out


def _valid_env(**over) -> dict:
    cache = _user_cache()
    env = {"G0_SIGNATURES_PATH": str(cache / "g0_signatures.csv"),
           "G0_CATALOG_PATH": str(cache / "g0_catalog.csv"),
           "G0_HW_PROFILE": CANON_PIN}
    env.update(over)
    return env


def _seed_ledger(outdir: Path, n_full: int) -> None:
    outdir.mkdir(parents=True, exist_ok=True)
    rows = [json.dumps({"kind": "launch", "mode": "full", "ts": "2026-11-02T00:00:00"})
            for _ in range(n_full)]
    (outdir / "campaign_launches.jsonl").write_text(
        "\n".join(rows) + ("\n" if rows else ""))


# -- input fail-closed laws -------------------------------------------------------

def test_env_valid_passes_preflight_control():
    # Arrange/Act/Assert: the anti-vacuous anchor — a complete, honest
    # environment must PASS the whole pre-flight (rc 0 + PREFLIGHT-PASS).
    p, out = _run(_valid_env(), expect_rc=0)
    assert "PREFLIGHT-PASS" in out, out[-800:]


def test_ignition_refuses_when_catalog_env_unset():
    p, out = _run(_valid_env(G0_CATALOG_PATH=None), expect_rc=2)
    assert "G0_CATALOG_PATH" in out and "unset" in out.lower(), out[-800:]


def test_ignition_refuses_when_signatures_env_unset():
    p, out = _run(_valid_env(G0_SIGNATURES_PATH=None), expect_rc=2)
    assert "G0_SIGNATURES_PATH" in out and "unset" in out.lower(), out[-800:]


def test_ignition_refuses_when_input_file_missing():
    d = _tmpdir("nofile")
    p, out = _run(_valid_env(G0_CATALOG_PATH=str(d / "absent.csv")), expect_rc=2)
    assert "G0_CATALOG_PATH" in out and "missing" in out.lower(), out[-800:]


def test_ignition_refuses_tampered_signatures_digest():
    # Arrange: flip one byte of a copy of the real ground truth.
    src = _user_cache() / "g0_signatures.csv"
    d = _tmpdir("tamsig")
    bad = d / "g0_signatures.csv"
    bad.write_bytes(src.read_bytes()[:-1] + b"x" if src.read_bytes()[-1:] != b"x"
                    else src.read_bytes()[:-1] + b"y")
    p, out = _run(_valid_env(G0_SIGNATURES_PATH=str(bad)), expect_rc=2)
    assert "tampered digest" in out and "signatures" in out, out[-800:]


def test_ignition_refuses_tampered_catalog_digest():
    src = _user_cache() / "g0_catalog.csv"
    d = _tmpdir("tamcat")
    bad = d / "g0_catalog.csv"
    bad.write_bytes(src.read_bytes()[:-1] + b"z" if src.read_bytes()[-1:] != b"z"
                    else src.read_bytes()[:-1] + b"w")
    p, out = _run(_valid_env(G0_CATALOG_PATH=str(bad)), expect_rc=2)
    assert "tampered digest" in out and "catalog" in out, out[-800:]


def test_ignition_refuses_blank_hw_profile():
    p, out = _run(_valid_env(G0_HW_PROFILE="   "), expect_rc=2)
    assert "G0_HW_PROFILE" in out, out[-800:]


# -- single-ignition / ledger laws -------------------------------------------------

def test_fresh_ignition_refuses_on_ignited_campaign():
    d = _tmpdir("ignited")
    (d / ".primary_pi_outdir").write_text("../results/docker_primary_pi_x\n")
    p, out = _run(_valid_env(G0_PI_CACHEDIR=str(d),
                             G0_PI_OUTDIR=_tmpdir("ignited_out")), expect_rc=2)
    assert "already ignited" in out, out[-800:]


def test_ignition_refuses_ledger_double_full_row():
    out_d = _tmpdir("dblledg")
    _seed_ledger(out_d, 2)
    p, out = _run(_valid_env(G0_PI_CACHEDIR=_tmpdir("dblledg_cache"),
                             G0_PI_OUTDIR=str(out_d)), expect_rc=2)
    assert "ledger refuses" in out, out[-800:]


def test_resume_control_accepts_single_full_row():
    cache = _tmpdir("rsc")
    out_d = _tmpdir("rsout")
    _seed_ledger(out_d, 1)
    (cache / ".primary_pi_outdir").write_text(str(out_d) + "\n")
    p, out = _run(_valid_env(G0_REUSE_CACHE=str(cache)), expect_rc=0)
    assert "PREFLIGHT-PASS" in out, out[-800:]


def test_resume_refuses_when_ledger_doubled():
    cache = _tmpdir("rsc2")
    out_d = _tmpdir("rsout2")
    _seed_ledger(out_d, 2)
    (cache / ".primary_pi_outdir").write_text(str(out_d) + "\n")
    p, out = _run(_valid_env(G0_REUSE_CACHE=str(cache)), expect_rc=2)
    assert "ledger refuses" in out, out[-800:]


def test_ignition_refuses_second_concurrent_holder():
    d = _tmpdir("marker")
    (d / ".campaign-running").write_text(f"{os.getpid()}\n")   # alive holder
    p, out = _run(_valid_env(G0_PI_CACHEDIR=str(d),
                             G0_PI_OUTDIR=_tmpdir("marker_out")), expect_rc=2)
    assert "second ignition refused" in out, out[-800:]


# -- co-tenancy bar laws (docker + load samplers) ----------------------------------

def _docker_shim(d: Path, ps_body: str, images_body: str) -> None:
    d.mkdir(parents=True, exist_ok=True)
    shim = d / "docker"
    shim.write_text(
        "#!/bin/sh\n"
        'sub="$1"; shift\n'
        'case "$sub" in\n'
        f'  ps)  printf \'%s\\n\' \'{ps_body}\' ;;\n'
        f'  images) printf \'%s\\n\' \'{images_body}\' ;;\n'
        "  *) : ;;\n"
        "esac\nexit 0\n")
    shim.chmod(0o755)


def test_ignition_refuses_missing_images():
    d = _tmpdir("shim_noimg")
    _docker_shim(d, "", "")
    env = _valid_env(PATH=f"{d}{os.pathsep}{os.environ['PATH']}",
                     G0_PI_CACHEDIR=_tmpdir("shim_noimg_c"),
                     G0_PI_OUTDIR=_tmpdir("shim_noimg_o"))
    p, out = _run(env, expect_rc=2)
    assert "image missing" in out and "g0-sigfit" in out, out[-800:]


def test_co_tenancy_refuses_live_measurement_container():
    d = _tmpdir("shim_busy")
    _docker_shim(d, "intruder g0-stl", "abc123")
    env = _valid_env(PATH=f"{d}{os.pathsep}{os.environ['PATH']}",
                     G0_PI_CACHEDIR=_tmpdir("shim_busy_c"),
                     G0_PI_OUTDIR=_tmpdir("shim_busy_o"))
    p, out = _run(env, expect_rc=2)
    assert "co-tenancy refused" in out and "intruder" in out, out[-800:]


def test_co_tenancy_refuses_over_bar_load():
    d = _tmpdir("shim_load")
    d.mkdir(parents=True, exist_ok=True)
    fake = d / "sysctl"
    fake.write_text("#!/bin/sh\necho '{ 42.00 42.00 42.00 }'\nexit 0\n")
    fake.chmod(0o755)
    env = _valid_env(G0_PI_SYSCTL=str(fake),
                     G0_PI_CACHEDIR=_tmpdir("shim_load_c"),
                     G0_PI_OUTDIR=_tmpdir("shim_load_o"))
    p, out = _run(env, expect_rc=2)
    assert "over BAR" in out, out[-800:]


def test_bar_is_not_an_operator_knob():
    env = _valid_env(G0_PI_LOAD_BAR="999",
                     G0_PI_CACHEDIR=_tmpdir("knob_c"),
                     G0_PI_OUTDIR=_tmpdir("knob_o"))
    p, out = _run(env, expect_rc=2)
    assert "not an operator knob" in out, out[-800:]


# -- mock-face orchestration liveness (calibration grade) ----------------------------

def test_mock_rehearsal_ledger_is_calibration_only():
    cache, out_d = _tmpdir("mrh_c"), _tmpdir("mrh_o")
    env = _valid_env(G0_PI_REHEARSAL="mock", G0_PI_REPS="1",
                     G0_PI_SHARDS="main nb clock_sparse",
                     G0_PI_CACHEDIR=str(cache), G0_PI_OUTDIR=str(out_d),
                     G0_PI_PREFLIGHT=None)
    p, out = _run(env)
    assert p.returncode == 0, out[-1500:]
    assert "REHEARSAL-COMPLETE" in out, out[-800:]
    rows = [json.loads(l) for l in
            (out_d / "campaign_launches.jsonl").read_text().splitlines() if l.strip()]
    assert len(rows) == 1 and rows[0]["kind"] == "launch" \
        and rows[0]["mode"] == "rehearsal", rows
    master = out_d / "timings_sharded_master.csv"
    lines = master.read_text().splitlines()
    assert lines[0] == NINE_COL_HEADER, lines[0]
    assert len(lines) > 1
    import csv as _csv
    import socket
    with master.open(newline="", encoding="utf-8") as fh:
        rows9 = [r for r in _csv.DictReader(fh) if r.get("cell")]
    assert rows9
    assert {r["host"] for r in rows9} == {socket.gethostname()}
    assert {r["cpu_seconds"] for r in rows9} == {"unmeasured"}
    assert {r["hw_profile"] for r in rows9} == {CANON_PIN}


# -- rollup + reader verifier units ---------------------------------------------------

def _write_timings(path: Path, rows: list) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("cell,tool,arm,n,seconds,status\n"
                    + "".join(f"{c},t,{a},{n},{s},{st}\n" for c, a, n, s, st in rows))


def test_rollup_merges_final_pass_repairs():
    d = _tmpdir("roll")
    shard = d / "shard_out" / "nb" / "timings_primary_x.csv"
    final = d / "timings_primary_y.csv"
    _write_timings(shard, [("sigfit__nb__N1000", "nb", 1000, 31.0, "ok"),
                           ("stl__nb__N1000", "nb", 1000, 12.0, "fail: boom")])
    _write_timings(final, [("sigfit__nb__N1000", "nb", 1000, 0.0, "cached"),
                           ("stl__nb__N1000", "nb", 1000, 95.0, "ok")])
    out_csv = d / "master.csv"
    p = subprocess.run([sys.executable, str(ROLLUP), "--shard-root",
                        str(d / "shard_out"), "--final", str(final),
                        "--host", "testhost", "--hw-profile", CANON_PIN,
                        "--out", str(out_csv)], capture_output=True, text=True)
    assert p.returncode == 0, p.stdout + p.stderr
    lines = out_csv.read_text().splitlines()
    assert lines[0] == NINE_COL_HEADER
    assert len(lines) == 3, lines
    m = {l.split(",")[0]: l.split(",") for l in lines[1:]}
    assert m["sigfit__nb__N1000"][5] == "ok" and m["sigfit__nb__N1000"][4] == "31.0"
    assert m["stl__nb__N1000"][5] == "ok" and m["stl__nb__N1000"][4] == "95.0"
    assert all(c[6] == "unmeasured" and c[7] == "testhost" and c[8] == CANON_PIN
               for c in m.values())


def test_reader_verifier_passes_and_flags_divergence():
    d = _tmpdir("verif")
    good = d / "m.csv"
    good.write_text(NINE_COL_HEADER + "\n"
                    + "c1,t,a,100,5.0,ok,unmeasured,testhost," + CANON_PIN + "\n")
    p = subprocess.run([sys.executable, str(VERIFIER), "--table", str(good),
                        "--host", "testhost", "--hw-profile", CANON_PIN],
                       capture_output=True, text=True)
    assert p.returncode == 0 and json.loads(p.stdout)["ok"] is True, p.stdout

    bad = d / "bad1.csv"
    bad.write_text(good.read_text().replace(CANON_PIN, "99 GPU class", 1))
    p = subprocess.run([sys.executable, str(VERIFIER), "--table", str(bad),
                        "--host", "testhost", "--hw-profile", CANON_PIN],
                       capture_output=True, text=True)
    v = json.loads(p.stdout)
    assert p.returncode == 1 and v["mismatched_hw_profile"] == ["c1"], p.stdout

    bad2 = d / "bad2.csv"
    bad2.write_text(good.read_text().replace("unmeasured", "123.4", 1))
    p = subprocess.run([sys.executable, str(VERIFIER), "--table", str(bad2),
                        "--host", "testhost", "--hw-profile", CANON_PIN],
                       capture_output=True, text=True)
    v = json.loads(p.stdout)
    assert p.returncode == 1 and v["unattested_cpu_claim"] == ["c1"], p.stdout

    p = subprocess.run([sys.executable, str(VERIFIER), "--table", str(d / "nope.csv"),
                        "--host", "testhost", "--hw-profile", CANON_PIN],
                       capture_output=True, text=True)
    assert p.returncode == 2, p.stdout
