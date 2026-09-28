#!/usr/bin/env sh
# Dependency-direction guard (docs/ARCHITECTURE.md §2): ffi (workspace root)
# → catalog → engine, never back; extendr-api stays in the FFI shell only.
#
# cargo-deny has no per-edge bans (crate X must not depend on crate Y), so the
# direction contract is asserted here; U-M0-07 CI runs this on every push.
set -eu

cd "$(dirname "$0")/../src/rust"
fail() { echo "check-dep-direction: FAIL: $1" >&2; exit 1; }

for m in engine/Cargo.toml catalog/Cargo.toml; do
  # anchored to dependency-declaration lines so prose comments don't trip it
  grep -Eq '^[[:space:]]*extendr' "$m" && fail "$m declares an extendr dependency (FFI budget leak)"
  grep -Eq '^[[:space:]]*msuiter[[:space:]]*=' "$m" && fail "$m depends on the FFI shell crate"
  # renamed-dependency bypass: foo = { package = "msuiter" } (or msuiter-catalog)
  grep -Eq '^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*\{[^}]*"msuiter(-catalog)?"' "$m" \
    && fail "$m has an aliased dependency on the FFI shell or catalog"
done

# the only inter-member edge is catalog → engine (plain or aliased form)
grep -Eq '^[[:space:]]*msuiter-catalog[[:space:]]*=' engine/Cargo.toml \
  && fail "engine depends on catalog (edge direction violated)"
grep -Eq '^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*\{[^}]*"msuiter-catalog"' engine/Cargo.toml \
  && fail "engine has an aliased dependency on catalog"

echo "check-dep-direction: OK (ffi→catalog→engine holds; no extendr in engine/catalog)"
