# P6 evidence campaign -- REFUSED, gate ledger follows

- **master all-ok (168 cells, gate)**: MEASURED — 168 accepted of 168; 7 rejected rows spoken in the ledger
- **digest-witness provenance (gate)**: PASS — 168 rows checked, 0 rejected
- **master timing attestation**: MEASURED — max wall 9293.22s at sigminer_post_p1_rust__comp_strong_flat__N1000, n=168 rows, 10 shard pass tables
- **P-1 parity sigminer_post_v3_rust (gate)**: FAIL — 18 offending class(es): sigminer_post_v3_rust__comp_flat_triple__N10000 ratio 67.102, sigminer_post_v3_rust__comp_flat_triple__N1000 ratio 63.041, sigminer_post_v3_rust__comp_flat_triple__N100 ratio 55.235, sigminer_post_v3_rust__comp_pole__N1000000 ratio 45.877, sigminer_post_v3_rust__comp_clock_only__N1000 ratio 42.329, sigminer_post_v3_rust__comp_pole__N300000 ratio 41.009, sigminer_post_v3_rust__comp_mmr__N1000 ratio 39.929, sigminer_post_v3_rust__comp_clock_only__N10000 ratio 39.637, sigminer_post_v3_rust__comp_clock_only__N100 ratio 39.599, sigminer_post_v3_rust__main__N10000 ratio 39.010, sigminer_post_v3_rust__comp_pole__N100000 ratio 38.877, sigminer_post_v3_rust__main__N1000 ratio 38.748, sigminer_post_v3_rust__main__N100 ratio 38.605, sigminer_post_v3_rust__comp_mmr__N100 ratio 38.341, sigminer_post_v3_rust__comp_mmr__N10000 ratio 38.005, sigminer_post_v3_rust__comp_strong_flat__N1000 ratio 23.418, sigminer_post_v3_rust__comp_strong_flat__N100 ratio 23.005, sigminer_post_v3_rust__comp_strong_flat__N10000 ratio 22.166
- **P-1 parity sigminer_post_v3 (reported)**: FAIL — 18 offending class(es): sigminer_post_v3__comp_clock_only__N10000 ratio 55.893, sigminer_post_v3__comp_flat_triple__N10000 ratio 52.144, sigminer_post_v3__comp_clock_only__N1000 ratio 49.556, sigminer_post_v3__comp_flat_triple__N1000 ratio 46.973, sigminer_post_v3__comp_flat_triple__N100 ratio 39.430, sigminer_post_v3__comp_mmr__N1000 ratio 37.659, sigminer_post_v3__main__N10000 ratio 35.332, sigminer_post_v3__comp_mmr__N10000 ratio 35.069, sigminer_post_v3__main__N1000 ratio 34.729, sigminer_post_v3__comp_clock_only__N100 ratio 31.142, sigminer_post_v3__main__N100 ratio 29.754, sigminer_post_v3__comp_mmr__N100 ratio 27.315, sigminer_post_v3__comp_pole__N1000000 ratio 21.208, sigminer_post_v3__comp_pole__N300000 ratio 20.850, sigminer_post_v3__comp_pole__N100000 ratio 20.846, sigminer_post_v3__comp_strong_flat__N1000 ratio 20.501, sigminer_post_v3__comp_strong_flat__N10000 ratio 19.724, sigminer_post_v3__comp_strong_flat__N100 ratio 17.423
- **P-2 sigminer_post_v3 vs 2.3.1 baseline (gate)**: PASS — 18 judged classes held within the committed tolerance
- **P-2 sigminer_post_v3_rust vs 2.3.1 baseline (gate)**: PASS — 18 judged classes held within the committed tolerance
- **P-2 sigminer_post_v3_rust vs sigminer_post_v3 (gate)**: PASS — 18 judged classes held within the committed tolerance
- **P-3 attribution N=100 (gate)**: PASS — 6 stages at N=100, worst 1.339
- **P-3 attribution N=1000 (gate)**: PASS — 6 stages at N=1000, worst 1.284
- **P-3 attribution N=10000 (gate)**: PASS — 6 stages at N=10000, worst 1.299
- **yardstick**: MEASURED — ratio 1.23 (rust 0.325407s, r 0.401000s) at the committed fixed count 400, fixture 10bda6beb4f457fa

Machine-written: every figure above is a value handed to the
writer from campaign or calibration bytes; this file carries no
hand-typed numbers.
