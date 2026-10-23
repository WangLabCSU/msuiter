# ID83 channel palette — authoritative color→class mapping (freezing notes)

Status: DETERMINED. The 16-entry `colors` array is bound to the 16 ID83
context classes by machine-readable class tokens, not by guesswork:
`plotID` derives each channel's class key from its canonical colon-form name
(first three colon fields) and matches it against the 16-token list
`xlables_set` (L8540–L8557); the matched index selects `colors[i]` for the
bar face. The `make_pickle_file` ID83 template legend independently reproduces
the same 16-band identity via header/group texts inside the colored bands.

## Provenance

- Pinned source: `/tmp/spp-hit.py`, 411857 bytes, md5
  `76f970ef1e13684c85548ebbb91ffd9f` (re-verified this session), 11387
  lines. Stated upstream: SigProfilerSuite/SigProfilerPlotting @ master
  `9be822faafc9b9933c75b78f0d59f2bfa35d657b`, path
  `sigProfilerPlotting/sigProfilerPlotting.py` (upstream id from the task
  brief; local byte identity verified here).
- SBS96 precedent parity check passed: `plotSBS` colors list L2895–L2902
  re-verified this session; its first entry
  `[3 / 256, 189 / 256, 239 / 256]` equals the house-frozen
  `C>A = #03BDEF` in `R/viz-palette.R`.

## The array (authoritative copy #1: the template)

`make_pickle_file` branch `elif context == "ID83":` starts L1173, ends with
`return _finish_plot_template(...)` L1692–L1694. The array, verbatim,
L1182–L1199. Provenance line range for the freeze header: **L1182–L1199**.

```python
1182        colors = [
1183            [253 / 256, 190 / 256, 111 / 256],
1184            [255 / 256, 128 / 256, 2 / 256],
1185            [176 / 256, 221 / 256, 139 / 256],
1186            [54 / 256, 161 / 256, 46 / 256],
1187            [253 / 256, 202 / 256, 181 / 256],
1188            [252 / 256, 138 / 256, 106 / 256],
1189            [241 / 256, 68 / 256, 50 / 256],
1190            [188 / 256, 25 / 256, 26 / 256],
1191            [208 / 256, 225 / 256, 242 / 256],
1192            [148 / 256, 196 / 256, 223 / 256],
1193            [74 / 256, 152 / 256, 201 / 256],
1194            [23 / 256, 100 / 256, 171 / 256],
1195            [226 / 256, 226 / 256, 239 / 256],
1196            [182 / 256, 182 / 256, 216 / 256],
1197            [134 / 256, 131 / 256, 189 / 256],
1198            [98 / 256, 64 / 256, 155 / 256],
1199        ]
```

## Mapping table

Class token = the verbatim `xlables_set` entry (plotID L8540–L8557) at the
same index as the array entry. Human legend identity = template group title +
column header (both quoted verbatim below).

| colors[i] | RGB (num/256) | class token | token line | template band geometry (draw lines) | header literal (line) @ x | template group title (line) |
|---|---|---|---|---|---|---|
| 0 | 253,190,111 | 1DelC | 8541 | loop band i=0, x=0.0475 w=0.0595, fc L1212/L1222 (block 1206–1227) | "C" (1317) @ 0.072 (1315) | "1bp Deletion" (1480) @ 0.08 |
| 1 | 255,128,2 | 1DelT | 8542 | band x=0.1140 | "T" (1326) @ 0.1385 (1324) | "1bp Deletion" (1480) |
| 2 | 176,221,139 | 1InsC | 8543 | band x=0.1805 | "C" (1336) @ 0.205 (1334) | "1bp Insertion" (1490) @ 0.21 |
| 3 | 54,161,46 | 1InsT | 8544 | band x=0.2470 | "T" (1345) @ 0.2715 (1343) | "1bp Insertion" (1490) |
| 4 | 253,202,181 | 2DelR | 8545 | band x=0.3135 | "2" (1355) @ 0.338 (1353) | ">1bp Deletion at Repeats\n      (Deletion Length)" (1500) @ 0.375 |
| 5 | 252,138,106 | 3DelR | 8546 | band x=0.3800 | "3" (1365) @ 0.4045 (1363) | (same 1500) |
| 6 | 241,68,50 | 4DelR | 8547 | band x=0.4465 | "4" (1375) @ 0.471 (1373) | (same 1500) |
| 7 | 188,25,26 | 5DelR | 8548 | band x=0.5130 | "5+" (1385) @ 0.5375 (1383) | (same 1500) |
| 8 | 208,225,242 | 2InsR | 8549 | band x=0.5795 | "2" (1395) @ 0.604 (1393) | ">1bp Insertion at Repeats\n       (Insertion Length)" (1510) @ 0.64 |
| 9 | 148,196,223 | 3InsR | 8550 | band x=0.6460 | "3" (1405) @ 0.6705 (1403) | (same 1510) |
| 10 | 74,152,201 | 4InsR | 8551 | band x=0.7125 | "4" (1415) @ 0.737 (1413) | (same 1510) |
| 11 | 23,100,171 | 5InsR | 8552 | band x=0.7790 | "5+" (1425) @ 0.8035 (1423) | (same 1510) |
| 12 | 226,226,239 | 2DelM | 8553 | rect 1229–1238, fc L1234, `(x-0.001, y_top)` w `0.006` (x=0.8455 post-loop) → [0.8445,0.8505] | "2" (1435) @ 0.844 (1433) | " Microhomology\n(Deletion Length)" (1520) @ 0.85 |
| 13 | 182,182,216 | 3DelM | 8554 | rect 1250–1259 fc L1255, x=0.8565 w=0.0155 (L1249 `x += 0.011`) → [0.8565,0.8720] | "3" (1445) @ 0.861 (1443) | (same 1520) |
| 14 | 134,131,189 | 4DelM | 8555 | rect 1271–1280 fc L1276, x=0.8785 w=0.027 (L1270 `x += 0.022`) → [0.8785,0.9055] | "4" (1455) @ 0.888 (1453) | (same 1520) |
| 15 | 98,64,155 | 5DelM | 8556 | rect 1292–1301 fc L1297, x=0.912 w=0.049 (L1291 `x += 0.0335`) → [0.912,0.961] | "5+" (1465) @ 0.93 (1463) | (same 1520) |

