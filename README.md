# msuiter

**A modern, high-performance mutational signature analysis ecosystem — Rust engine, R interface.**

msuiter is the fully modernized successor of [sigminer](https://github.com/ShixiangWang/sigminer): a scientific, accurate, reliable and professional toolkit for mutational signature analysis across all variant classes — **SBS, DBS, indel, copy number (CNV), structural variant (SV), and RNA-SBS** — with extraction and fitting performance benchmarked against SigProfiler.

**Positioning: the Seurat of mutational signatures** — a central object model, one workflow grammar (`ms_variants() |> ms_tally() |> ms_extract() |> ms_fit() |> ms_compare()`), interface-parity engines for all mainstream and advanced methods (swap engines in one line for methodological comparison), with our own calibrated statistical methods (MSU-Fit / MSU-LowCount / MSU-Infer) as the default path. Full functional coverage (identification, quantification, visualization, application workflows & visual mining) is tracked in the [capability matrix](docs/CAPABILITY-MATRIX.md).

> **Status: research & design phase.** Implementation has not started; this repository currently hosts the comprehensive research and architecture design that will drive a paper-grade development effort.

## Documentation

| Document | Content |
|---|---|
| [docs/research/00-executive-summary.md](docs/research/00-executive-summary.md) | Research executive summary (methods, fitting, applications, source audit, standards) |
| [docs/research/01-extraction-methods.md](docs/research/01-extraction-methods.md) | De-novo extraction landscape & NMF compute engines (with update equations) |
| [docs/research/02-fitting-inference.md](docs/research/02-fitting-inference.md) | Fitting, attribution, uncertainty quantification, post-fitting analyses |
| [docs/research/03-applications.md](docs/research/03-applications.md) | Application literature & scenarios → workflow module requirements (with PMIDs) |
| [docs/research/04-source-audit.md](docs/research/04-source-audit.md) | Repo-by-repo source audit (algorithms to file:line, licenses) |
| [docs/research/05-standards-data.md](docs/research/05-standards-data.md) | COSMIC licensing, channel standards, genome access, visualization, benchmarks, CRAN policy |
| [docs/research/06-s7-class-system.md](docs/research/06-s7-class-system.md) | S7 object system: status, design patterns, engine-registry blueprint |
| [docs/research/07-algorithm-zoo.md](docs/research/07-algorithm-zoo.md) | Exhaustive layered algorithm zoo + integrated-method opportunities |
| [docs/research/08-fact-check-audit.md](docs/research/08-fact-check-audit.md) | Fact-check audit of the dossier (discrepancy resolutions) |
| [docs/CAPABILITY-MATRIX.md](docs/CAPABILITY-MATRIX.md) | **Capability coverage matrix** — the authoritative completeness checklist (9 layers, per-capability methods/engines/defaults/visualization/milestones) |
| [docs/reviews/00-synthesis.md](docs/reviews/00-synthesis.md) | **Five-expert independent review synthesis (adopt/reject verdicts)** |
| [docs/reviews/01–05](docs/reviews/01-computational-biologist.md) | Independent adversarial reviews: computational biologist / Rust-R engineer / ML statistician / software engineer / Nature editor |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modular architecture: Rust workspace + S7 package, ADRs, unified method framework, MSU-* methods |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Dual-track paper-oriented roadmap (v0.1 / v0.2 / v1.0) with organizational gates |

## Design pillars

- **Rust core, R interface** — extendr/rextendr-based; hot paths (NMF engines, NNLS, likelihood kernels, channel assignment, resampling, consensus clustering, genome context via mmap 2bit) live in Rust.
- **Scientific fidelity** — bit-compatibility targets: SigProfilerMatrixGenerator channel semantics, MuSiCal sparse-NNLS, SigProfiler consensus pipeline, HRDetect coefficients; every kernel validated by golden fixtures.
- **Methodological frontier** — SigProfiler-compatible extraction + SUITOR-style CV K-selection + correlation-aware extraction (Cornet-lineage model, own optimized implementation) + mSigAct-style likelihood-ratio presence testing + calibrated bootstrap CIs (unvalidated in the field) + compositional-data analyses.
- **Tidy & orthogonal** — `ms_*` S7 API, label-validated channel registry, versioned reference databases (COSMIC v3.6 bundled with provenance), zero magic strings.
- **Paper-driven** — all code, tests, docs feed three paper sections: architecture & implementation; performance & benchmark; application case studies.

## License

Apache-2.0. Reference signature data bundled from the Alexandrov-lab BSD-2 mirror (SigProfilerAssignment) with full provenance; see [docs/research/05-standards-data.md](docs/research/05-standards-data.md) for licensing analysis.

## Author

Shixiang Wang (王诗翔) — Wang Lab, CSU. Author of [sigminer](https://github.com/ShixiangWang/sigminer).
