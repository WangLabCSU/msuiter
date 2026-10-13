# Research report 03: the application literature and the application-scenario panorama (2012–2026)
> ℹ️ **Document nature**: this piece is a research snapshot (archival snapshot; the verification date is in the text). Live decisions are governed by [ARCHITECTURE.md](../ARCHITECTURE.md) §0 (D1–D16) and [reviews/00-synthesis.md](../reviews/00-synthesis.md); the method names in the text (e.g. MSU-Extract, MSU-Corr) are the wording of the time, the current naming is in ARCHITECTURE §5; the benchmark metrics are governed by [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) and ARCHITECTURE §8.


> Research date: 2026-09-27. Every PMID was verified on the spot via PubMed (NCBI E-utilities); the sample sizes are taken from the abstracts/bodies. The focus is 2020–2026. Every scenario maps to a "reusable workflow the software suite must deliver".

---

## 1. The pan-cancer atlases (cohort-level WGS)

| The study | The citation (PMID) | n | The variant types | The analyses | The software |
|---|---|---|---|---|---|
| PCAWG SBS/DBS/ID | Alexandrov, Nature 2020 (32025018) | 2,780 WGS, 38 cancer types | SBS, DBS, ID | de novo + repair attribution | bespoke (the SigProfiler family), NMF/HDP |
| PCAWG SV | Li Y, Nature 2020 (32025012); chromothripsis Park, Nat Genet 2020 (32025003) | the same cohort | SV (16 rearrangement classes) | SV extraction | bespoke |
| Breast cancer 560 WGS (foundational) | Nik-Zainal, Nature 2016 (27135926) | 560 | SBS, ID, SV, CN | de novo + clonal timing | bespoke |
| Hartwig metastatic | Priestley, Nature 2019 (31645765) | 2,520 | SBS, ID, CN, SV | fitting + treatment-associated signatures | bespoke |
| CN signatures (TCGA) | Steele, Nature 2022 (35705804) | **9,873**, 33 cancer types | CN | de novo CN extraction; the framework generalized to WGS/WES/scDNA/SNP6 | bespoke (later the SigProfiler CN tool) |
| UK GEL SBS/DBS | Degasperi, Science 2022 (35949260) | **12,222** WGS | SBS, DBS | fitting + de novo; the common/rare framework; amber/red QC | the SigProfiler suite |
| SV signatures (100kGP) | Everall, Nat Genet 2026 (41688639) | **10,983** WGS, 16 cancer types | SBS+DBS+ID+CN+**SV (the first reference set)** | five-class de novo; 134 signatures, 26 new COSMIC entries | SigProfiler + bespoke |
| 100kGP precision oncology | Sosinsky, Nat Med 2024 (38200255) | 13,880 solid tumors | whole-genome | signature/CN features + clinical outcomes | institutional pipelines |
| The pediatric atlases | Ma X, Nature 2018 (29489755); Gröbner, Nature 2018 (29489754); **Greenhalgh, Cancer Cell 2026 (41825442)**: 1,616 children vs 2,203 adults, **10 SV signatures**, SV7=RAG-mediated | — | SBS, SV | SV signature extraction + susceptibility backgrounds | bespoke |

**The implied workflow — the "atlas mode"**: five-variant-class ingestion → the standardized matrix generation (SBS96/DBS78/ID83/CN/SV) → the QC gates (purity, the FFPE/oxoG marks) → the mixed de novo vs reference refit → the common/rare classification → the per-sample activity matrix + clinical-feature association. Everall 2026 made the SV reference set a first citizen → **msuiter should treat SBS/DBS/ID/CN/SV/RNA as symmetric data types**.

## 2. Environmental/lifestyle exposure epidemiology