The strip loop (L1206–L1227) draws for each `i` in `range(0, 12)` a top band
`(x, y_top=0.827)` (block L1207–L1216, `facecolor=colors[i]` L1212) and a
bottom band `(x, y_bottom=0.114)` (L1217–L1226, fc L1222), width `0.0595`
(L1210), advancing `x += 0.0665` (L1227) from `x = 0.0475` (L1201). So band
i spans `[0.0475 + 0.0665·i, +0.0595]` (inter-band gap 0.007). The four MH
bands (colors[12]…[15]) use the same top+bottom pairing (L1229–L1311).

## Source 1: bar faces via plotID class-token matching (authoritative)

`plotID` def L8475; ID83/94 gate L8501–L8506 (`plot_type == "83"` among
others); template load L8512–L8514 (`make_pickle_file(context="ID83", ...)`).
The decisive block, verbatim (L8517–L8534 array, then):

```python
8535            ctx = data.index
8536            xlabels = [
8537                i.split(":")[0] + i.split(":")[1] + i.split(":")[2]
8538                for i in ctx.to_list()
8539            ]
8540            xlables_set = [
8541                "1DelC", "1DelT", "1InsC", "1InsT",
8545                "2DelR", "3DelR", "4DelR", "5DelR",
8549                "2InsR", "3InsR", "4InsR", "5InsR",
8553                "2DelM", "3DelM", "4DelM", "5DelM",
8557            ]
8558            colors_idx = copy.deepcopy(xlabels)
8559            for ii in range(0, len(xlables_set)):
8560                colors_idx = [ii if x == xlables_set[ii] else x for x in colors_idx]
8561
8562            colors_flat_list = [colors[i] for i in colors_idx]
```

(Each `xlables_set` entry occupies its own source line L8541–L8556; the
grouping above compresses four-per-row for readability.) Bars:
`plt.bar(..., color=colors_flat_list, ...)` L8575–L8582 (percentage; fc
L8579) and L8586–L8593 (counts; fc L8590).

Canonical order: `data = process_input(matrix_path, plot_type)` (L8507)
reindexes rows to the upstream reference (`order_input_context` →
`input_data.reindex(ref_format)` L310; `get_context_reference` L216–L228;
`type_dict` `"83"/"id"/"id83" → "ID83.txt"` L71–L73, `SPP_REFERENCE` L47).
The 83 canonical names are colon-form; joining fields 0–2 yields exactly the
16 tokens — this is checkable against this repo's staged corpus:
`data-raw/reference/refdb_stage/COSMIC_v3.6_ID_GRCh37.txt` (83 data rows;
field0+field1+field2 tallies to exactly the 16 tokens with counts
`1DelC:6, 1DelT:6, 1InsC:6, 1InsT:6, 2DelR:6, 3DelR:6, 4DelR:6, 5DelR:6,
2InsR:6, 3InsR:6, 4InsR:6, 5InsR:6, 2DelM:1, 3DelM:2, 4DelM:3, 5DelM:5` —
verified this session by tally; total 72+11 = 83).

## Source 2: template legend geometry (independent corroboration)

Header containment (computed this session):

