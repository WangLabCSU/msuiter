# RB-11 restoration — instrument liveness attestation and evidence-snapshot laws (2026-10-10)

Restoration record. An earlier commit carried the RB-11 recording into the branch,
was orphaned by a later rebase, and was pruned by gc: `git grep` over the current
lineage finds zero RB-11 trace. The ruling texts survived only in the controller's
governing ledger. This file restores them to the tracked lane. Ruling IDs and
violation names only; no persons, per the established doctrine.

- **RB-11(i) — instrument-liveness attestation law.** An observation instrument may be
  cited as *live* in a report only after a post-deployment liveness attestation: a
  pre-echo to its own capture, or controller-verifiable process evidence (a ps-class
  line proving the watcher itself is resident). Companion clause defines *dry-run*
  strictly: **end-to-end execution of the instrument under its target interpreter** —
  pattern-grepping fixture lines is not a dry-run. Both directions were proven by the
  same failure family: a watcher reported as armed had died on launch
  (`declare: -A: invalid option` — associative arrays need bash ≥ 4, macOS ships 3.2)
  and emitted zero events across a full matrix pass while its owner reported it as
  watching; a second-generation watch died silently to double-escaped quoting in an
  inline command, its progress lines printing blank (`0/13` the whole time). The
  generalization: *a failed instrument that looks armed is worse than none — the
  controller idles past terminal states waiting on events that can never be emitted.*
  Corollary from the same hour: report timestamps and counts come from command output
  only; a compose-time-fabricated start stamp stands as the negative example.
- **RB-11(ii) — no redirect-target reuse across launches.** A log path written with
  `>` may never be reused as the redirect target of a relaunch without first
  snapshotting the prior bytes to a timestamped path. Violation instance: the second
  ignition's `>` truncate destroyed ignition-1's own launch evidence, deepening the
  very forensics deficit the incident review then had to reconstruct from transcripts.
  The law: *snapshot first, or the relaunch truncates the evidence of the run you
  still must explain.*
- **Orphaning forensics (3a973e2).** The pre-restoration recording commit became
  unreachable when its branch line was rebased; `git cat-file -s 3a973e2` now fails,
  and `git fsck --dangling` lists no commit bearing the RB-11 subject. The pruned
  content was not invention: both laws had already bound behavior between their
  entry and this restoration (attestation regime in force for every watch deployed
  after it; log-reuse check in force before every relaunch). This file is the
  authoritative tracked-lineage copy going forward.
- **Lane-transfer note (controller, symmetric accountability).** This restoration and
  the companion artifact commit (`docs(m7): authoritative degraded run artifacts …`)
  were dispatched to the worker lane twice with fully specified content and produced
  zero diff both times (HEAD unchanged across both resumes, outdir still untracked).
  They were executed on the controller lane instead; the transfer and its evidence
  are recorded in that artifact commit's message. Delegated-to-lane idleness is
  surfaced, not silently absorbed.