- **Tobacco**: Alexandrov, Science 2016 (27811275, ~5,243 tumors; SBS4 + the dose-modulated SBS5). Torrens, Nat Genet 2025 (40164736, HNSCC tobacco complexity, field cancerization). Never-smokers: Díaz-Gay/Landi, Nature 2025 (40604281, LCINS). Experimental tobacco-specific nitrosamines: Korenjak/Zavadil, Genome Med 2026 (42393796).
- **UV/melanoma**: Hayward, Nature 2017 (28467829; SBS7 vs the acral SBS38).
- **Aristolochic acid**: Poon/Hoang, Sci Transl Med 2013 (23926199/23926200); Jelaković, IJC 2015 (25403517); Lu, Theranostics 2020 (32292497) — **the AA signature defines the UTUC low-risk subtype** (the exposure signature is itself the clinical stratifier).
- **Colibactin**: Pleguezuelos-Manzano, Nature 2020 (32106218, organoid→SBS88/ID18); Dziubańska-Kusibab, Nat Med 2020 (32483361, IBD); van Boxtel/Rosendahl Huber, Cancer Cell 2024 (38471458); Cornish, Nature 2024 (39112709, 2,023 CRC, colibactin and early-onset CRC); Díaz-Gay, Nature 2025 (40267983, CRC geographic + age variation).
- **Mutographs (geographic etiologies)**: Senkin, Nature 2024 (38693263, kidney cancers); Van Loon, CEBP 2023 (37505926, East-African ESCC); Huang, Cancer Discov 2026 (41532847, gastrointestinal chemical exposure).
- **Alcohol (preclinical)**: Chavanel/Zavadil, Cell Biol Toxicol 2026 (42321443, rat multi-organ).
- **Artificial artifacts as an "exposure"**: formalin Guo, Nat Commun 2022 (36068219); FFPE WGS Basyuni, Nat Commun 2024 (39231944); FFPEsig Methods Mol Biol 2025 (40779107); Excerno J Comput Biol 2023 (36322906, the signature-style FFPE filtering); oxoG Costello, NAR 2013 (23303777); the review Chavanel 2024 (39216514).

**The implied workflow — the "exposure-attribution mode"**: refit against the exposure reference panel (SBS4, SBS7/38, SBS22, SBS24/88, SBS32, SBS31/35, formalin/oxoG) → bootstrap CIs → association tests against the exposure metadata/geography/age → the cohort map. **Requirement: the exposure reference panel + the artifact-first QC (the amber/red style grading)**.

## 3. Treatment signatures and treatment-history deconvolution

- **Temozolomide (SBS11; the MMR failure→SBS1/6+ID1)**: Hwang, NAR 2025 (39656916); Yaacov, Cells 2025 (41511341 the review); panel feasibility Kim, Pathobiology 2026 (42412714); the longitudinal IDH glioma Chowdhury bioRxiv 2025 (40791422).
- **Platins (SBS31/35 + the SV/CN scars)**: Loveday, Nat Commun 2020 (32366847, testicular); Tsang, npj Precis Oncol 2023 (36964191, the HRD signature and the platinum duration).
- **5-FU**: Christensen, Nat Commun 2019 (31594944, the T>G-characteristic).
- **Thiopurines (SBS32)**: Li B, Blood 2020 (31697823, relapsed ALL); Van der Ham, Haematologica 2025 (40371888); Brown bioRxiv 2025 (40568177, testicular GCT).
- **Radiation**: Behjati, Nat Commun 2016 (27615322); Sherborne, Cell Rep 2015 (26344771); Davidson, Sci Rep 2017 (28794481); Daino review Biology 2025 (41007286); Mossanen, Eur Urol 2022 (34953602); the nuclear-test veterans PLoS One 2026 (42378240).
- **Treatment-history deconvolution**: Mendelaar, Nat Commun 2021 (33495476, metastatic CRC — the prior chemotherapy can be detected from the signatures); Brady review, Trends Genet 2022 (34483003).

