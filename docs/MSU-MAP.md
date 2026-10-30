# The MSU concept map (MSU-MAP)

One row per exported function in NAMESPACE. Columns: the exported face,
the concept it serves on the msuiter platform, the paper pillar it carries
(p1 architecture, p2 performance, p3 application scenarios -- the D14
positioning in [ARCHITECTURE.md](docs/ARCHITECTURE.md#10-the-paper-positioning-d14), and its
peer counterpart: a real sigminer (CRAN) or sigprofiler function name, or
NONE with the reason none exists.

Laws (governed by tests/testthat/test-pkgdown-msu-map.R -- the row set is
re-derived from the NAMESPACE bytes, this file carries no hand-kept
roster): every row's pillar cell names one of the three pillars and
carries a live repo anchor (path#heading-slug, resolved against the
heading bytes at test time); every peer cell is `tool::function` or
`NONE -- reason`. Peer names were verified at authoring time against the
local CRAN 2.3.3 sigminer ground truth (2026-10-30); the CI gate checks
the SHAPE of the peer column, not the peer's installed catalogue.

<!-- msu-map:table-begin -->
| function | MSU concept served | paper pillar (anchor) | peer counterpart |
|---|---|---|---|
| MsArd | The ARD-NMF engine specification plugged into the registry (divisive error reduction). | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- peer tools fix the extraction algorithm; the registry-pluggable engine face is msuiter's (the nearest sigminer face is bp_extract_signatures, plain NMF) |
| MsBenchmark | The benchmark-grid results container carrying witness provenance per cell. | performance (docs/ARCHITECTURE.md#8-performance-and-benchmark-the-v21-upgrade) | NONE -- sigminer ships a scoring helper (scoring) but no results container |
| MsCatalog | The channel-count matrix with a channel-registry snapshot: the typed tally IR. | architecture (docs/ARCHITECTURE.md#3-the-r-package-structure-and-the-s7-class-system) | NONE -- sigminer hands back plain tally lists/matrices |
| MsComparison | The calibrated-comparison result with its matching protocol recorded. | architecture (docs/ARCHITECTURE.md#5-the-method-system-v21-contracted-to-three-named-methods-components) | NONE -- sigminer returns bare cosine matrices (get_sig_similarity) |
| MsEngine | The abstract engine specification: the registry contract object. | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- no peer engine-plugin surface exists |
| MsFit | Reference-fitted exposures with a reference snapshot: the estimand-fidelity record. | architecture (docs/ARCHITECTURE.md#3-the-r-package-structure-and-the-s7-class-system) | NONE -- sigminer returns plain data.frame lists from sig_fit |
| MsNmf | The NMF engine specification (kl/eu faces). | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- the peer face is sigminer::bp_extract_signatures, not a spec object |
| MsRefDb | The versioned reference signature database object with bundled-first precedence. | architecture (docs/ARCHITECTURE.md#6-data-and-standards-the-v21-revision) | sigminer::get_sig_db |
| MsSignature | Extracted signatures with a catalog snapshot summary. | architecture (docs/ARCHITECTURE.md#3-the-r-package-structure-and-the-s7-class-system) | sigminer::sig_signature |
| MsSparse | The penalized sparse-NMF engine specification (volume/L1 regularizers). | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- no peer sparse-NMF plugin; the sigminer face bp_extract_signatures is unpenalized NMF |
| MsStratification | The hypermutator stratification decision (GMM cutoff, exclusion, forced refit). | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | sigminer::handle_hyper_mutation |
| MsVariants | The validated variant calls with somaticness provenance: the typed input IR. | architecture (docs/ARCHITECTURE.md#3-the-r-package-structure-and-the-s7-class-system) | sigminer::read_vcf |
| fit_engine | Runs a registered engine through its implementation (registry dispatch). | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- no peer dispatch registry exists |
| match_ms_engine | Resolves string sugar to an MsEngine specification. | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- no peer engine sugar to resolve |
| ms_ard | The ARD-NMF engine factory. | architecture (docs/CAPABILITY-MATRIX.md#l-c-signature-identification-de-novo-extraction----the-engine-equivalence-matrix) | NONE -- ARD ships as an engine here; the nearest peer face, bp_extract_signatures, has no ARD split |
| ms_benchmark | Constructs an MsBenchmark from the grid plus witnessed cells. | performance (docs/ARCHITECTURE.md#8-performance-and-benchmark-the-v21-upgrade) | NONE -- no peer benchmark orchestrator |
| ms_benchmark_grid | Constructs one benchmark scenario cell under the frozen geometry. | performance (docs/ARCHITECTURE.md#8-performance-and-benchmark-the-v21-upgrade) | NONE -- sigminer has no scenario-grid face |
| ms_calibration_grid | The Monte-Carlo coverage grid over exposure intervals (MSU-Fit calibration). | performance (docs/ROADMAP.md#m3b----msu-fit-calibration-statistics-6-weeks-the-g2-gate-must-be-reached-in-this-period) | NONE -- no peer publishes empirical coverage evidence |
| ms_calibration_sanity | The real-data downsampling sanity harness for exposure intervals. | performance (docs/ROADMAP.md#m3b----msu-fit-calibration-statistics-6-weeks-the-g2-gate-must-be-reached-in-this-period) | NONE -- no peer sanity harness exists |
| ms_calibration_verdict | The structured window verdict over a calibration grid. | performance (docs/ROADMAP.md#m3b----msu-fit-calibration-statistics-6-weeks-the-g2-gate-must-be-reached-in-this-period) | NONE -- no peer verdict window exists |
| ms_catalog | Constructs an MsCatalog object. | architecture (docs/ARCHITECTURE.md#3-the-r-package-structure-and-the-s7-class-system) | NONE -- the peer tally container is the plain output_tally list |
| ms_catalog_currency | Verifies the pinned COSMIC catalog snapshot for currency. | architecture (docs/ARCHITECTURE.md#6-data-and-standards-the-v21-revision) | NONE -- peers pin no official-source digest |
| ms_catalog_currency_update | Refreshes the catalog-currency cache from the official source documents. | architecture (docs/ARCHITECTURE.md#6-data-and-standards-the-v21-revision) | NONE -- peers carry no currency updater |
| ms_catalog_registry | The committed catalog-currency digest registry. | architecture (docs/ARCHITECTURE.md#6-data-and-standards-the-v21-revision) | NONE -- peers carry no digest registry |
| ms_cluster_signatures | Clusters signatures by cosine similarity. | scenarios (docs/CAPABILITY-MATRIX.md#l-e-post-fitting-analysis) | sigminer::same_size_clustering |
| ms_compare | Calibrated comparison of two signature dictionaries (Hungarian/Islam/Jiang protocols). | architecture (docs/ARCHITECTURE.md#5-the-method-system-v21-contracted-to-three-named-methods-components) | sigminer::get_sig_similarity |
| ms_comparison | Constructs an MsComparison object. | architecture (docs/ARCHITECTURE.md#5-the-method-system-v21-contracted-to-three-named-methods-components) | NONE -- no peer comparison container |
| ms_convert | Converts signatures between mutational opportunity representations. | architecture (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | sigminer::sig_convert |
| ms_downsample | Downsamples a catalog to a common depth. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer common-depth face |
| ms_embed | Embeds samples by their exposure profiles. | scenarios (docs/CAPABILITY-MATRIX.md#l-g-application-scenario-workflows-and-visual-data-mining) | NONE -- peers ship no embedding face |
| ms_engines | Lists registered engines. | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- no peer registry to list |
| ms_export | Exports a catalog or signature set in a file format. | architecture (docs/ARCHITECTURE.md#6-data-and-standards-the-v21-revision) | sigminer::output_tally |
| ms_exposure_test | Tests per-signature exposure differences between sample groups. | scenarios (docs/CAPABILITY-MATRIX.md#l-e-post-fitting-analysis) | sigminer::get_group_comparison |
| ms_extract | Extracts signatures from a catalog (the consensus-CV pipeline default). | architecture (docs/ARCHITECTURE.md#5-the-method-system-v21-contracted-to-three-named-methods-components) | sigminer::sig_extract |
| ms_fit | Fits signature exposures against given signatures (the MSU-Fit default). | architecture (docs/ARCHITECTURE.md#5-the-method-system-v21-contracted-to-three-named-methods-components) | sigminer::sig_fit |
| ms_fit_bootstrap | Bootstrap percentile confidence intervals for signature exposures. | performance (docs/ROADMAP.md#m3a----fitting-three-methods-bootstrap-4-weeks) | sigminer::sig_fit_bootstrap |
| ms_hrd_report | The HRD report from allele-specific segment calls. | scenarios (docs/ROADMAP.md#m6s----hrd-workflow-3-weeks-the-scope-safety-contract-in-force) | sigminer::get_pLOH_score |
| ms_import | Imports a file into a catalog or signature set. | architecture (docs/ARCHITECTURE.md#6-data-and-standards-the-v21-revision) | sigminer::sigprofiler_import |
| ms_nmf | Creates the NMF engine specification (factory). | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- the peer face is sigminer::bp_extract_signatures |
| ms_qc_artifact_roster | The cataloged COSMIC artifact roster. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer artifact-roster face |
| ms_qc_burden | The per-sample burden distribution table. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer burden-table face |
| ms_qc_mechanism_channels | The SBS96 mechanism-channel roster. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer mechanism roster |
| ms_qc_provenance | The QC provenance checklist. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer QC provenance face |
| ms_qc_report | The per-sample QC report. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer sample-level QC face |
| ms_qc_roster_share | The per-sample artifact-roster exposure share. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer roster-share face |
| ms_qc_sentries | The per-sample gt/ct mechanism sentries. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer mechanism-sentry face |
| ms_refdb | Constructs an MsRefDb object. | architecture (docs/ARCHITECTURE.md#6-data-and-standards-the-v21-revision) | sigminer::get_sig_db |
| ms_refdb_bundled | The bundled reference signature database (COSMIC v3.6). | architecture (docs/ARCHITECTURE.md#6-data-and-standards-the-v21-revision) | sigminer::get_sig_db |
| ms_refdb_manifest | The governance manifest of the bundled reference database. | architecture (docs/ARCHITECTURE.md#6-data-and-standards-the-v21-revision) | NONE -- peers carry no governance manifest |
| ms_run_benchmark | Runs the benchmark grid to completion with witnessed cells. | performance (docs/ARCHITECTURE.md#8-performance-and-benchmark-the-v21-upgrade) | sigminer::scoring |
| ms_segments | Reads allele-specific copy-number segments into a typed table. | architecture (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | sigminer::read_copynumber |
| ms_select_k | Selects the signature count from a rank grid (the consensus-CV evidence). | architecture (docs/ARCHITECTURE.md#5-the-method-system-v21-contracted-to-three-named-methods-components) | sigminer::sig_estimate |
| ms_signature | Constructs an MsSignature object. | architecture (docs/ARCHITECTURE.md#3-the-r-package-structure-and-the-s7-class-system) | sigminer::sig_signature |
| ms_simulate | Simulates a catalog from a signature dictionary (shared by benchmarks and tests). | performance (docs/CAPABILITY-MATRIX.md#l-b-catalog-representation) | sigminer::simulate_catalogue |
| ms_sitrep | The situation report for the msuiter installation. | architecture (docs/ROADMAP.md#m0----engineering-foundations-2-weeks-the-original-05-1-week-estimate-was-rejected-by-review) | NONE -- peers carry no installation sitrep face |
| ms_sparse | Creates the penalized sparse-NMF engine specification (factory). | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- no peer sparse engine to construct |
| ms_stratify_hypermutants | Stratifies hypermutated samples with the SigProfiler GMM cutoff. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | sigminer::handle_hyper_mutation |
| ms_sv | Reads structural-variant calls (BEDPE) into a typed table. | architecture (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | sigminer::read_sv_as_rs |
| ms_tally | Tallies variants into a channel catalog (the SBS/DBS/ID families). | architecture (docs/ARCHITECTURE.md#2-the-rust-workspace-srcrust) | sigminer::sig_tally |
| ms_test_presence | The cohort presence test for signature exposures (BH-corrected LRT). | performance (docs/ARCHITECTURE.md#5-the-method-system-v21-contracted-to-three-named-methods-components) | NONE -- peers report raw exposures with no presence test |
| ms_treatment_report | The treatment-forensics report: bootstrap-CI association plus clonal timing. | scenarios (docs/devlog/2026-10-28-p8-treatment-forensics-design.md) | NONE -- no peer treatment-record face exists |
| ms_variants | Reads variant calls into an MsVariants object. | architecture (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | sigminer::read_vcf |
| plot_boot_ci | The bootstrap CI error bars for one sample's exposures. | performance (docs/ROADMAP.md#m3a----fitting-three-methods-bootstrap-4-weeks) | sigminer::show_sig_bootstrap_error |
| plot_boot_distribution | The bootstrap exposure distributions for one sample. | performance (docs/ROADMAP.md#m3a----fitting-three-methods-bootstrap-4-weeks) | sigminer::show_sig_bootstrap_exposure |
| plot_boot_stability | The bootstrap stability bar face. | performance (docs/ROADMAP.md#m3a----fitting-three-methods-bootstrap-4-weeks) | sigminer::show_sig_bootstrap_stability |
| plot_calibration_curve | The calibration coverage curve of a grid measurement. | performance (docs/ROADMAP.md#m3b----msu-fit-calibration-statistics-6-weeks-the-g2-gate-must-be-reached-in-this-period) | NONE -- no peer calibration curve to plot |
| plot_catalog_profile | Plots one profile column in COSMIC style. | architecture (docs/CAPABILITY-MATRIX.md#l-f-basic-visualization-native-ggplot2-the-cosmic-style-specification-canonical-order-enforced-the-official-palette-class-group-separation-dual-axes-vector-output) | sigminer::show_sig_profile |
| plot_cosmic_scatter | The estimate-vs-COSMIC-reference scatter. | architecture (docs/CAPABILITY-MATRIX.md#l-f-basic-visualization-native-ggplot2-the-cosmic-style-specification-canonical-order-enforced-the-official-palette-class-group-separation-dual-axes-vector-output) | sigminer::show_cosmic |
| plot_embedding | The sample-embedding scatter. | scenarios (docs/CAPABILITY-MATRIX.md#l-g-application-scenario-workflows-and-visual-data-mining) | NONE -- peers ship no embedding plot |
| plot_exposure_heatmap | The exposure heatmap (samples x signatures). | scenarios (docs/CAPABILITY-MATRIX.md#l-f-basic-visualization-native-ggplot2-the-cosmic-style-specification-canonical-order-enforced-the-official-palette-class-group-separation-dual-axes-vector-output) | NONE -- the peer face show_sig_profile_heatmap profiles signatures, not samples x signatures |
| plot_exposure_riverplot | The exposure riverplot (samples x signature flow). | scenarios (docs/CAPABILITY-MATRIX.md#l-f-basic-visualization-native-ggplot2-the-cosmic-style-specification-canonical-order-enforced-the-official-palette-class-group-separation-dual-axes-vector-output) | NONE -- no peer riverplot face |
| plot_exposure_stacked | The stacked exposure bars per sample. | scenarios (docs/CAPABILITY-MATRIX.md#l-f-basic-visualization-native-ggplot2-the-cosmic-style-specification-canonical-order-enforced-the-official-palette-class-group-separation-dual-axes-vector-output) | sigminer::show_sig_exposure |
| plot_hypermutator_burden | The hypermutator burden histogram with the stored cutoff line. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer burden/cutoff figure face |
| plot_k_cv_curve | The CV-error curve from K-selection evidence. | architecture (docs/ARCHITECTURE.md#5-the-method-system-v21-contracted-to-three-named-methods-components) | sigminer::bp_get_rank_score |
| plot_k_stability | The consensus-stability curves from K-selection evidence. | architecture (docs/ARCHITECTURE.md#5-the-method-system-v21-contracted-to-three-named-methods-components) | sigminer::show_sig_number_survey2 |
| plot_opportunity_distribution | The trinucleotide opportunity landscape. | architecture (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer opportunity-landscape face |
| plot_pseudosig_contribution | The artifact-signature contribution ranking. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer pseudosignature figure face |
| plot_qc_dashboard | The QC dashboard: burden bars plus the sentry shares. | scenarios (docs/CAPABILITY-MATRIX.md#l-a-data-acquisition-qc-and-preprocessing) | NONE -- no peer QC dashboard face |
| plot_reconstruction_panel | Original vs reconstruction with a per-channel residual strip. | architecture (docs/ARCHITECTURE.md#5-the-method-system-v21-contracted-to-three-named-methods-components) | sigminer::show_sig_fit |
| plot_reference_comparison | Compares an estimated profile against a reference profile. | architecture (docs/CAPABILITY-MATRIX.md#l-f-basic-visualization-native-ggplot2-the-cosmic-style-specification-canonical-order-enforced-the-official-palette-class-group-separation-dual-axes-vector-output) | sigminer::show_cosmic_sig_profile |
| plot_signature_catalog | Plots a signature set as a facet grid. | architecture (docs/CAPABILITY-MATRIX.md#l-f-basic-visualization-native-ggplot2-the-cosmic-style-specification-canonical-order-enforced-the-official-palette-class-group-separation-dual-axes-vector-output) | sigminer::show_sig_profile |
| plot_similarity_heatmap | The similarity heatmap from an ms_compare result. | architecture (docs/CAPABILITY-MATRIX.md#l-f-basic-visualization-native-ggplot2-the-cosmic-style-specification-canonical-order-enforced-the-official-palette-class-group-separation-dual-axes-vector-output) | NONE -- get_sig_similarity computes the matrix; the 2.3.3 face set ships no heatmap plot |
| register_ms_engine | Registers an engine in the msuiter engine registry. | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- no peer registration surface |
| required_pkgs | Reports the packages required by an engine. | architecture (docs/ARCHITECTURE.md#34-the-engine-registry-v21-adds-the-governance-fields) | NONE -- no peer dependency-report face |
<!-- msu-map:table-end -->

