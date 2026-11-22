# test-scenario-segments-witness.R -- the CS-14 segments-witness law units
# (pillar 3). The scenario plants hand-authored TSV bytes and adjudicates
# the EXPORTED ms_segments() face: the eight caller grammars with their
# authoritative column signatures, the auto-detection signature split, the
# file/extension/ragged gates, the caller-label law with its documented-
# limited CNVkit branch, the caller-internal legality laws (B-allele
# ceiling, declared-role pair rejection, the four PCAWG mutation_type
# illegalities, the FACETS LOH semantics, the Battenberg block law, the
# Sequenza allele-sum law), the integer-parse laws, the canonical-path
# laws, and the precedence discriminators. The witness bytes under
# bench/scenarios/out/ (cs14_specs.tsv, cs14_laws.tsv, cs14_precedence.tsv,
# cs14_degenerates.tsv, cs14_scalars.tsv) are the committed verdict: a
# drift in a fired clause, an observed error class, a returned shape or
# the precedence order reddens here before print. The plants are synthetic
# TSV text -- no RNG, no network, no COSMIC bytes; the lane NEVER calls the
# benchmark driver, the declined calibration family, or any internal of
# the face (banned words, grepped).
# Framing law: DECISION RECORD only. What the face says on planted truth --
# the accepted shapes, the abort classes, the fired bullets -- is an
# OBSERVED, COMMITTED record, never a fidelity claim beyond what was
# measured. Cross-platform posture (D11): integer, label, class and
# clause bytes are byte-committed; the two OBSERVED-CARRY arms (the
# Battenberg zero-row table, the beyond-int32 coordinate) commit their
# measured shape strings, and float glyphs would ride censuses only (none
# is produced -- the typed columns are integer by law).
# The frozen block and the shared code block below are MINTED mechanically
# from the observed probe ledger (gen-frozen.R / probe-cs14.R); neither is
# ever hand-edited in place.

.rs_out14 <- function(fname) {
  file.path(.ms_root, "bench", "scenarios", "out", fname)
}

# The committed tables are written quote-free; quote = "" keeps every
# double quote inside the clauses literal on read.
.rs_tsv14 <- function(fname) {
  read.csv(.rs_out14(fname), header = TRUE, sep = "\t",
           stringsAsFactors = FALSE, na.strings = "", colClasses = "character",
           quote = "")
}