**The implied workflow — the "treatment forensics mode"**: fit against the treatment reference set (SBS11/25/31/32/35/36 + the treatment ID/SV patterns) → validate against the treatment records → the clonal timing (the clone = pre-treatment, the subclone = during-treatment) → the longitudinal relapse-pair differences. **No mainstream tool offers a treatment-history reporting module — a differentiation opportunity.**

## 4. Germline/repair-deficiency syndromes and HRD

- **POLE/POLD1 (SBS10a–d, SBS14/28)**: van Gool, CCR 2015 (25878334); **Davila, BMC Med Genomics 2021 (34158040) — the RNA-seq signature detects POLE hypermutation**; Mur, Genet Med 2020 (32792570); Cui, Diagn Pathol 2023 (36765365).
- **MMR/MSI**: **Chung, Cancer Discov 2021 (33355208) — the classic polymerase-vs-MMRI distinction of the MSI signatures (incl. indels)**; Lynch normal epithelia Lee BCH, Nat Commun 2022 (35581206); Martin, HMG 2024 (39180486).
- **MUTYH (the ID signature)**: Robinson, Nat Commun 2022 (35803914); **Georgeson, Nat Commun 2022 (35668106) — identifying bialelic MUTYH CRC from the tumor signature alone (a diagnostic-grade use case)**.
- XP/NER: Badja, Cell Rep 2024 (38805398); the BRCA1 nick signature Feng, Nat Commun 2022 (35879372).

**The HRD-tool landscape**:
- **HRDetect** (Davies, Nat Med 2017, 28288110): WGS input (SBS3+ID6+SV3/SV5+HRD-LOH) → calibrated probabilities. The WGS-study gold standard (SCAN-B Staaf 2019 31570822; Banda CCR 2026 42201779; Davies HR Commun Med 2026 41699108).
- **scarHRD** (Sztupinszki, npj Breast Cancer 2018, 29978035): CN only (HRD-LOH+LST+TAI) → a numeric score. The highest clinical-study adoption.
- **CHORD** (Nguyen, Nat Commun 2020, 33149131): a random forest over the SV/CN features → the BRCA1 vs BRCA2-style HRD subtype; WES-friendly.
- The comparative evidence: Sztupinszki CCR 2021 (34380641); **Nacer, Breast Cancer Res 2026 (42351273): across 7 methods vs the FDA assay, the discordance is a live problem**; Fortuno, EBioMedicine 2026 (41797047, HRD aids the BRCA1/2 VUS classification); RNA-based Brown, JCO PO 2023 (38061006); Corti, npj PO 2024 (39402170); Zhao CCR 2017 (29246904); Chopra Nat Commun 2020 (32471999).

**The implied workflow — the "HRD assessment"**: the SBS3/ID6/SV3+SV5 fit + LOH/LST/TAI + the CHORD-style SV features → an ensemble verdict + confidences → the report (the HRD status, the BRCA1 vs BRCA2 tendency, the PARP-i/platinum implications, the germline corroboration). **The composite with the greatest clinical demand; the 2026 comparisons show the tool discordance unresolved — msuiter's ensemble+uncertainty implementation drops straight in.**

## 5. Clinical decisions and biomarkers

- **ICI response**: Litchfield, Cell 2021 (33508232); APOBEC+TMB urothelial Natesan, Front Oncol 2022 (35321431); **Yaacov, ESMO Open 2026 (42378718): the APOBEC signature predicts ICI benefit in TMB-low NSCLC (independent of PD-L1)**; Chumsri, JNCCN 2020 (32380464); the lung adenocarcinoma brain-metastasis risk Li Q, Transl Oncol 2024 (38402722); CHIP TET2 and immunotherapy Rondeau, Cancer Res 2026 (41218172).
- **Prognosis**: myeloma APOBEC and adverse translocations Walker, Nat Commun 2015 (25904160); urologic tumors Karihtala, Neoplasia 2023 (37678146); early-onset breast Basmadjian, Genes 2024 (38790221); bladder adenocarcinoma Yang, J Pathol 2024 (38180342); **the CN karyotype order and the prognosis Watkins, Nature 2020 (32879494)**.
- **Signatures as diagnostic clues**: MUTYH (35668106); the AA-low-risk UTUC (32292497); POLE hypermutant endometriumi management (25878334); panel signature performance Lawrence, APLM 2021 (33571361).
- Drug sensitity: Levatić, Nat Commun 2022 (35614096). The reporting frameworks: van de Haar, Ann Oncol 2024 (39112111); Black, Lancet Oncol 2025 (41072453).
- Lymphoid AID: Kasar, Nat Commun 2015 (26638776); the Maura practice guidance Nat Commun 2019 (31278357).

