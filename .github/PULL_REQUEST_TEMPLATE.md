<!-- 提交前：逐项勾选；任何一项不适用须在描述中说明原因。 -->

## 变更说明

<!-- 做了什么、为什么（关联 issue / ROADMAP 工作单元号，如 U-M1s-03）。 -->

## 检查项

- [ ] **FFI-surface 变更声明**：本 PR 是否触碰 `msffi_*` / `ms_*_rust` 导出面？
  - **否**。
  - **是** → 已按 [docs/ffi-surface.md](../docs/ffi-surface.md) 冻结协议同步更新 §「导出清单」与 §「导出明细表」（含 `since` 与 `状态`）；漂移守卫 `tests/testthat/test-ffi-surface-drift.R` 保持绿；并在下方声明变更内容（新增/删除/改签名/改错误协议）。`ms_*_rust` kernel 导出一经发布冻结：语义变更 = 新导出名 + 旧名 `lifecycle::deprecate_warn`。
- [ ] **fixture / golden 刷新**：未更新任何金标准夹具；或已更新且在 devlog（`docs/devlog/`）写明上游理由（上游版本/commit/协议变更或修正依据）——链接：<!-- devlog 路径 -->。RNG golden 重生成须换 `LAYOUT_ID`。
- [ ] **MSRV 钉版保持**：`matrixmultiply = 0.3.9`、`rayon = 1.10.x` 未随 `cargo update` 漂移；`Cargo.lock` 仍为 version 3（docs/adr/0002 §4.4）。
- [ ] **依赖纪律**：未新增依赖；或已新增且有 ADR + docs/adr/0002 §2 vendor 基线追加 + `tools/vendor.sh --check` 绿；rand 族仍为零。
- [ ] **docs-sync 绿**：`Rscript tools/docs-sync.R` 通过（ARCH/ROADMAP 的 `ms_*` API ↔ CAPABILITY-MATRIX L-H 表无 drift）。
- [ ] **测试先行**：新行为有测试（先红后绿）；错误路径断言 condition 而非崩溃。

## 本地验收电池

<!-- CONTRIBUTING.md §2 全清单；粘贴关键输出摘要。 -->

- [ ] Rust：`cargo test` / `cargo clippy -- -D warnings` / `cargo deny check` / `tools/check-dep-direction.sh` / `tools/vendor.sh --check` / `tools/rng-kat.py` 全绿
- [ ] R：`devtools::test()` 全绿；`R CMD check --no-manual` 不劣化（0 error / 0 warning）
- [ ] `Rscript tools/docs-sync.R` 绿