## <<CS14-FROZEN-BEGIN>>  (minted mechanically from the observed ledger
##    2026-11-23; DO NOT hand-edit: regenerate via gen-frozen.R) ######
.CS14_LAW_ARMS <- c("rej-vecpath", "rej-napath", "rej-emptypath", "rej-missing", "rej-dir", "rej-ext", "rej-emptyfile", "rej-ragged", "rej-dots", "rej-chromcol-absent", "rej-caller-na", "rej-caller-num", "rej-caller-empty", "rej-caller-cnvkit", "rej-caller-bogus", "rej-auto-nosig", "rej-ancn-bcn-gt-tcn", "rej-ascat-pair-declared", "rej-purple-pair-declared", "rej-pcg-loh-zero", "rej-pcg-het-low", "rej-pcg-loss-high", "rej-pcg-bad-type", "rej-fac-lcn-gt-tcn", "rej-bat-block-incomplete", "rej-seq-sum", "rej-cn-negative", "rej-cn-fractional", "rej-cn-na-strict", "rej-start-zero", "rej-end-before-start", "rej-chrom-empty", "rej-sample-empty", "rej-can-zero", "rej-can-missingcol", "rej-can-chromcol", "rej-can-nocaller", "rej-can-auto-caller", "rej-can-fractional", "rej-can-negative", "rej-generic-numeric")
.CS14_LAW_CLS <- c("msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_io", "msuiter_error_io", "msuiter_error_unsupported", "msuiter_error_io", "msuiter_error_parse", "msuiter_error_input", "msuiter_error_io", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_io", "msuiter_error_io", "msuiter_error_segments", "msuiter_error_segments", "msuiter_error_segments", "msuiter_error_segments", "msuiter_error_segments", "msuiter_error_segments", "msuiter_error_segments", "msuiter_error_io", "msuiter_error_io", "msuiter_error_io", "msuiter_error_io", "msuiter_error_io", "msuiter_error_io", "msuiter_error_segments", "msuiter_error_segments", "msuiter_error_segments", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_input", "msuiter_error_segments", "msuiter_error_segments", "msuiter_error_input")
.CS14_LAW_MODE <- c("full", "full", "full", "stable3", "stable3", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full", "full")
.CS14_LAW_CLAUSES <- list()
.CS14_LAW_CLAUSES[["rej-vecpath"]] <- paste0("x must be a single non-empty file path | the ",
            "character method of ms_segments() reads exact",
            "ly one file | received a character vector of ",
            "length 2 | pass the path of one segmentation ",
            "file (optionally .gz)")
.CS14_LAW_CLAUSES[["rej-napath"]] <- paste0("x must be a single non-empty file path | the ",
            "character method of ms_segments() reads exact",
            "ly one file | received a character vector of ",
            "length 1 | pass the path of one segmentation ",
            "file (optionally .gz)")
.CS14_LAW_CLAUSES[["rej-emptypath"]] <- paste0("x must be a single non-empty file path | the ",
            "character method of ms_segments() reads exact",
            "ly one file | received a character vector of ",
            "length 1 | pass the path of one segmentation ",
            "file (optionally .gz)")
.CS14_LAW_CLAUSES[["rej-missing"]] <- paste0("the segmentation file does not exist | the io",
            " layer reads the file eagerly at call time | ",
            "check the path spelling and the working direc",
            "tory")
.CS14_LAW_CLAUSES[["rej-dir"]] <- paste0("the segmentation path is a directory, not a f",
            "ile | the io layer reads regular files only |",
            " pass the path of one segmentation file")
.CS14_LAW_CLAUSES[["rej-ext"]] <- paste0("unrecognized segmentation file extension | ms",
            "_segments() reads tab-separated segmentation ",
            "files: .tsv, .txt (optionally .gz) | badext.b",
            "in | re-export the caller output as a tab-sep",
            "arated file")
.CS14_LAW_CLAUSES[["rej-emptyfile"]] <- paste0("the segmentation file is empty | a tabular in",
            "put needs a header line and at least one reco",
            "rd | empty.tsv | check that the file is the i",
            "ntended input")
.CS14_LAW_CLAUSES[["rej-ragged"]] <- paste0("the segmentation file has ragged data line(s)",
            " | the header declares 6 tab-separated fields",
            "; every data line must match | ragged.tsv, of",
            "fending file line(s): '2' | repair the ragged",
            " data line(s), or re-export the file")
.CS14_LAW_CLAUSES[["rej-dots"]] <- paste0("unknown argument passed to ms_segments() | ms",
            "_segments() has no passthrough arguments | un",
            "expected: 'bogus_arg' | check the argument sp",
            "elling against ?ms_segments")
.CS14_LAW_CLAUSES[["rej-chromcol-absent"]] <- paste0("the requested chromosome column does not exis",
            "t in the file | chrom_col overrides the calle",
            "r's default chromosome column | 'nope_col' no",
            "t found in ASCAT_chrlabel.tsv | use the exact",
            " column name, or omit chrom_col")
.CS14_LAW_CLAUSES[["rej-caller-na"]] <- paste0("caller must be a single non-empty string | ca",
            "ller names the copy-number caller whose colum",
            "ns are mapped | received: 'NA' | use \"auto\" o",
            "r one of the eight supported caller labels")
.CS14_LAW_CLAUSES[["rej-caller-num"]] <- paste0("caller must be a single non-empty string | ca",
            "ller names the copy-number caller whose colum",
            "ns are mapped | received: '7' | use \"auto\" or",
            " one of the eight supported caller labels")
.CS14_LAW_CLAUSES[["rej-caller-empty"]] <- paste0("caller must be a single non-empty string | ca",
            "ller names the copy-number caller whose colum",
            "ns are mapped | received: '' | use \"auto\" or ",
            "one of the eight supported caller labels")
.CS14_LAW_CLAUSES[["rej-caller-cnvkit"]] <- paste0("unsupported copy-number caller | supported ca",
            "llers: ASCAT, ASCAT_NGS, ABSOLUTE, PCAWG, FAC",
            "ETS, BATTENBERG, PURPLE, SEQUENZA | 'CNVkit' ",
            "| CNVkit is documented-limited: SPMG has no C",
            "NVkit branch and .cns/.cnr output is total-CN",
            " (log2), not allele-specific; run an allele-s",
            "pecific caller")
.CS14_LAW_CLAUSES[["rej-caller-bogus"]] <- paste0("unsupported copy-number caller | supported ca",
            "llers: ASCAT, ASCAT_NGS, ABSOLUTE, PCAWG, FAC",
            "ETS, BATTENBERG, PURPLE, SEQUENZA | 'BOGUS' |",
            " check the caller spelling against ?ms_segmen",
            "ts")
.CS14_LAW_CLAUSES[["rej-auto-nosig"]] <- paste0("caller = \"auto\" could not identify the copy-n",
            "umber caller | auto-detection matches the cal",
            "ler's copy-number column signature | no calle",
            "r signature matched the file's columns | pass",
            " caller explicitly: ASCAT, ASCAT_NGS, ABSOLUT",
            "E, PCAWG, FACETS, BATTENBERG, PURPLE, SEQUENZ",
            "A")
.CS14_LAW_CLAUSES[["rej-ancn-bcn-gt-tcn"]] <- paste0("Tumour BCN exceeds Tumour TCN | the B-allele ",
            "copy number cannot exceed the total copy numb",
            "er | ancn_bcn_hi.tsv, offending rows: '1' | r",
            "epair the caller output")
.CS14_LAW_CLAUSES[["rej-ascat-pair-declared"]] <- paste0("minor copy number exceeds major copy number |",
            " the typed pair is ordered minor <= major (Cn",
            "Segment contract, src/rust/catalog/src/cn48.r",
            "s); the callers with declared roles (ASCAT, B",
            "ATTENBERG, FACETS, PURPLE) are rejected inste",
            "ad of reordered | ascat_pair.tsv, source row(",
            "s) '1' | swap the allele columns, or repair t",
            "he caller output")
.CS14_LAW_CLAUSES[["rej-purple-pair-declared"]] <- paste0("minor copy number exceeds major copy number |",
            " the typed pair is ordered minor <= major (Cn",
            "Segment contract, src/rust/catalog/src/cn48.r",
            "s); the callers with declared roles (ASCAT, B",
            "ATTENBERG, FACETS, PURPLE) are rejected inste",
            "ad of reordered | purple_pair.tsv, source row",
            "(s) '1' | swap the allele columns, or repair ",
            "the caller output")
.CS14_LAW_CLAUSES[["rej-pcg-loh-zero"]] <- paste0("LOH-labelled PCAWG row with total copy number",
            " 0 | upstream would tally it as LOH (mutation",
            "_type test :243-252) while the total says hom",
            "del | pcg_loh0.tsv, offending rows: '1' | rep",
            "air the copy_number/mutation_type pair")
.CS14_LAW_CLAUSES[["rej-pcg-het-low"]] <- paste0("het-labelled PCAWG row with total copy number",
            " below 2 | upstream would target the nonexist",
            "ent '1:het' channel (:253-254) | pcg_het1.tsv",
            ", offending rows: '1' | repair the copy_numbe",
            "r/mutation_type pair")
.CS14_LAW_CLAUSES[["rej-pcg-loss-high"]] <- paste0("'loss' PCAWG row with total copy number >= 2 ",
            "| upstream leaves its LOH list unsynchronised",
            " and crashes on the assignment (:255-259, :30",
            "4) | pcg_loss3.tsv, offending rows: '1' | rec",
            "lassify the segment with the proper mutation_",
            "type")
.CS14_LAW_CLAUSES[["rej-pcg-bad-type"]] <- paste0("unsupported PCAWG mutation_type | handled val",
            "ues: copy neutral LOH, amp LOH, hemizygous de",
            "l LOH, loss (total CN 0/1), copy neutral, gai",
            "n (:243-258) | pcg_type.tsv, offending rows: ",
            "'1' | reclassify the segment with a handled m",
            "utation_type")
.CS14_LAW_CLAUSES[["rej-fac-lcn-gt-tcn"]] <- paste0("minor copy number exceeds major copy number |",
            " the typed pair is ordered minor <= major (Cn",
            "Segment contract, src/rust/catalog/src/cn48.r",
            "s); the callers with declared roles (ASCAT, B",
            "ATTENBERG, FACETS, PURPLE) are rejected inste",
            "ad of reordered | facets_lcn_hi.tsv, source r",
            "ow(s) '1' | swap the allele columns, or repai",
            "r the caller output")
.CS14_LAW_CLAUSES[["rej-bat-block-incomplete"]] <- paste0("the Battenberg subclonal block is incomplete ",
            "| the subclonal block needs both nMaj2_A and ",
            "nMin2_A | bat_half.tsv | export both subclona",
            "l columns, or neither")
.CS14_LAW_CLAUSES[["rej-seq-sum"]] <- paste0("Sequenza alleles A + B do not sum to CNt (msu",
            "iter io-layer legality rule; upstream :92-103",
            "/:206-213 does not validate and would count i",
            "nconsistent rows) | the allele copy numbers m",
            "ust reconstruct the total copy number | seq_s",
            "um.tsv, offending rows: '1' | repair the call",
            "er output")
.CS14_LAW_CLAUSES[["rej-cn-negative"]] <- paste0("the column must contain non-negative integers",
            " | copy numbers and segment coordinates are n",
            "on-negative integer states | column 'copy_num",
            "ber' in cn_neg.tsv, offending rows: '1' | wri",
            "te values as plain integers")
.CS14_LAW_CLAUSES[["rej-cn-fractional"]] <- paste0("the column must contain non-negative integers",
            " | copy numbers and segment coordinates are n",
            "on-negative integer states | column 'copy_num",
            "ber' in cn_frac.tsv, offending rows: '1' | wr",
            "ite values as plain integers")
.CS14_LAW_CLAUSES[["rej-cn-na-strict"]] <- paste0("the copy-number column must not contain missi",
            "ng values | missing values have no faithful u",
            "pstream behaviour for this caller (upstream s",
            "ilently classifies NaN copy numbers into the ",
            "9+/het branches) | column 'copy_number' in cn",
            "_na.tsv, offending rows: '1' | impute or drop",
            " the affected rows before reading")
.CS14_LAW_CLAUSES[["rej-start-zero"]] <- paste0("values must be integers >= 1 | canonical segm",
            "ent coordinates are positive 1-based integers",
            " | column 'chromosome_start' in start0.tsv, o",
            "ffending rows: '1' | write coordinates as pos",
            "itive integers (1-based closed intervals)")
.CS14_LAW_CLAUSES[["rej-end-before-start"]] <- paste0("segment end must not precede segment start | ",
            "canonical segments are closed intervals [star",
            "t, end] | endbefore.tsv, source row(s) '1' | ",
            "swap or repair the coordinates")
.CS14_LAW_CLAUSES[["rej-chrom-empty"]] <- paste0("the chromosome column must contain non-empty ",
            "labels | chromosome names are passed through ",
            "verbatim into the typed record | chromempty.t",
            "sv, source row(s) '1' | fill in the chromosom",
            "e label")
.CS14_LAW_CLAUSES[["rej-sample-empty"]] <- paste0("the sample column must contain non-empty labe",
            "ls | sample labels are passed through for per",
            "-sample tallying | sampempty.tsv, source row(",
            "s) '1' | fill in the sample label")
.CS14_LAW_CLAUSES[["rej-can-zero"]] <- paste0("the canonical segment table has no rows | a d",
            "irect-construction input must carry at least ",
            "one segment | the table has 0 rows | check th",
            "e table upstream of ms_segments()")
.CS14_LAW_CLAUSES[["rej-can-missingcol"]] <- paste0("the canonical segment table is missing requir",
            "ed columns | required columns: chrom, start, ",
            "end, minor, major | missing: 'major' | pass c",
            "hrom/start/end/minor/major, or read a caller ",
            "file")
.CS14_LAW_CLAUSES[["rej-can-chromcol"]] <- paste0("the chrom_col mapping applies only when readi",
            "ng a file | a canonical data.frame already na",
            "mes its chromosome column 'chrom' | chrom_col",
            " is set on the direct-construction path | dro",
            "p chrom_col, or pass a file path instead")
.CS14_LAW_CLAUSES[["rej-can-nocaller"]] <- paste0("the caller label is required for direct const",
            "ruction | a canonical table carries no per-ca",
            "ller columns to auto-detect from | received: ",
            "'auto' | record the calling tool, e.g. caller",
            " = \"ASCAT\"")
.CS14_LAW_CLAUSES[["rej-can-auto-caller"]] <- paste0("the caller label is required for direct const",
            "ruction | a canonical table carries no per-ca",
            "ller columns to auto-detect from | received: ",
            "'AUTO' | record the calling tool, e.g. caller",
            " = \"ASCAT\"")
.CS14_LAW_CLAUSES[["rej-can-fractional"]] <- paste0("the canonical column 'start' must contain int",
            "eger values >= 1 | canonical segments carry i",
            "nteger coordinates and copy numbers | offendi",
            "ng rows: '1' | write plain integers, or read ",
            "a caller file for column repair")
.CS14_LAW_CLAUSES[["rej-can-negative"]] <- paste0("the canonical column 'start' must contain int",
            "eger values >= 1 | canonical segments carry i",
            "nteger coordinates and copy numbers | offendi",
            "ng rows: '1' | write plain integers, or read ",
            "a caller file for column repair")
.CS14_LAW_CLAUSES[["rej-generic-numeric"]] <- paste0("x must be a segmentation file path or a canon",
            "ical segment table | ms_segments() dispatches",
            " on character paths and data.frames | receive",
            "d: integer | pass a segmentation file path or",
            " a data.frame with columns chrom/start/end/mi",
            "nor/major")
.CS14_SPEC_ARMS <- c("acc-ASCAT", "acc-ASCAT_NGS", "acc-ABSOLUTE", "acc-PCAWG", "acc-FACETS", "acc-BATTENBERG", "acc-PURPLE", "acc-SEQUENZA", "acc-auto-pcawg", "acc-auto-sequenza", "acc-txt", "acc-gz", "acc-canonical", "acc-facets-loh", "acc-chrom-col", "obs-bat-all-na", "obs-end-out-of-range")
.CS14_SPEC_CLS <- c("data.frame", "data.frame", "data.frame", "data.frame", "data.frame", "data.frame", "data.frame", "data.frame", "data.frame", "data.frame", "data.frame", "character", "data.frame", "data.frame", "data.frame", "data.frame", "data.frame")
.CS14_SPEC_DETAILS <- list()
.CS14_SPEC_DETAILS[["acc-ASCAT"]] <- paste0("nrow=2;cols=sample,chrom,start,end,minor,majo",
            "r;caller=ASCAT;format=segments;nlines=2;nrec=",
            "2;nexp=0;nskip=0;skiprows=0;mm1=1/3")
.CS14_SPEC_DETAILS[["acc-ASCAT_NGS"]] <- paste0("nrow=2;cols=sample,chrom,start,end,minor,majo",
            "r;caller=ASCAT_NGS;format=segments;nlines=2;n",
            "rec=2;nexp=0;nskip=0;skiprows=0;mm1=1/2")
.CS14_SPEC_DETAILS[["acc-ABSOLUTE"]] <- paste0("nrow=2;cols=sample,chrom,start,end,minor,majo",
            "r;caller=ABSOLUTE;format=segments;nlines=2;nr",
            "ec=2;nexp=0;nskip=0;skiprows=0;mm1=1/3")
.CS14_SPEC_DETAILS[["acc-PCAWG"]] <- paste0("nrow=2;cols=sample,chrom,start,end,minor,majo",
            "r;caller=PCAWG;format=segments;nlines=2;nrec=",
            "2;nexp=0;nskip=0;skiprows=0;mm1=1/2")
.CS14_SPEC_DETAILS[["acc-FACETS"]] <- paste0("nrow=2;cols=sample,chrom,start,end,minor,majo",
            "r;caller=FACETS;format=segments;nlines=2;nrec",
            "=2;nexp=0;nskip=0;skiprows=0;mm1=1/2")
.CS14_SPEC_DETAILS[["acc-BATTENBERG"]] <- paste0("nrow=3;cols=sample,chrom,start,end,minor,majo",
            "r;caller=BATTENBERG;format=segments;nlines=2;",
            "nrec=3;nexp=1;nskip=1;skiprows=1;mm1=1/3")
.CS14_SPEC_DETAILS[["acc-PURPLE"]] <- paste0("nrow=2;cols=sample,chrom,start,end,minor,majo",
            "r;caller=PURPLE;format=segments;nlines=2;nrec",
            "=2;nexp=0;nskip=0;skiprows=0;mm1=1/3")
.CS14_SPEC_DETAILS[["acc-SEQUENZA"]] <- paste0("nrow=2;cols=sample,chrom,start,end,minor,majo",
            "r;caller=SEQUENZA;format=segments;nlines=2;nr",
            "ec=2;nexp=0;nskip=0;skiprows=0;mm1=1/3")
.CS14_SPEC_DETAILS[["acc-auto-pcawg"]] <- "PCAWG"
.CS14_SPEC_DETAILS[["acc-auto-sequenza"]] <- "SEQUENZA"
.CS14_SPEC_DETAILS[["acc-txt"]] <- "ASCAT"
.CS14_SPEC_DETAILS[["acc-gz"]] <- "ASCAT;nrow=2"
.CS14_SPEC_DETAILS[["acc-canonical"]] <- "1;synthetic"
.CS14_SPEC_DETAILS[["acc-facets-loh"]] <- "1;minor=0;major=3"
.CS14_SPEC_DETAILS[["acc-chrom-col"]] <- "chrom1=c7c;chrom2=c8c"
.CS14_SPEC_DETAILS[["obs-bat-all-na"]] <- paste0("ACCEPTED-TABLE nrow=0;cols=sample,chrom,start",
            ",end,minor,major;nrec=0;nskip=1;skiprows=1")
.CS14_SPEC_DETAILS[["obs-end-out-of-range"]] <- paste0("ACCEPTED-TABLE nrow=1;end1=9999999999;end1.cl",
            "ass=numeric")
.CS14_PLANT <- list()
.CS14_PLANT[["ASCAT_ok.tsv"]] <- c("sample	chr	startpos	endpos	nMajor	nMinor", "TUM1	chr7	100	9000	3	1", "TUM1	chr8	50	4000	2	2")
.CS14_PLANT[["ASCATNGS_ok.tsv"]] <- c("Chromosome	Start Position	End Position	Tumour TCN	Tumour BCN	sample", "chr7	100	9000	3	1	TUM1", "chr8	50	4000	2	2	TUM1")
.CS14_PLANT[["ABSOLUTE_ok.tsv"]] <- c("Chromosome	Start	End	Modal_HSCN_1	Modal_HSCN_2	sample", "chr7	100	9000	3	1	TUM1", "chr8	50	4000	2	2	TUM1")
.CS14_PLANT[["PCAWG_ok.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9000	3	gain", "chr8	TUM1	50	4000	4	copy neutral LOH")
.CS14_PLANT[["FACETS_ok.tsv"]] <- c("chrom	start	end	tcn.em	lcn.em	sample", "chr7	100	9000	3	1	TUM1", "chr8	50	4000	2	1	TUM2")
.CS14_PLANT[["BATTENBERG_ok.tsv"]] <- c("chr	startpos	endpos	nMaj1_A	nMin1_A	nMaj2_A	nMin2_A	sample", "chr7	100	9000	3	1	2	2	TUM1", "chr8	50	4000	2	2	NA	NA	TUM1")
.CS14_PLANT[["PURPLE_ok.tsv"]] <- c("chromosome	start	end	minorAlleleCopyNumber	majorAlleleCopyNumber	sample", "chr7	100	9000	1	3	TUM1", "chr8	50	4000	2	2	TUM1")
.CS14_PLANT[["SEQUENZA_ok.tsv"]] <- c("chromosome	start.pos	end.pos	CNt	A	B	sample", "chr7	100	9000	4	3	1	TUM1", "chr8	50	4000	4	1	3	TUM1")
.CS14_PLANT[["facets_loh.tsv"]] <- c("chrom	start	end	tcn.em	lcn.em	sample", "chr7	100	9000	3	NA	TUM1")
.CS14_PLANT[["ASCAT_chrlabel.tsv"]] <- c("sample	chr	chrlabel	startpos	endpos	nMajor	nMinor", "TUM1	chr7	c7c	100	9000	3	1", "TUM1	chr8	c8c	50	4000	2	2")
.CS14_PLANT[["badext.bin"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9000	3	gain", "chr8	TUM1	50	4000	4	copy neutral LOH")
.CS14_PLANT[["empty.tsv"]] <- character(0L)
.CS14_PLANT[["ragged.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9000	3	gain	EXTRA")
.CS14_PLANT[["nosig.tsv"]] <- c("chromosome	position	value", "chr7	100	3")
.CS14_PLANT[["ancn_bcn_hi.tsv"]] <- c("Chromosome	Start Position	End Position	Tumour TCN	Tumour BCN	sample", "chr7	100	9000	3	5	TUM1")
.CS14_PLANT[["ascat_pair.tsv"]] <- c("sample	chr	startpos	endpos	nMajor	nMinor", "TUM1	chr7	100	9000	1	9")
.CS14_PLANT[["purple_pair.tsv"]] <- c("chromosome	start	end	minorAlleleCopyNumber	majorAlleleCopyNumber	sample", "chr7	100	9000	9	1	TUM1")
.CS14_PLANT[["pcg_loh0.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9000	0	amp LOH")
.CS14_PLANT[["pcg_het1.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9000	1	copy neutral")
.CS14_PLANT[["pcg_loss3.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9000	3	loss")
.CS14_PLANT[["pcg_type.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9000	3	bogus_state")
.CS14_PLANT[["facets_lcn_hi.tsv"]] <- c("chrom	start	end	tcn.em	lcn.em	sample", "chr7	100	9000	2	3	TUM1")
.CS14_PLANT[["bat_half.tsv"]] <- c("chr	startpos	endpos	nMaj1_A	nMin1_A	nMaj2_A	sample", "chr7	100	9000	3	1	2	TUM1")
.CS14_PLANT[["bat_allna.tsv"]] <- c("chr	startpos	endpos	nMaj1_A	nMin1_A	sample", "chr7	100	9000	NA	NA	TUM1")
.CS14_PLANT[["seq_sum.tsv"]] <- c("chromosome	start.pos	end.pos	CNt	A	B	sample", "chr7	100	9000	5	3	1	TUM1")
.CS14_PLANT[["cn_neg.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9000	-1	gain")
.CS14_PLANT[["cn_frac.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9000	1.5	gain")
.CS14_PLANT[["cn_na.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9000	NA	gain")
.CS14_PLANT[["start0.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	0	9000	3	gain")
.CS14_PLANT[["endbefore.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	50	3	gain")
.CS14_PLANT[["endrange.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7	TUM1	100	9999999999	3	gain")
.CS14_PLANT[["chromempty.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "	TUM1	100	9000	3	gain")
.CS14_PLANT[["sampempty.tsv"]] <- c("chromosome	sample	chromosome_start	chromosome_end	copy_number	mutation_type", "chr7		100	9000	3	gain")
.CS14_PLANT[["ASCAT_ok.txt"]] <- c("sample	chr	startpos	endpos	nMajor	nMinor", "TUM1	chr7	100	9000	3	1", "TUM1	chr8	50	4000	2	2")
.CS14_PREC_ARMS <- c("prec-parse-before-caller", "prec-caller-on-clean", "prec-intparse-before-validate", "prec-blocklaw-before-intparse")
.CS14_PREC_FIRES <- c("msuiter_error_parse", "msuiter_error_input", "msuiter_error_io", "msuiter_error_io")
.CS14_PREC_ANCHOR <- c("the segmentation file has ragged data line(s)", "unsupported copy-number caller", "the column must contain non-negative integers", "the Battenberg subclonal block is incomplete")
.CS14_PREC_ANTI <- c("unsupported copy-number caller", "the segmentation file has ragged data line(s)", "minor copy number exceeds major copy number", "the column must contain non-negative integers")
.CS14_DEGEN <- list(
list(edge = "zero-row file path vs canonical", arm = "obs-bat-all-na", cls = "accept", observed = paste0("ACCEPTED-TABLE nrow=0;cols=sample,chrom,start",
            ",end,minor,major;nrec=0;nskip=1;skiprows=1")),
  list(edge = "zero-row file path vs canonical", arm = "rej-can-zero", cls = "msuiter_error_input", observed = "the canonical segment table has no rows"),
  list(edge = "missing values: LOH caller vs strict caller", arm = "acc-facets-loh", cls = "accept", observed = "1;minor=0;major=3"),
  list(edge = "missing values: LOH caller vs strict caller", arm = "rej-cn-na-strict", cls = "msuiter_error_io", observed = paste0("the copy-number column must not contain missi",
            "ng values")),
  list(edge = paste0("coordinates beyond int32 are carried, not ref",
            "used"), arm = "obs-end-out-of-range", cls = "accept", observed = paste0("ACCEPTED-TABLE nrow=1;end1=9999999999;end1.cl",
            "ass=numeric")),
  list(edge = "auto-detection on a zero-signature plant", arm = "rej-auto-nosig", cls = "msuiter_error_io", observed = paste0("caller = \"auto\" could not identify the copy-n",
            "umber caller"))
)
.CS14_SCAL_KEYS <- c("caller-roster", "declared-callers", "extension-law", "cnvkit-clause", "plant-checksum", "spec-checksum", "rng-before", "rng-after")
.CS14_SCAL_SOURCE <- list(
list(key = "caller-roster", from_arm = "rej-caller-bogus", seg = 2L),
  list(key = "declared-callers", from_arm = "rej-ascat-pair-declared", seg = 2L),
  list(key = "extension-law", from_arm = "rej-ext", seg = 2L),
  list(key = "cnvkit-clause", from_arm = "rej-caller-cnvkit", seg = 4L)
)
## <<CS14-FROZEN-END>> ########################################################
##CS14-SHARED-SPLICE##
##CS14-FROZEN-SPLICE##
## <<CS14-SHARED-BEGIN>>  (single source: injected byte-identically into
##    tests/testthat/test-scenario-segments-witness.R and
##    bench/scenarios/run_segments_witness.R; pure code -- no testthat, no
##    rails, reaches the package ONLY through the exported ms_segments face)
.CS14_BULLET <- "ℹ"

##' -- error surface mirror (cli bullet glyphs are RENDERING, not bytes:
##' the theme prints ℹ, the testthat context prints an ASCII "i"; both
##' strip per segment -- CS-12/13 precedent)
.cs14_describe <- function(e) {
  m <- gsub("\n", " | ", paste(as.character(conditionMessage(e)),
                               collapse = " | "), fixed = TRUE)
  segs <- strsplit(m, " | ", fixed = TRUE)[[1L]]
  segs <- vapply(seq_along(segs), function(i) {
    s <- trimws(segs[i])
    for (b in c(paste0(.CS14_BULLET, " "), "i ")) {
      if (startsWith(s, b)) s <- substring(s, nchar(b) + 1L)
    }
    trimws(s)
  }, character(1L))
  paste0(segs, collapse = " | ")
}
.cs14_try <- function(expr) tryCatch(list(v = expr), error = identity)
.cs14_cls <- function(r) if (inherits(r, "error")) class(r)[1L] else
                         class(r$v)[1L]
.cs14_msg <- function(r) if (inherits(r, "error")) .cs14_describe(r) else ""

##' -- plant channel: the ONLY sanctioned way to lay bytes (binary
##' connection pins LF; zero-line plants are created empty)
.cs14_wl <- function(lines, path) {
  if (length(lines) == 0L) {
    file.create(path)
    return(invisible(path))
  }
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(lines, con)
  invisible(path)
}
.cs14_plants <- function(pd) {
  dir.create(pd, showWarnings = FALSE, recursive = TRUE)
  files <- list()
  for (nm in names(.CS14_PLANT)) files[[nm]] <- .cs14_wl(.CS14_PLANT[[nm]],
                                                          file.path(pd, nm))
  list(dir = pd, files = files)
}
##' -- the caller-shape rendering (integers and labels only: D11 posture by
##' construction -- the typed table's float-free columns are what rides here)
.cs14_shape <- function(r) {
  pv <- attr(r, "provenance")
  paste0("nrow=", nrow(r), ";cols=", paste0(names(r), collapse = ","),
         ";caller=", pv$caller, ";format=", pv$format,
         ";nlines=", pv$parse$n_lines, ";nrec=", pv$parse$n_records,
         ";nexp=", pv$parse$n_expanded, ";nskip=", pv$parse$n_skipped,
         ";skiprows=", nrow(pv$parse$skip_reasons),
         ";mm1=", r$minor[[1L]], "/", r$major[[1L]])
}
##' -- the canonical texts whose dual-kernel checksums ride the scalars
##' witness (byte-stable joins over the minted plants and the spec roster)
.cs14_plant_text <- function() {
  paste0(vapply(names(.CS14_PLANT), function(nm)
    paste0(nm, "=", paste0(.CS14_PLANT[[nm]], collapse = "~")), character(1L)),
    collapse = ";")
}
.cs14_spec_text <- function() paste0(.CS14_SPEC_ARMS, collapse = ";")

##' -- acceptance arms: what the face RETURNS on planted truth
.cs14_specfire <- function(arm, P) {
  f <- P$files
  switch(arm,
    "acc-ASCAT"        = .cs14_try(ms_segments(f$ASCAT_ok.tsv, caller = "ASCAT")),
    "acc-ASCAT_NGS"    = .cs14_try(ms_segments(f$ASCATNGS_ok.tsv, caller = "ASCAT_NGS")),
    "acc-ABSOLUTE"     = .cs14_try(ms_segments(f$ABSOLUTE_ok.tsv, caller = "ABSOLUTE")),
    "acc-PCAWG"        = .cs14_try(ms_segments(f$PCAWG_ok.tsv, caller = "PCAWG")),
    "acc-FACETS"       = .cs14_try(ms_segments(f$FACETS_ok.tsv, caller = "FACETS")),
    "acc-BATTENBERG"   = .cs14_try(ms_segments(f$BATTENBERG_ok.tsv, caller = "BATTENBERG")),
    "acc-PURPLE"       = .cs14_try(ms_segments(f$PURPLE_ok.tsv, caller = "PURPLE")),
    "acc-SEQUENZA"     = .cs14_try(ms_segments(f$SEQUENZA_ok.tsv, caller = "SEQUENZA")),
    "acc-auto-pcawg"   = .cs14_try(ms_segments(f$PCAWG_ok.tsv)),
    "acc-auto-sequenza" = .cs14_try(ms_segments(f$SEQUENZA_ok.tsv)),
    "acc-txt"          = .cs14_try(ms_segments(f$ASCAT_ok.txt, caller = "ASCAT")),
    "acc-gz"           = .cs14_try({
      gp <- file.path(P$dir, "ASCAT_ok.tsv.gz")
      gc <- gzcon(file(gp, open = "wb"), 6L)
      writeLines(.CS14_PLANT[["ASCAT_ok.tsv"]], gc)
      close(gc)
      r <- ms_segments(gp, caller = "ASCAT")
      paste0(attr(r, "provenance")$caller, ";nrow=", nrow(r))
    }),
    "acc-canonical"    = .cs14_try(ms_segments(data.frame(chrom = "chr7",
      start = 100L, end = 9000L, minor = 1L, major = 3L),
      caller = "synthetic")),
    "acc-facets-loh"   = .cs14_try(ms_segments(f$facets_loh.tsv,
      caller = "FACETS")),
    "acc-chrom-col"    = .cs14_try(ms_segments(f$ASCAT_chrlabel.tsv,
      caller = "ASCAT", chrom_col = "chrlabel")),
    "obs-bat-all-na"   = .cs14_try(ms_segments(f$bat_allna.tsv,
      caller = "BATTENBERG")),
    "obs-end-out-of-range" = .cs14_try(ms_segments(f$endrange.tsv,
      caller = "PCAWG")),
    NULL)
}
##' -- the committed detail rendering per acceptance arm (recomputed live;
##' rails and U4 compare against the frozen bytes)
.cs14_detail <- function(arm, P) {
  f <- P$files
  v <- switch(arm,
    "acc-ASCAT" = , "acc-ASCAT_NGS" = , "acc-ABSOLUTE" = , "acc-PCAWG" = ,
    "acc-FACETS" = , "acc-BATTENBERG" = , "acc-PURPLE" = , "acc-SEQUENZA" =
      .cs14_shape(.cs14_specfire(arm, P)$v),
    "acc-auto-pcawg"   = attr(.cs14_specfire(arm, P)$v, "provenance")$caller,
    "acc-auto-sequenza" = attr(.cs14_specfire(arm, P)$v, "provenance")$caller,
    "acc-txt"          = attr(.cs14_specfire(arm, P)$v, "provenance")$caller,
    "acc-gz"           = .cs14_specfire(arm, P)$v,
    "acc-canonical"    = paste0(nrow(.cs14_specfire(arm, P)$v), ";",
      attr(.cs14_specfire(arm, P)$v, "provenance")$caller),
    "acc-facets-loh"   = {
      r <- .cs14_specfire(arm, P)$v
      paste0(nrow(r), ";minor=", r$minor[[1L]], ";major=", r$major[[1L]])
    },
    "acc-chrom-col"    = {
      r <- .cs14_specfire(arm, P)$v
      paste0("chrom1=", r$chrom[[1L]], ";chrom2=", r$chrom[[2L]])
    },
    "obs-bat-all-na"   = {
      r <- .cs14_specfire(arm, P)$v
      pv <- attr(r, "provenance")
      paste0("ACCEPTED-TABLE nrow=", nrow(r), ";cols=",
             paste0(names(r), collapse = ","), ";nrec=", pv$parse$n_records,
             ";nskip=", pv$parse$n_skipped, ";skiprows=",
             nrow(pv$parse$skip_reasons))
    },
    "obs-end-out-of-range" = {
      r <- .cs14_specfire(arm, P)$v
      paste0("ACCEPTED-TABLE nrow=", nrow(r),
             ";end1=", format(r$end[[1L]], scientific = FALSE, digits = 15L),
             ";end1.class=", class(r$end[[1L]]))
    },
    NA_character_)
  if (is.na(v)) stop(".cs14_detail: unknown acceptance arm")
  paste0(v)
}

##' -- reject arms: what the face SAYS on planted violations
.cs14_fire <- function(arm, P) {
  f <- P$files
  switch(arm,
    "rej-vecpath"   = .cs14_try(ms_segments(c(f$PCAWG_ok.tsv, f$PCAWG_ok.tsv))),
    "rej-napath"    = .cs14_try(ms_segments(NA_character_)),
    "rej-emptypath" = .cs14_try(ms_segments("")),
    "rej-missing"   = .cs14_try(ms_segments(file.path(P$dir, "nope_missing.tsv"))),
    "rej-dir"       = .cs14_try(ms_segments(P$dir)),
    "rej-ext"       = .cs14_try(ms_segments(f$badext.bin, caller = "PCAWG")),
    "rej-emptyfile" = .cs14_try(ms_segments(f$empty.tsv, caller = "PCAWG")),
    "rej-ragged"    = .cs14_try(ms_segments(f$ragged.tsv, caller = "PCAWG")),
    "rej-dots"      = .cs14_try(ms_segments(f$PCAWG_ok.tsv, caller = "PCAWG",
      bogus_arg = 1L)),
    "rej-chromcol-absent" = .cs14_try(ms_segments(f$ASCAT_chrlabel.tsv,
      caller = "ASCAT", chrom_col = "nope_col")),
    "rej-caller-na"    = .cs14_try(ms_segments(f$PCAWG_ok.tsv, caller = NA)),
    "rej-caller-num"   = .cs14_try(ms_segments(f$PCAWG_ok.tsv, caller = 7L)),
    "rej-caller-empty" = .cs14_try(ms_segments(f$PCAWG_ok.tsv, caller = "")),
    "rej-caller-cnvkit" = .cs14_try(ms_segments(f$PCAWG_ok.tsv,
      caller = "CNVkit")),
    "rej-caller-bogus" = .cs14_try(ms_segments(f$PCAWG_ok.tsv,
      caller = "BOGUS")),
    "rej-auto-nosig"   = .cs14_try(ms_segments(f$nosig.tsv, caller = "auto")),
    "rej-ancn-bcn-gt-tcn" = .cs14_try(ms_segments(f$ancn_bcn_hi.tsv,
      caller = "ASCAT_NGS")),
    "rej-ascat-pair-declared" = .cs14_try(ms_segments(f$ascat_pair.tsv,
      caller = "ASCAT")),
    "rej-purple-pair-declared" = .cs14_try(ms_segments(f$purple_pair.tsv,
      caller = "PURPLE")),
    "rej-pcg-loh-zero"  = .cs14_try(ms_segments(f$pcg_loh0.tsv,
      caller = "PCAWG")),
    "rej-pcg-het-low"   = .cs14_try(ms_segments(f$pcg_het1.tsv,
      caller = "PCAWG")),
    "rej-pcg-loss-high" = .cs14_try(ms_segments(f$pcg_loss3.tsv,
      caller = "PCAWG")),
    "rej-pcg-bad-type"  = .cs14_try(ms_segments(f$pcg_type.tsv,
      caller = "PCAWG")),
    "rej-fac-lcn-gt-tcn" = .cs14_try(ms_segments(f$facets_lcn_hi.tsv,
      caller = "FACETS")),
    "rej-bat-block-incomplete" = .cs14_try(ms_segments(f$bat_half.tsv,
      caller = "BATTENBERG")),
    "rej-seq-sum" = .cs14_try(ms_segments(f$seq_sum.tsv, caller = "SEQUENZA")),
    "rej-cn-negative"  = .cs14_try(ms_segments(f$cn_neg.tsv, caller = "PCAWG")),
    "rej-cn-fractional" = .cs14_try(ms_segments(f$cn_frac.tsv, caller = "PCAWG")),
    "rej-cn-na-strict" = .cs14_try(ms_segments(f$cn_na.tsv, caller = "PCAWG")),
    "rej-start-zero"   = .cs14_try(ms_segments(f$start0.tsv, caller = "PCAWG")),
    "rej-end-before-start" = .cs14_try(ms_segments(f$endbefore.tsv,
      caller = "PCAWG")),
    "rej-chrom-empty"  = .cs14_try(ms_segments(f$chromempty.tsv,
      caller = "PCAWG")),
    "rej-sample-empty" = .cs14_try(ms_segments(f$sampempty.tsv,
      caller = "PCAWG")),
    "rej-can-zero" = .cs14_try(ms_segments(data.frame(chrom = character(0L),
      start = integer(0L), end = integer(0L), minor = integer(0L),
      major = integer(0L)), caller = "synthetic")),
    "rej-can-missingcol" = .cs14_try(ms_segments(data.frame(chrom = "chr7",
      start = 100L, end = 9000L, minor = 1L), caller = "synthetic")),
    "rej-can-chromcol" = .cs14_try(ms_segments(data.frame(chrom = "chr7",
      start = 100L, end = 9000L, minor = 1L, major = 3L),
      caller = "synthetic", chrom_col = "c")),
    "rej-can-nocaller" = .cs14_try(ms_segments(data.frame(chrom = "chr7",
      start = 100L, end = 9000L, minor = 1L, major = 3L))),
    "rej-can-auto-caller" = .cs14_try(ms_segments(data.frame(chrom = "chr7",
      start = 100L, end = 9000L, minor = 1L, major = 3L),
      caller = "AUTO")),
    "rej-can-fractional" = .cs14_try(ms_segments(data.frame(chrom = "chr7",
      start = 100.5, end = 9000L, minor = 1L, major = 3L),
      caller = "synthetic")),
    "rej-can-negative" = .cs14_try(ms_segments(data.frame(chrom = "chr7",
      start = -1L, end = 9000L, minor = 1L, major = 3L),
      caller = "synthetic")),
    "rej-generic-numeric" = .cs14_try(ms_segments(42L)),
    NULL)
}

##' -- precedence discriminators: which law speaks when two could
.cs14_precfire <- function(arm, P) {
  f <- P$files
  switch(arm,
    "prec-parse-before-caller" = .cs14_try(ms_segments(f$ragged.tsv,
      caller = "BOGUS")),
    "prec-caller-on-clean" = .cs14_try(ms_segments(f$PCAWG_ok.tsv,
      caller = "BOGUS")),
    "prec-intparse-before-validate" = .cs14_try(ms_segments(f$cn_neg.tsv,
      caller = "PCAWG")),
    "prec-blocklaw-before-intparse" = .cs14_try(ms_segments(f$bat_half.tsv,
      caller = "BATTENBERG")),
    NULL)
}
## <<CS14-SHARED-END>>  (do not hand-edit in place: edit the source and
##    re-splice both hosts)
##    re-splice both hosts)
##    re-splice both hosts)
##    re-splice both hosts)

.cs14_lawrows <- function() {
  data.frame(arm = .CS14_LAW_ARMS, face = rep("ms_segments", length(.CS14_LAW_ARMS)),
    cls = .CS14_LAW_CLS, mode = .CS14_LAW_MODE,
    clause = vapply(.CS14_LAW_ARMS, function(a) .CS14_LAW_CLAUSES[[a]],
                    character(1L)),
    stringsAsFactors = FALSE, check.names = FALSE)
}
.cs14_specrows <- function() {
  data.frame(arm = .CS14_SPEC_ARMS, face = rep("ms_segments", length(.CS14_SPEC_ARMS)),
    cls = .CS14_SPEC_CLS,
    detail = vapply(.CS14_SPEC_ARMS, function(a) .CS14_SPEC_DETAILS[[a]],
                    character(1L)),
    stringsAsFactors = FALSE, check.names = FALSE)
}
.cs14_precrows <- function() {
  data.frame(arm = .CS14_PREC_ARMS, fires_cls = .CS14_PREC_FIRES,
    fires_anchor = .CS14_PREC_ANCHOR, anti_anchor = .CS14_PREC_ANTI,
    stringsAsFactors = FALSE, check.names = FALSE)
}
.cs14_degenrows <- function() {
  row <- function(k) vapply(.CS14_DEGEN, function(d) d[[k]], character(1L))
  data.frame(edge = row("edge"), arm = row("arm"), cls = row("cls"),
    observed = row("observed"), stringsAsFactors = FALSE, check.names = FALSE)
}
.cs14_scalar_kv <- function(sc, k) sc$value[match(k, sc$key)]

# ===========================================================================
# U1 -- runner rails: the witness exists and speaks the attestation idiom,
# reaching the package ONLY through the exported face.
# ===========================================================================
test_that("runner speaks the exported-face rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  runner <- file.path(.ms_root, "bench", "scenarios", "run_segments_witness.R")
  expect_true(file.exists(runner))
  src <- paste(readLines(runner, warn = FALSE), collapse = "\n")
  for (need in c("--file=", "[attest]", "OVERALL PASS", "ms_segments(", "cs14_")) {
    expect_true(grepl(need, src, fixed = TRUE), info = need)
  }
  for (ban in c("msuiter:::", ".ms_segment", "msuiter_segment_",
                "msuiter_segments_", "msuiter_validate_", "expect_",
                "ms_calibration_grid", "ms_fit_bootstrap", "ms_calibration_sanity",
                "run_benchmark", "set.seed", "sample(", "download.file", "http")) {
    expect_false(grepl(ban, src, fixed = TRUE), info = ban)
  }
})

# ===========================================================================
# U2 -- witness existence and shape: five committed TSVs, non-zero, with
# hard row-count gates and an all-character no-NA census (no vacuous green).
# ===========================================================================
test_that("the five witnesses exist with hard shape gates", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  for (f in c("cs14_specs.tsv", "cs14_laws.tsv", "cs14_precedence.tsv",
              "cs14_degenerates.tsv", "cs14_scalars.tsv")) {
    expect_true(file.exists(.rs_out14(f)))
    expect_gt(file.size(.rs_out14(f)), 0)
  }
  sp <- .rs_tsv14("cs14_specs.tsv"); lw <- .rs_tsv14("cs14_laws.tsv")
  pr <- .rs_tsv14("cs14_precedence.tsv"); dg <- .rs_tsv14("cs14_degenerates.tsv")
  sc <- .rs_tsv14("cs14_scalars.tsv")
  expect_identical(nrow(sp), 17L)
  expect_identical(nrow(lw), 41L)
  expect_identical(nrow(pr), 4L)
  expect_identical(nrow(dg), 6L)
  expect_true("key" %in% names(sc) && "value" %in% names(sc))
  expect_true(all(sc$key %in% .CS14_SCAL_KEYS))
  expect_identical(nrow(sc), length(.CS14_SCAL_KEYS))
  for (df in list(sp, lw, pr, dg, sc)) {
    expect_true(all(vapply(df, is.character, logical(1L))))
    expect_false(any(vapply(df, function(cc) any(is.na(cc)), logical(1L))))
  }
})

# ===========================================================================
# U3 -- the specs witness mirrors the frozen acceptance table byte for byte.
# ===========================================================================
test_that("committed specs mirror the frozen table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  sp <- .rs_tsv14("cs14_specs.tsv"); fr <- .cs14_specrows()
  expect_identical(sp$arm, fr$arm)
  expect_identical(sp$face, fr$face)
  expect_identical(sp$cls, fr$cls)
  expect_identical(sp$detail, fr$detail)
})

# ===========================================================================
# U4 -- live replay of the acceptance arms: the shipped face still RETURNS
# exactly what the witness committed (class tokens + shape renderings).
# ===========================================================================
test_that("acceptance arms replay live through the face", {
  P <- .cs14_plants(file.path(tempdir(TRUE), "cs14-law-plants"))
  fr <- .cs14_specrows()
  for (i in seq_len(nrow(fr))) {
    arm <- fr$arm[i]
    r <- .cs14_specfire(arm, P)
    expect_false(inherits(r, "error"), info = arm)
    expect_identical(.cs14_cls(r), fr$cls[i], info = arm)
    expect_identical(.cs14_detail(arm, P), fr$detail[i], info = arm)
  }
})

# ===========================================================================
# U5 -- the laws witness mirrors the frozen law table: 41 arms, classes,
# adjudication modes, verbatim clauses.
# ===========================================================================
test_that("committed laws mirror the frozen law table", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  lw <- .rs_tsv14("cs14_laws.tsv"); fr <- .cs14_lawrows()
  expect_identical(lw$arm, fr$arm)
  expect_identical(lw$face, fr$face)
  expect_identical(lw$cls, fr$cls)
  expect_identical(lw$mode, fr$mode)
  expect_identical(lw$clause, fr$clause)
})

# ===========================================================================
# U6 -- live replay of the reject arms: each fires its committed class, and
# per mode the clause matches (full = verbatim; stable3 = every frozen
# bullet rides the live message; the machine-volatile temp path is
# deliberately NOT welded into any witness).
# ===========================================================================
test_that("reject arms replay live with their committed verdicts", {
  P <- .cs14_plants(file.path(tempdir(TRUE), "cs14-law-plants"))
  fr <- .cs14_lawrows()
  for (i in seq_len(nrow(fr))) {
    arm <- fr$arm[i]
    r <- .cs14_fire(arm, P)
    expect_true(inherits(r, "error"), info = arm)
    expect_identical(.cs14_cls(r), fr$cls[i], info = arm)
    msg <- .cs14_msg(r)
    if (identical(fr$mode[i], "full")) {
      expect_identical(msg, fr$clause[i], info = arm)
    } else {
      for (bl in strsplit(fr$clause[i], " | ", fixed = TRUE)[[1L]]) {
        expect_true(grepl(bl, msg, fixed = TRUE), info = paste0(arm, " :: ", bl))
      }
    }
  }
})

# ===========================================================================
# U7 -- precedence discriminators: the RIGHT law speaks when two could.
# ===========================================================================
test_that("precedence discriminators speak the right law", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  P <- .cs14_plants(file.path(tempdir(TRUE), "cs14-law-plants"))
  pr <- .cs14_precrows()
  cw <- .rs_tsv14("cs14_precedence.tsv")
  expect_identical(cw$arm, pr$arm)
  expect_identical(cw$fires_cls, pr$fires_cls)
  expect_identical(cw$fires_anchor, pr$fires_anchor)
  expect_identical(cw$anti_anchor, pr$anti_anchor)
  for (i in seq_len(nrow(pr))) {
    r <- .cs14_precfire(pr$arm[i], P)
    expect_true(inherits(r, "error"), info = pr$arm[i])
    expect_identical(.cs14_cls(r), pr$fires_cls[i], info = pr$arm[i])
    msg <- .cs14_msg(r)
    expect_true(grepl(pr$fires_anchor[i], msg, fixed = TRUE), info = pr$arm[i])
    expect_false(grepl(pr$anti_anchor[i], msg, fixed = TRUE), info = pr$arm[i])
  }
})

# ===========================================================================
# U8 -- degenerate boundaries: the asymmetry pairs the face draws on its own
# (zero-row ledger vs canonical refusal; LOH-caller NA vs strict-caller NA;
# carried beyond-int32 coordinate; zero-signature auto-detection).
# ===========================================================================
test_that("degenerate boundaries hold their committed sides", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  P <- .cs14_plants(file.path(tempdir(TRUE), "cs14-law-plants"))
  dg <- .rs_tsv14("cs14_degenerates.tsv"); fr <- .cs14_degenrows()
  expect_identical(dg$edge, fr$edge)
  expect_identical(dg$arm, fr$arm)
  expect_identical(dg$cls, fr$cls)
  expect_identical(dg$observed, fr$observed)
  for (i in seq_len(nrow(fr))) {
    arm <- fr$arm[i]
    if (identical(fr$cls[i], "accept")) {
      r <- .cs14_specfire(arm, P)
      expect_false(inherits(r, "error"), info = arm)
      expect_identical(.cs14_detail(arm, P), fr$observed[i], info = arm)
    } else {
      r <- .cs14_fire(arm, P)
      expect_true(inherits(r, "error"), info = arm)
      expect_true(grepl(fr$observed[i], .cs14_msg(r), fixed = TRUE), info = arm)
    }
  }
})

# ===========================================================================
# U9 -- plant checksum: every plant byte re-hashes identically under BOTH
# governed SHA-256 kernels, and the scalars witness carries that checksum.
# ===========================================================================
test_that("plant bytes re-hash under both governed kernels", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  bytes <- charToRaw(.cs14_plant_text())
  hA <- .ms_fit_sha256(bytes)
  hB <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  expect_identical(hA, hB)
  expect_match(hA, "^[0-9a-f]{64}$")
  sc <- .rs_tsv14("cs14_scalars.tsv")
  expect_identical(.cs14_scalar_kv(sc, "plant-checksum"), hA)
  sbytes <- charToRaw(.cs14_spec_text())
  expect_identical(.cs14_scalar_kv(sc, "spec-checksum"),
                   .ms_fit_sha256(sbytes))
})

# ===========================================================================
# U10 -- scalars: the bytes the face speaks verbatim (cross-checked LIVE
# through its own clauses) and the silent RNG rails.
# ===========================================================================
test_that("scalars speak face bytes and RNG rails", {
  if (is.na(.ms_root)) skip("repository checkout not locatable (R CMD check context)")
  P <- .cs14_plants(file.path(tempdir(TRUE), "cs14-law-plants"))
  sc <- .rs_tsv14("cs14_scalars.tsv")
  for (s in .CS14_SCAL_SOURCE) {
    msg <- .cs14_msg(.cs14_fire(s$from_arm, P))
    seg <- strsplit(msg, " | ", fixed = TRUE)[[1L]][s$seg]
    froz <- strsplit(.CS14_LAW_CLAUSES[[s$from_arm]], " | ", fixed = TRUE)[[1L]][s$seg]
    expect_identical(.cs14_scalar_kv(sc, s$key), seg, info = s$key)
    expect_identical(seg, froz, info = s$key)
  }
  expect_identical(.cs14_scalar_kv(sc, "rng-before"), "FALSE")
  expect_identical(.cs14_scalar_kv(sc, "rng-after"), "FALSE")
})