**The implied workflow — the "biomarker mode"**: a single-sample refit + uncertainty → the standardized biomarker calls (the APOBEC activity, the HRD composite, the ID-signature MSI, the UV load, the clock exposures) → an outcome-modeling table. **Negative/mixed results require reporting the CIs and a pre-registered signature definition.**

## 6. Normal tissues, somatic mosaicism and clonal hemopoiesis

- Skin Martincorena Science 2015 (25999502); esophagus Science 2018 (30337457); colon Lee-Six Nature 2019 (31645730); IBD colon Olafsson Cell 2020 (32697969); endometrium Moore Nature 2020 (32350471); stomach Coorens Nature 2025 (40108450); bladder Lawson Science 2020 (33004514); chronic-liver disease Ng Nature 2021 (34646017).
- Blood/CHIP: Bick Nature 2020 (33057201, 97,691 genomes); Fabre Nature 2022 (35650444, CHIP longitudinal); Moore Nature 2021 (34433962); lymphocytes Machado Nature 2022 (35948631); AML risk Abelson Nature 2018 (29988082); 9/11 responders Verma, Cancer Discov 2025 (41031953). **No standalone "CHIP signature" has been canonized — normal hematopoiesis is dominated by the clock SBS1/5 family, and the studies treat it with clone-specific spectra. This is an msuiter opportunity.**
- Mosaicism/neurons/muscle: SMaHT Coorens Nature 2025 (40604182); Lodato Science 2018 (29217584); Miller Nature 2022 (35444284); myocardium Choudhury Nat Aging 2022 (36051457); cortical developmental malformations Chung Nat Genet 2023 (36635388); single-neuron indels Luquette Nat Genet 2022 (36163278).
- Pre-cancer lesions: gastric IM Huang 2026 (41532847); breast pre-cancer Chmelova, Nat Commun 2026 (42156386).

**The implied workflow — the "low-mutation-count mode"**: 50–1,000 mutations/sample; the hierarchical pooled estimation over the clone/colony layers; the clock vs excess decomposition; the tumor-normal activity contrast; clonal-lineage-aware fitting (the TrackSig style, 32024834).

## 7. Cell lines, organoids, QC

- Cell lines Giacomelli, Nat Genet 2018 (30224644, CCLE TP53/APOBEC); drug sensitity Levatić 2022 (35614096).
- **The in-vitro exposure screening: Kucab, Cell 2019 (30982602) — the environment-mutagen signature compendium, the foundation of exposure refits**; aflatoxin Huang, Genome Res 2017 (28739859).
- Organoid colibactin van Boxtel 2024 (38471458); XP iPSC 2024 (38805398).
- QC/artifacts: the amber/red grading (35949260); oxoG (23303777); formalin (36068219; 40779107; 36322906); the FFPE large-scale utility (39231944); the fixation substitutes Berrino, Lab Invest 2024 (38345263).

## 8. Single-cell, ultra-low input, ctDNA

- Single-cell: Zhang, Nat Protoc 2024 (37996541); the PTA toolbox Middelkamp, Cell Genom 2023 (37719152); neurons (36163278); Satas bioRxiv 2025 (40060559). The scDNA signatures are still dominated by amplification errors/allele dropout — the papers fit at the cohort/pooled level.
- ctDNA: **Wan, Nat Commun 2022 (35999207, the low-coverage WGS cfDNA whole-genome signatures)**; Hollizeck, Nat Commun 2024 (39543119); Chabon, Nature 2020 (32269342); Nordentoft, Eur Urol 2024 (38811314); Adalsteinsson, Nat Commun 2017 (29109393); **the cfDNA CN signatures vs ICI resistance Front Oncol 2026 (42601918)**.

