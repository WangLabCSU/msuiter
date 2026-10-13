# Catalog currency (P5)

The catalog-currency instrument keeps msuiter's pinned COSMIC catalog
snapshot **provably current** against the official COSMIC release line. It
answers one operational question mechanically -- *is the snapshot we ship
still the snapshot upstream publishes?* -- and reports drift per governed
source document rather than ever passing silently.

It is the phase-P5 deliverable of the sigminer v3 parity plan
(`docs/research/09-sigminer-v3-parity-plan.md`, section 5), built in the
governance shape of the refdb chain (`R/refdb.R`, `data-raw/build_refdb.R`).

## What is governed

Two committed records, each with a distinct job:

| Record | Path | Owns |
| --- | --- | --- |
| refdb manifest | `inst/reference/refdb/refdb_manifest.rds` | the shipped BSD-2 mirror *bytes*, re-verified fail-closed on load |
| currency sidecar | `inst/catalog-currency/catalog_registry.rds` | the *official* release records: canonical page URLs, SHA-256 digests of the measured source documents, version labels, structural (shape) facts |

The sidecar never duplicates the refdb digests -- it cross-references them and
re-checks the agreement live (`ms_refdb_manifest()`) so the two can never
silently disagree.

**D3 law.** Only digests, URLs, version labels and structural shape counts
are ever committed -- never COSMIC numeric content (matrix values, exposure
or mutation counts). Test fixtures are self-evidently synthetic.

## Verdict model

```
pinned    <- committed sidecar + live refdb manifest   (what we assert)
latest    <- last derived cache record                  (what was measured)
available <- full measured release-label list           (what exists)
```

Verdict precedence (law, tested):
`inconsistent > corrupt > no-cache > drift > behind > ok`.

A separate `version_state` axis carries `current | behind | ahead | unknown`.

## Commands

```sh
# read-only verdict over a derived cache (never fetches)
Rscript tools/catalog-currency.R verify    [--cache=DIR] [--registry=PATH] [--verbose]

# (re-)derive the cache from the official documents, or offline from a capture
Rscript tools/catalog-currency.R update     [--source=PATH] [--cache=DIR] [--offline]
Rscript tools/catalog-currency.R registry   [--registry=PATH]
```

Exit codes (the CI contract): `0` = verdict ok, `1` = a non-ok currency
verdict, `2` = usage or load error.

The cache directory resolves as: `--cache=` -> option
`msuiter.catalog_currency.cache_dir` -> env
`MSUITER_CATALOG_CURRENCY_CACHE_DIR` -> the user cache directory. A missing
cache is the actionable `no-cache` verdict with a repair hint, not an error.

## Re-pinning upstream

The committed sidecar is never rewritten by the updater (that would defeat
its purpose). To move the pin deliberately:

```sh
Rscript data-raw/build_catalog_registry.R                 # official fetch, or
Rscript data-raw/build_catalog_registry.R --source=CAPTURE # offline re-measure
```

The builder measures every digest from fetched bytes (never re-typed),
is deterministic, and self-checks the emitted sidecar through the package's
own fail-closed registry gate. A pin *ahead* of measured truth is a hard
stop -- re-pinning is a human decision, not a build artifact.

## Offline / D3 safety

The updater's injected-source mode (`--source=` a downloads-page capture or a
split `reference_data.json` + `availability_data.json` directory) never opens a
socket. The verification leg needs no JSON parser at all -- it compares byte
digests. The test suite runs entirely on the synthetic fixture and never
touches the network.
