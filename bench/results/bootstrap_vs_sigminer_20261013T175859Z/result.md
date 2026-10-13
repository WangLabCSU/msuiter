# bootstrap-vs-sigminer campaign — result

- tier: B
- ratio(A1/A2) = 1.536600758177e+01
- verdict: MEASURED-false 15.37x

## Disclosure
- seed: 20260928 (G0 master; the arms carry it into their own RNG regimes; RNG-stream equality is NOT claimed — data bytes carry identity)
- shape: K=1000 S=1000 n_sig=50
- heavy arms: single authoritative timed shot each (RB-10); repeatability 
  evidence lives in the probe witnesses (warmup + 3 timed, median)
- msuiter catalog construction happens outside the timed regions 
  (harness glue); both arms are timed on their documented entry point
- host: ShixiangWang-WorkSpacedeMacBook-Pro.local  R: R version 4.5.2 (2025-10-31)  hw_profile: host-R campaign | Apple Silicon | 10 cores | hw.ncpu=10 hw.memsize=25769803776 | R 4.5.2
- data seal: {"sha256": "cc094225d599a6765dbc7958a445609459ded0f32f2481f87c5cb9e8762b3263", "campaign_rds": "campaign.rds","host": "ShixiangWang-WorkSpacedeMacBook-Pro.local", "hw_profile": "host-R campaign | Apple Silicon | 10 cores | hw.ncpu=10 hw.memsize=25769803776 | R 4.5.2", "generator": "gen_campaign.R","argv": "-- --out bench/results/bootstrap_vs_sigminer_20261013T175859Z --k 1000 --s 1000 --sig 50 --seed 20260928"}
- co-tenancy census: witnesses/host_census.jsonl (verbatim docker ps)
- secondary A1/A3 (pool-scaling isolation): 14.2209