**The implied workflow**: the ultra-low-count/low-coverage mode: QC-aware counts, sensitivity bounds (how large an N before it is trustworthly), longitudinal activity tracking, cfDNA CN signature support.

## 9. The RNA-seq signatures

- **IMAPR**: Tang, Commun Biol 2024 (38783092, TCGA-grade RNA somatic-mutation discovery); OncoDB 2.0 NAR 2025 (40995640).
- Forerunners: Davila 2021 (34158040, the RNA signature detects POLE); Jessen, BMC Med Genomics 2021 (33648520, tumor-only RNA TMB+signatures).
- **RNA-SBS** (already included since COSMIC **v3.4**, not v3.5) derives from TRACERx: Martínez-Ruiz, Nature 2023 (37046093).
- RNA-based HRD: Brown 2023 (38061006).

**The implied workflow**: RNA mutation calling → artifact-aware RNA fitting (the G>A/C>T skew, RNA editing) (DNA-derived + RNA-specific reference sets) → a DNA-vs-RNA concordance report. **The thousands of RNA-seq-only cohorts are a huge unsatisfied demand.**

## 10. Non-human/cross-species and non-cancer

- Mouse: **Riva, Nat Genet 2020 (32989322, the mouse signature spectrum of the known human carcinogens — the base of the COSMIC mouse set)**; Connor, J Hepatol 2018 (29958939); Xu, Cell Rep 2025 (40638383); Zhang/Smith-Roe, EMM 2026 (42277565); Ohno, Genes Environ 2025 (41131588); Gurevich bioRxiv 2026 (41959104).
- Rat: the ethanol multi-organ (42321443). Yeast: Loeillet, PNAS 2020 (32968016). Dog: Hwang, Gene 2026 (42342053). The reviews: Daino 2025 (41007286).

**The implied workflow — the "preclinical/toxicology mode"**: the non-human genomic contexts (mm10/rn6/canFam), the species reference sets, the exposure-screen scoring (the genotoxicity ranking beyond Ames), the cross-species signature matching.

## 11. The software-ecosystem usage patterns and pain points

**What the application papers actually use**: the SigProfiler suite (MatrixGenerator: Khandekar, BMC Genomics 2023, 37605126; Extractor: Islam 2022, 36388765) dominates the high-profile WGS atlases; deconstructSigs (26899170) dominates the old/clinical WES panels; MutationalPatterns (29695279; update 35168570) dominates the R/Bioc normal-tissue and non-human studies; sigminer/sigflow; MuSiCal (38361034) the newcomer; mmsig — the fitting standard of hematologic tumors (Maura 2019, 31278357 practice guidance: misattribution, focal-hypermutation over-calling, over-fitting); TrackSig (32024834); TensorSignatures Vöhringer, Nat Commun 2021 (34131135); Pollock (35603231); MuSiCa web (29898651); SigFormer bioRxiv 2026 (41648438); Palimpsest (FunGeST).

**Portals/pipelines**: mSigPortal (NCI DCEG; CBIIT/nci-webtools-dceg-mSigPortal); MutSpec Galaxy (27091472); OncoDB 2.0 (40995640); **nf-core/tumourevo (the only nf-core pipeline carrying a signature module; there is no dedicated maintained nf-core signature pipeline)**.

**The pain-point literature (the opportunity list)**: Medo 2024 (39487150); Jiang 2024 (39910776); **the variant-caller dependency bioRxiv 2025 (41427300, the Alexandrov group)**; the conceptual warning Koh, Nat Rev Cancer 2021 (34316057); the field review Steele, J Pathol 2022 (35420163).

