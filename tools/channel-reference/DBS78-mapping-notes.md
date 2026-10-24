# DBS78 channel palette — authoritative color→class mapping (freezing notes)

Status: DETERMINED. Every `colors[i]` entry is associated with a reference
dinucleotide by two independent, mutually confirming sources:

1. Legend geometry in `make_pickle_file` (context `"DBS78"`): each colored
   Rectangle is covered by exactly one legend header (`AC>NN` … `TT>NN`),
   and the Rectangle widths reproduce the per-group channel counts of
   `tools/channel-reference/DBS78.txt` exactly.
2. Bar-face coloring in `plotDBS`: `colors` is indexed via
   `sklearn.preprocessing.LabelEncoder` over the left (reference) dinucleotide
   of the canonically sorted channel index, i.e. by the sorted unique
   reference classes `[AC, AT, CC, CG, CT, GC, TA, TC, TG, TT]`.

## Provenance

- Pinned source: `/tmp/spp-hit.py`, 411857 bytes, md5
  `76f970ef1e13684c85548ebbb91ffd9f` (re-verified at the start of this
  session), 11387 lines. Stated upstream: SigProfilerSuite/SigProfilerPlotting
  @ master `9be822faafc9b9933c75b78f0d59f2bfa35d657b`, path
  `sigProfilerPlotting/sigProfilerPlotting.py` (upstream commit/path taken
  from the task brief; this session verified the local file's bytes).
- Precedent parity: the frozen SBS96 palette is the `plotSBS` list at
  L2895–L2902 (re-verified this session; 6 entries, first entry
  `[3 / 256, 189 / 256, 239 / 256]` = house `C>A = #03BDEF`, matching
  `R/viz-palette.R` L1–L8 header and L29–L36).

## The array (authoritative copy #1)

`make_pickle_file` branch `elif context == "DBS78":` starts L903 and ends
L1172 (the `return _finish_plot_template(...)` at L1170–L1172). The array,
verbatim, L915–L926:

```python
915        colors = [
916            [3 / 256, 189 / 256, 239 / 256],
917            [3 / 256, 102 / 256, 204 / 256],
918            [162 / 256, 207 / 256, 99 / 256],
919            [1 / 256, 102 / 256, 1 / 256],
920            [255 / 256, 153 / 256, 153 / 256],
921            [228 / 256, 41 / 256, 38 / 256],
922            [255 / 256, 178 / 256, 102 / 256],
923            [255 / 256, 128 / 256, 1 / 256],
924            [204 / 256, 153 / 256, 255 / 256],
925            [76 / 256, 1 / 256, 153 / 256],
926        ]
```

Provenance line range for the freeze header: **L915–L926**.

## Mapping table (class = reference dinucleotide = left side of `XY>ZW`)

| colors[i] | RGB (num/256) | class | array line | Rectangle block (facecolor line) | header text block (literal line) |
|---|---|---|---|---|---|
| 0 | 3,189,239 | AC | 916 | 933–942 (fc 938), rect `(0.043, y3)`, `0.101` (935–936) | 1035–1043 (x 1036, `"AC>NN"` 1038) |
| 1 | 3,102,204 | AT | 917 | 943–952 (fc 948), `(0.151, y3)`, `0.067` (945–946) | 1044–1052 (x 1045, `"AT>NN"` 1047) |
| 2 | 162,207,99 | CC | 918 | 953–962 (fc 958), `(0.225, y3)`, `0.102` (955–956) | 1053–1061 (x 1054, `"CC>NN"` 1056) |
| 3 | 1,102,1 | CG | 919 | 963–972 (fc 968), `(0.334, y3)`, `0.067` (965–966) | 1062–1070 (x 1063, `"CG>NN"` 1065) |
| 4 | 255,153,153 | CT | 920 | 973–982 (fc 978), `(0.408, y3)`, `0.102` (975–976) | 1071–1079 (x 1072, `"CT>NN"` 1074) |
| 5 | 228,41,38 | GC | 921 | 983–992 (fc 988), `(0.517, y3)`, `0.067` (985–986) | 1080–1088 (x 1081, `"GC>NN"` 1083) |
| 6 | 255,178,102 | TA | 922 | 993–1002 (fc 998), `(0.591, y3)`, `0.067` (995–996) | 1089–1097 (x 1090, `"TA>NN"` 1092) |
| 7 | 255,128,1 | TC | 923 | 1003–1012 (fc 1008), `(0.665, y3)`, `0.102` (1005–1006) | 1098–1106 (x 1099, `"TC>NN"` 1101) |
| 8 | 204,153,255 | TG | 924 | 1013–1022 (fc 1018), `(0.774, y3)`, `0.102` (1015–1016) | 1107–1115 (x 1108, `"TG>NN"` 1110) |
| 9 | 76,1,153 | TT | 925 | 1023–1032 (fc 1028), `(0.883, y3)`, `0.102` (1025–1026) | 1116–1124 (x 1117, `"TT>NN"` 1119) |

All Rectangles and texts share `y3 = 0.87` (L929) / `yText = y3 + 0.06`
(L1034) and `transform=plt.gcf().transFigure` — header sits directly above
its band; association is by x containment.

## Source 1: legend geometry arithmetic

Rectangle spans `[x, x+w]` vs header x (all transFigure), and per-group
channel counts `n` tallied from `tools/channel-reference/DBS78.txt`
(`AC×9, AT×6, CC×9, CG×6, CT×9, GC×6, TA×6, TC×9, TG×9, TT×9`; verified this
session: 78 rows, lexicographic order, 10 distinct left dinucleotides):

```
i=0 AC  rect=[0.043,0.144] w=0.101 n=9  w/n=0.01122  header_x=0.070  inside=True
i=1 AT  rect=[0.151,0.218] w=0.067 n=6  w/n=0.01117  header_x=0.163  inside=True
i=2 CC  rect=[0.225,0.327] w=0.102 n=9  w/n=0.01133  header_x=0.255  inside=True
i=3 CG  rect=[0.334,0.401] w=0.067 n=6  w/n=0.01117  header_x=0.345  inside=True
i=4 CT  rect=[0.408,0.510] w=0.102 n=9  w/n=0.01133  header_x=0.435  inside=True
i=5 GC  rect=[0.517,0.584] w=0.067 n=6  w/n=0.01117  header_x=0.527  inside=True
i=6 TA  rect=[0.591,0.658] w=0.067 n=6  w/n=0.01117  header_x=0.600  inside=True
i=7 TC  rect=[0.665,0.767] w=0.102 n=9  w/n=0.01133  header_x=0.690  inside=True
i=8 TG  rect=[0.774,0.876] w=0.102 n=9  w/n=0.01133  header_x=0.800  inside=True
i=9 TT  rect=[0.883,0.985] w=0.102 n=9  w/n=0.01133  header_x=0.915  inside=True
```

Every header x falls strictly inside the span of the Rectangle of the same
index; inter-band gaps are a uniform `0.007`; per-channel width is a common
`≈0.0112`. The width pattern `9,6,9,6,9,6,6,9,9,9` (0.101/0.102 ↔ 9 channels,
0.067 ↔ 6 channels) matches ONLY the group sequence
`AC,AT,CC,CG,CT,GC,TA,TC,TG,TT` — any permutation would have to preserve the
6-vs-9 width classes AND the ascending header placement; the headers are
literally named in that order (L1038…L1119). The x-axis context:
`panel1.set_xlim([0, 78])` L1134 with `labs = np.arange(0.44, 78.44, 1)` L1133
(78 bars).

## Source 2: plotDBS bar faces (LabelEncoder on the reference dinucleotide)

`plotDBS` def L10457; DBS78 gate `if plot_type == "78" or ... "DBS78":` L10483.
Bar-face machinery, verbatim (selected lines):

```python
10484        data = process_input(matrix_path, plot_type)
10579            data = data.sort_index()
10580            ctx = data.index
10581            xlabels = [dn.split(">")[1] for dn in ctx]          # tick labels = ALT side
10582            colors = [ ... ]                                     # identical to L915-926
10593            ]
10594            mainlist = [dn.split(">")[0] for dn in ctx]          # classes = REFERENCE side
10595            le = LabelEncoder()
10596            colors_idxs = le.fit_transform(mainlist)
10597            colors_flat_list = [colors[i] for i in colors_idxs]
```

Bars: `plt.bar(..., color=colors_flat_list, ...)` at L10625 (percentage) and
L10636 (counts). `LabelEncoder` imported L35 (`from sklearn.preprocessing
import LabelEncoder`); sklearn semantics: `fit_transform` maps to integers
in the **sorted unique** order of the labels. Sorted unique of `mainlist` =
`[AC, AT, CC, CG, CT, GC, TA, TC, TG, TT]` (verified equal to the
first-appearance order of `DBS78.txt` this session). Therefore
`colors[0]` faces the AC bars, …, `colors[9]` the TT bars.

Canonical order guarantee: `process_input` (L231) validates and reindexes to
the upstream reference file — `order_input_context` →
`reindexed_data = input_data.reindex(ref_format)` (L310), `ref_format` from
`get_context_reference` (L216–L228) reading `SPP_REFERENCE + SPP_TYPE` (L47,
L225) with `type_dict` `"78"/"dbs"/"dbs78"/"dinuc" → "DBS78.txt"` (L67–L70).
`plotDBS` then renames any reverse-complement rows (L10567–L10578, membership
tested against the 78-name `dinucs` literal L10486–L10565) and re-sorts
lexicographically (L10579); lexicographic order of the 78 canonical channels
equals `DBS78.txt` byte order (verified: `sorted(canon) == canon`).

## Cross-check vs tools/channel-reference/DBS78.txt (sanity #5)

Distinct reference dinucleotides in the file, in order of first appearance:
`AC, AT, CC, CG, CT, GC, TA, TC, TG, TT` — exactly the 10 classes in the
TSV's `class` column, same order. PASS.

## Duplicate copies of the array; which is authoritative for bar faces

The 10-entry array occurs 3× (verified byte-identical modulo indentation;
normalized md5 of the 10 entry lines each: `35ad59d500ef1959965fdf96c2c70ac2`):

| Copy | Lines | Role |
|---|---|---|
| A | **L915–L926** (`make_pickle_file`, DBS78 branch) | colors the legend Rectangles only (L933–L1032); the template draws **no bars** (no `plt.bar` anywhere in L903–L1172) |
| B | **L10582–L10593** (`plotDBS`, main path) | **AUTHORITATIVE for actual bar faces** (via L10594–L10597 → `color=colors_flat_list` L10625/L10636) |
| C | **L11009–L11020** (`plotDBS`, strand-bias subpath) | colors that figure's strip legends only (L11116–L11155 using `colors[0],[2],[4],[7]`; L11203–L11250 same subset); its bars are strand literals `[1 / 256, 70 / 256, 102 / 256]` / `[228 / 256, 41 / 256, 38 / 256]` (e.g. L11032/L11042) |

A and B agree with each other and with Source 2 arithmetic; they are the
freeze basis. Copy C is NOT authoritative — see the anomaly note below.
Related but distinct arrays (NOT this palette): the SBS96 `plotSBS` list
L2895–L2902 (house-frozen separately), and SBS branches at L532, L712 etc.

## Documented anomaly (does not affect the freeze): strand-bias mini-legend

The DBS78 strand-bias subpath draws a 4-band strip legend,
`colors[0],[2],[4],[7]` at `(0.075/0.302/0.532/0.765, y3=0.87)`, width `0.218`
(L11116–L11155), headed by texts `"CC>NN"` (x 0.13, L11158–L11166), `"CT>NN"`
(x 0.37, L11167–L11175), `"TC>NN"` (L11176–L11184), `"TT>NN"` (L11185–L11193).
Geometric pairing there would say `colors[0]→CC, colors[2]→CT, colors[4]→TC,
colors[7]→TT`, which contradicts BOTH consistent sources (which give those
colors to AC, CC, TA, TC and would instead pair CC/CT/TC/TT with indices
2,4,7,9). The mini-legend is internally inconsistent with every other use of
these colors and cannot override the two deterministic sources (legend
geometry of the main figure; LabelEncoder arithmetic on the canonical
index). Judgment: upstream off-by-N index bug in the strand-bias mini-legend;
excluded from the freeze. Extra evidence that would formally close it: an
upstream-generated DBS78 strand-bias PDF whose band colors are sampled, or an
upstream fix — neither is needed for the bar-face freeze.

## Honest-limitations statement

- The class identity is NOT established by pixel inference: every step above
  is code-level (named literals, sorted-unique encoder semantics, and exact
  coordinate containment computed above). No mapping remains
  under-determined.
- The upstream git commit id / path are carried from the task brief; the
  local pinned copy's byte identity (md5 76f970ef…) was re-verified here.
