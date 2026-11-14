# PF forensics — P10 bridge landing + pipeline-floor localization (re-landed evidence carrier)

Re-landed 2026-11-14 per the sealed design memo §5 ruling
(`vignettes/articles/devlog-2026-11-10-r1-parity-regen-design.qmd`: "Ruling:
**re-land under `bench/`** as part of the same phase as the regeneration,
because the paper's forensics-direction sentence (paper-draft.qmd:261-263)
cites pipeline-floor localization and needs committed, path-bound evidence
behind it.").

Every figure below is quoted from committed, path-bound carriers. The
kernel-share percentages and stub controls deliberately do NOT appear: they
have no committed carrier anywhere in the repository (/tmp-lane records,
per the novelty-scan R1 disposition and the P9 reified-provenance pattern).

## 1. P10 batch-bridge landing (bit-identical)

Anchor: commit object `2296f49` message bytes (PR #62 merge; re-derive:
`git show -s --format=%B 2296f49`).

> A0 per-run before 0.14060 s/run | A3 batch after 0.06112 s/run
> landing ratio 2.3004 (per-k 2.74/2.43/2.19/2.04).
> The <=2x peer-parity row stays BREACH at the system level; this lane
> delivers its measured share toward the needed 6.7x, honestly.

Same message bytes carry the law expectations (476 in
`test-kernel-bit-identity.R` + 346 in `test-kernel-batch-bridge.R`), the
bit-identity attestation (before binary, `--full-trace` and production
faces agree byte-for-byte on W/H/meta witnesses over the 16-task grid),
and the floors-sealed probe: "floors sealed (floor_table_epoch
f3e894a6933a2ffb unchanged, probed)". That probe quote is a byte-quote of
the 2296f49 record — the epoch itself has since been superseded to
`cfdcc51dbb9b7041` (erratum:
`vignettes/articles/devlog-2026-11-14-gen4-census-erratum.qmd`); the quote
stays byte-exact, the supersession is recorded around it.

## 2. System-level distance (census-backed)

The O5 parity census (gen-4 bank,
`bench/results/p6_regen_20261111-095635/census_regen_20261114.txt`,
epoch `cfdcc51dbb9b7041`): 168/168 R-face x class cells BREACH the <=2x
bar, per-face cpu-basis range 8.7963–77.6890 (best arm
`sigminer_post_v3_rust_batch`). The bridge-face 2.3004x reduction and the
P11 bit-identical ceilings below are the measured shares delivered toward
the needed system-level factor; none of them closes the system-level row.

## 3. Defensible worst-class citation

35.0x (688.16 s vs 19.65 s), five-gate P7-F ruling V1 — committed carrier:
`vignettes/articles/devlog-2026-11-10-novelty-scan.qmd:114` (R1 row) and
`vignettes/articles/research-09-sigminer-v3-parity-plan.qmd` §9
("defensible worst-class citation (supersedes 67.102) | 688.16 / 19.65 =
**35.0x** | five-gate ledger, P7-F ruling V1 | citable").

## 4. Pipeline-floor localization

The ~170 s pipeline-floor finding (five-gate structural section) is
committed via the same novelty-scan R1 row and research-09 §9 ("Closing the
remaining ~35x gap is Phase-2/Phase-3 engine scope (the ~170 s
pipeline-floor finding, five-gate structural section)"). This is the
forensics-direction sentence the paper cites
(`vignettes/articles/paper-draft.qmd:261-263`).

## 5. P11 bit-identical ceilings

`vignettes/articles/devlog-2026-11-09-p11-engine-kl-design.qmd:121-122`:

> | steps only (no per-iteration objective) | 129.920 ms | 106.2 ms (derived) | **1.223x** |
> | end-to-end (Full trace, per-iteration objective) | 237.056 ms | 214.235 ms | 1.107x |

System-level reading (:144): "The O5 census needs ~6.7x system-wide to
reach the <=2x row; 1.223x step-core does not close it. L1-L5 bank the
honest bit-identical ceiling."

## 6. Internal-ruling-only figures (NOT committed measurements)

The bridge-share estimate (33.4% of system mass) and the characterization
"2x measured-foreclosed for bit-identical code" exist only as the internal
ruling at the sealed design memo
(`vignettes/articles/devlog-2026-11-10-r1-parity-regen-design.qmd:166`) and
the novelty-scan R1 row's own instruction ("re-land it in `bench/` **or
cite it only as an internal ruling**"). They are carried here under that
internal-ruling label; they are not measurements and must not be cited as
such.