1. The refit ambiguity and over-fitting of small cohorts and panels → principled uncertainty (CIs, LRTs, adaptive priors) should be a first-class output.
2. The variant-caller/matrix-generator dependency → versioned, testable SBS/DBS/ID/CN/SV matrix builders.
3. The multi-class support is fragmented → CN/SV need separate toolchains; Everall 2026 demands a unified SV reference.
4. The COSMIC version drift → the reference sets must be versioned, bundled and diffable.
5. The ad-hoc QC-artifact handling → the Excerno/FFPEsig/amber-red logic should be built-in filters.
6. The non-standard genomes (mouse/rat/dog, non-canonical contigs) → a Rust mmap genome reader trivializes any reference genome.
7. Panels/WES/low coverage → the trinucleotide-coverage corrections and sensitivity bounds are comprehensively missing.
8. The reproducible end-to-end pipelines → there is no maintained nf-core module; every atlas paper ships its own glue. A Rust/R hybrid + CLI + R bindings + workflow templates fills exactly that slot.

---

# The Top-10 deliverable workflows (ranked by paper/impact value)

1. **The clinical HRD composite report** — the SBS3/ID6 fit + HRD-LOH/LST/TAI + SV features (the CHORD style) → the ensemble HRD verdict + uncertainty + the BRCA1-vs-BRCA2 tendency + the PARP-i/platinum text. Rationale: the greatest clinical demand, the FDA-assay discordance unresolved (42351273), WES/WGS support.
2. **The clinical WGS/tumor-only signature report (the atlas refit)** — the common-vs-rare refit, amber/red QC, artifact clearing, druggability annotation (38200255; the 35949260 pattern became an NHS-grade standard).
3. **The exposure-attribution and epidemiology module** — bundled exposure reference panels (tobacco/UV/AA/colibactin/platinum/thiopurine/formalin), case-control tests, the geographic/age/lifestyle mapping (38693263; 40267983; 40604281; 37505926).
4. **The five-class joint extraction (SBS+DBS+ID+CN+SV) + versioned reference sets** — the Everall/Steele atlas pattern; no single tool covers the five classes end to end; the SV reference is brand new, paper-grade.
5. **The panel/WES repair-deficiency diagnostics (MSI/MMR, POLE, MUTYH)** — the ID-signature MSI classification, the SBS10/POLE detection + sensitivity bounds (33355208; 35668106; 25878334; 33571361). The FFPE panel is the largest clinical sample pool.
6. **The treatment-history forensics and the longitudinal relapse-pair mode** — the treatment reference set + clonal timing + longitudinal differencing (31594944; 33495476; 31697823; 40371888; 40791422; 32024834). Near-zero competition, high novelty.
7. **The normal-tissue/pre-cancer low-count mode** — hierarchical pooled fitting (50–1,000 mutations), the clock vs excess decomposition, the tumor-normal contrast (40604182; 40108450; 41532847; 35948631; 35581206). The SMaHT/pre-cancer wave is accelerating.
8. **The RNA-seq signature module** — RNA-aware calling + the RNA-SBS reference (COSMIC v3.4+) + the DNA-RNA concordance (38783092; 37046093; 34158040; 33648520).
9. **The ctDNA/low-VAF liquid-biopsy mode** — sensitivity-bound-constrained signature-presence tests, low-coverage WGS support, cfDNA CN signatures (35999207; 39543119; 42601918; 32269342).
10. **The preclinical/toxicology and cross-species mode** — any genome (mouse/rat/dog/yeast), species reference sets, in-vitro exposure screening, cross-species matching (32989322; 30982602; 28739859; 42321443; 42277565).

**The cross-cutting enablers**: the versioned bundled reference sets + diffs; the native bootstrap/CI APIs; the built-in QC-artifact filters; the panel sensitivity bounds; the one-command R/CLI/Nextflow interfaces (what nf-core lacks today).