```
i= 0 hdr=C   band=[0.0475,0.1070] text_x=0.0720 inside
i= 1 hdr=T   band=[0.1140,0.1735] text_x=0.1385 inside
i= 2 hdr=C   band=[0.1805,0.2400] text_x=0.2050 inside
i= 3 hdr=T   band=[0.2470,0.3065] text_x=0.2715 inside
i= 4 hdr=2   band=[0.3135,0.3730] text_x=0.3380 inside
i= 5 hdr=3   band=[0.3800,0.4395] text_x=0.4045 inside
i= 6 hdr=4   band=[0.4465,0.5060] text_x=0.4710 inside
i= 7 hdr=5+ band=[0.5130,0.5725] text_x=0.5375 inside
i= 8 hdr=2   band=[0.5795,0.6390] text_x=0.6040 inside
i= 9 hdr=3   band=[0.6460,0.7055] text_x=0.6705 inside
i=10 hdr=4   band=[0.7125,0.7720] text_x=0.7370 inside
i=11 hdr=5+ band=[0.7790,0.8385] text_x=0.8035 inside
i=12 hdr=2   band=[0.8445,0.8505] text_x=0.8440 edge (see below)
i=13 hdr=3   band=[0.8565,0.8720] text_x=0.8610 inside
i=14 hdr=4   band=[0.8785,0.9055] text_x=0.8880 inside
i=15 hdr=5+ band=[0.9120,0.9610] text_x=0.9300 inside
```

Honest note on i=12: the `"2"` glyph at x=0.844 starts 0.0005 **left** of
the band's left edge (0.8445), i.e. in the inter-band gap (band 11 ends
0.8385). It is left-anchored 40pt text covering the 0.006-wide band
(rightward); no other band covers it and the header sequence
(2,3,4,5+ at ascending x) is forced. The class binding does not rest on
this 0.0005 — it rests on plotID's token matching (Source 1), where
`colors[12] ↔ "2DelM"` is a list-position fact.

Per-band sub-column digit strings under the bands (bottom row, drawn
L1580–L1661) match the corpus counts: cols 0–1 `"1  2  3  4  5  6+"`
(L1585), cols 2–3 `"0  1  2  3  4  5+"` (L1596, the `i == 2 or i == 3`
branch L1581), cols 4–7 `"1  2  3  4  5  6+"`, cols 8–11 `"0  1  2  3
4  5+"` (L1610), MH cols: `"1"` (L1622), `"1  2"` (L1633), `"1  2  3"`
(L1644), `"1  2  3  4  5+"` (L1655) → 6×12 + 1+2+3+5 = 83 bars, matching
`panel1.set_xlim([0, 83])` L1664. Bottom section titles (verbatim lines):
`"Homopolymer Length"` L1531 (x 0.058) and L1541 (x 0.19);
`"Number of Repeat Units"` L1551 (x 0.39) and L1561 (x 0.65);
`"Microhomology Length"` L1571 (x 0.85).

Both sources agree class-for-class, so the mapping is deterministic; the
class names as the branch defines them are the Source-1 tokens plus these
human titles.

## Duplicate copies of the array; which is authoritative for bar faces

The 16-entry array occurs 3× (verified byte-identical modulo indentation;
normalized md5 of the 16 entry lines each:
`a0d23cbd0170e24ce3a6d2d9935920df`):

| Copy | Lines | Role |
|---|---|---|
| A | **L1182–L1199** (`make_pickle_file`, ID83 branch) | colors the top+bottom legend strips only (L1206–L1311); template draws **no bars** (no `plt.bar` in L1173–L1694) |
| B | **L8517–L8534** (`plotID`, main path) | **AUTHORITATIVE for actual bar faces** (L8558–L8562 → `color=colors_flat_list` L8579/L8590) |
| C | **L9690–L9707** (`plotID`, strand-bias subpath) | colors that figure's own strip legends (loop fc `colors[i]` L9780/L9790; `colors[12]` L9802/L9812; `colors[13]` L9823/L9833; `colors[14]` L9844/L9854; `colors[15]` L9865/L9875); its bars are strand literals `[1 / 256, 70 / 256, 102 / 256]` / `[228 / 256, 41 / 256, 38 / 256]` (e.g. L9720/L9730, L9745/L9755), i.e. strand-colored, not class-colored |

## Cross-check: ID83 canonical order in this repo

`tools/channel-reference/` has no ID83 file (only DBS78/SBS96/SBS384/
SBS1536 — confirmed this session). The repo's ID83 canonical content lives
in `data-raw/reference/refdb_stage/COSMIC_v3.6_ID_GRCh37.txt` (83 colon-form
rows; refdb build side: `R/refdb.R` L6, L19, L214, L239 — ID83 is declared
`build_independent`; and `R/ffi-probes.R` L341 notes the ID94-only channel
`N:Ins:M:x` is absent upstream from ID83, consistent with our corpus having
no `NInsM` token). The 83-row tally above equals `xlables_set` exactly.

## Honest-limitations statement

- Class binding is code-level deterministic (token equality L8560 + sorted
  canonical reindex L310), not geometric inference; geometry only corroborates.
- The only geometric nit is the i=12 header 0.0005 offset, documented above;
  it does not affect the binding.
- Upstream commit id/path carried from the task brief; local pinned md5
  re-verified.
