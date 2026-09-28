# 贡献指南（CONTRIBUTING）

> 依据：docs/ARCHITECTURE.md §2/§3.4/§3.5/§9（依赖预算、引擎扩展契约、错误与 lifecycle、TDD/CI）、docs/ffi-surface.md（冻结协议）、docs/adr/0002-vendor-budget.md（vendor 预算与 MSRV 钉版纪律）、docs/ROADMAP.md M0 治理文件条目。
> 任何 PR 提交前，本文的「本地验收电池」必须全绿；PR 模板（.github/PULL_REQUEST_TEMPLATE.md）检查项须逐项勾选。

## 1. 开发环境

| 组件 | 要求 | 说明 |
|---|---|---|
| R | **≥ 4.3** | DESCRIPTION `Depends` 地板（D8） |
| Rust | rustup 管理，**MSRV 1.71** | DESCRIPTION `SystemRequirements: cargo, rustc (>= 1.71)`；验证须过 `cargo +1.71.0 build/test`（ADR 0002 §4） |
| R 工具链 | rextendr（流程）、devtools、testthat ≥ 3（edition 3） | rextendr 硬约定：FFI crate manifest 位于 `src/rust/Cargo.toml`（root-package + members 形态，U-M0-01 实测定案） |
| cargo-deny | `cargo install cargo-deny` | ban 规则 / license / advisory / sources 四节 |
| Python3 | 纯 stdlib | 仅 `tools/rng-kat.py` 需要 |

日常开发流程（rextendr）：`devtools::load_all()` 即会编译 Rust workspace 并生成 `R/extendr-wrappers.R`；wrapper 文件由 rextendr 生成、不手改；`src/rust/` 下的 vendor 产物（`vendor/`、`vendor.tar.xz`）不入 git（ADR 0002 §3.3）。

已知本机坑（ADR 0002 §4.4）：`~/.Renviron` 注入的 conda PATH 会遮蔽前置工具链——本机验证 MSRV 时用 `R_ENVIRON_USER=/tmp/empty-renviron` + 1.71 bin 前置 PATH。

## 2. 本地验收电池（提交前全绿）

Rust 侧（`cd src/rust`）：

```sh
cargo test --workspace                                  # 单元/property/golden 测试
cargo clippy --workspace --all-targets -- -D warnings   # lint 门（devlog M0-01 口径）
cargo deny check                                        # 四节全绿（快门：cargo deny check bans）
sh ../../tools/check-dep-direction.sh                   # 依赖方向守卫 ffi→catalog→engine
sh ../../tools/vendor.sh --check                        # vendor 字节数基线漂移检查（±0.1% xz 容差带）
python3 ../../tools/rng-kat.py                          # 自研 PCG64 布局 v1 独立 KAT
```

R 侧（仓库根）：

```sh
Rscript -e 'devtools::test()'          # testthat edition 3 全套（含 ffi-surface 漂移守卫）
R CMD build .                          # 产物 *.tar.gz
R CMD check <tar.gz> --no-manual       # 不劣化：0 error / 0 warning 基线
Rscript tools/docs-sync.R              # ARCH/ROADMAP ms_* API ↔ CAPABILITY-MATRIX L-H 表同步
```

CI（U-M0-07）在 3 OS × {release, oldrel, R-4.3(Linux), devel} 矩阵上跑同一电池外加 rcmdcheck --as-cran、cargo audit、valgrind/ASAN scheduled job；本地电池是其前置。

## 3. 第三方引擎接入清单（ARCHITECTURE §3.4 扩展契约）

第三方包通过**自己包的 `.onLoad()`** 调用 `msuiter::register_ms_engine()` 注册引擎（registry 行是数据，注册本身不需要 `S7::methods_register()`；仅当第三方为 msuiter 泛型定义自己的方法时才调用它）。接入必须逐项满足：

1. **九个字段齐全**：`name`（小写 snake_case，registry 键，重复注册报错）、`mode`（`"extract"` 或 `"fit"`）、`engine_class`（派生自抽象 `MsEngine` 的 S7 类，string sugar 经 `engine_class()` 解析）、`fit_fn`（实现函数，被 `fit_engine()` 以 `fit_fn(engine, ...)` 调用）、`packages`（`required_pkgs()` 报告的 R 依赖，可空）、`tags`（自由标签，可空）、`engine_version`（必填单字符串：引擎实现版本）、`contract_version`（必填单字符串：所针对的 msuiter 注册表/扩展契约版本）、`certified`（必填三态，见下）。
2. **certified 三态语义与信任边界**：`"certified"` = 通过 msuiter maintainer 兼容性评审（A17）；`"self-reported"` = 引擎作者自报；`"unknown"` = 未声明。非 certified 引擎在 `match_ms_engine()` 解析时每会话一次性 warning（class `msuiter_warning_uncertified_engine`）。文档必须声明信任边界：**注册引擎代码将以你的权限执行**。
3. **fit_engine / required_pkgs 语义**：`fit_engine()` 分发到注册的 `fit_fn`；`required_pkgs()` 在引擎运行前报告 R 包依赖（供 `ms_sitrep()` / 安装提示）。
4. **契约测试要求**：注册校验（字段类型/名字语法/派生关系/重复键）由 msuiter 侧 `tests/testthat/test-engines-registry.R` 契约套件覆盖；第三方包必须自带：注册往返测试（`.onLoad()` 后 `ms_engines()` 可见、`match_ms_engine()` 可解析）、自身引擎行为测试、以及 non-certified warning 幂等性测试。
5. **文档义务**：第三方文档声明 `engine_version` / `contract_version` / `certified` 与信任边界；msuiter 侧 `vignettes/extending.Rmd` + 配套 harness（M2 交付）是扩展作者的规范读物。maintainer 对 certified 引擎跑月度反向依赖兼容矩阵 job。
6. **D9 红线**：外部工具（SigProfiler*、MuSiCal、mmsig…）永不进 `ms_*` API——只作 bench 对照（bench/adapters 容器），不得经注册表包装进用户接口。

## 4. extendr-api 升级检查单（deny.toml [advisories] 注释钩子）

每次升级 `extendr-api`（任何 minor/patch）：

1. 读一遍 `src/rust/deny.toml` 头部与 `[advisories]` 注释（升级复查钩子即此流程）；
2. 全量 `cargo deny check`（四节，不只 `bans` 快门）；
3. 再评估 **paste 1.0.15 / RUSTSEC-2024-0421**（unmaintained，经 extendr-api 0.9 传入）：`unmaintained = "workspace"` 只扫自家 crate 故不 fail 构建，但升级可能带入新传递依赖或解除该暴露——逐条重读并更新 deny.toml 注释结论；
4. 按 **ADR 0002 §2 增量纪律**在 ADR 表格追加一行（日期/单元/新增内容/三口径字节增量/新基线），并同步更新 `tools/vendor.sh --check` 的内置基线常量；
5. MSRV 重证：`cargo +1.71.0 build/test --workspace` 过（lock 钉版不得动，见 §6）；`Cargo.lock` 保持 version 3。

## 5. fixture / golden 刷新协议（团队铁律）

- **任何金标准夹具更新**（语义逐位 golden、数值协议 golden、RNG golden、通道参考文件）**必须在对应 devlog（`docs/devlog/YYYY-MM-DD-<单元>.md`）写明上游理由**——上游版本/commit/协议变更或实现修正依据。无理由的 golden 变更一律拒绝。先例：U-M0-06 RNG post-step 修正（canonical pcg64 输出位）随 devlog 记录了重生成缘由与 numpy/pcg-cpp 证据。
- **溯源格式**照 `tools/channel-reference/README.md` 样例：上游来源（项目 @ 分支 + commit SHA + 路径）、license（附原文或审计链接）、获取日期、用途（被哪个测试锚定）。
- **RNG golden 重生成须换 `LAYOUT_ID`**（当前 `0x4D53_5552_4E47_5631` = "MSURNGV1"，见 `src/rust/engine/src/rng.rs`）：任何影响流布局/输出位约定的修改 = 新布局 = 新 id（域分离，v1 流与后续流互不可换算），并保留旧 golden 作跨版本对照。
- 通道注册表单一事实来源在 `data-raw/build_channels.R`：改通道数据走该脚本重新生成，`tools/docs-sync.R` 与 channels 同步测试（drift 即红）是守卫。

## 6. 依赖纪律

- **预算冻结**（ARCHITECTURE §2 / D2/D4）：`extendr-api`（default-features=false，仅 ndarray feature）、`ndarray`、`rayon`、`memmap2`、`twobit 0.2.2`（ADR 0001 解锁）。**rand 族全局 deny**——随机性只有自研 PCG64 + SplitMix64。
- **新增依赖须 ADR**：说明必要性、体积影响、MSRV 兼容；并按 ADR 0002 §2 追加 vendor 基线行 + 更新 `tools/vendor.sh --check` 常量；每 ~0.1 MB xz 增量都要记录，超预算触发依赖再收缩决策。
- **MSRV 钉版不可动**：`matrixmultiply = 0.3.9`（≥0.3.10 需 rustc 1.75）、`rayon = 1.10.x`（≥1.11 需 rustc 1.80）；`Cargo.lock` 保持 version 3。不放宽 MSRV——升级 rustc 门槛需 ADR。
- `engine/catalog` 两 crate `#![forbid(unsafe_code)]`；`extendr-api` 只许出现在 FFI 壳 manifest；方向 ffi→catalog→engine 永不反向（`tools/check-dep-direction.sh` 断言）。

## 7. Commit 风格与评审流程

- **Conventional Commits**（`feat` / `fix` / `docs` / `test` / `refactor` / `perf` / `chore`），scope 用里程碑/单元号（如 `feat(m0): U-M0-04 引擎注册表`）；**中文 subject 可**。示例见 `git log`。
- **TDD 先行**：先写测试（红）再实现（绿）；错误路径测试断言 condition 而非崩溃。
- **评审流程**：PR → 模板检查项逐项勾选 → 至少一轮独立审核（AI agent 审核轮的 REVISE/PASS 结论记入当期 devlog）→ 本地验收电池 + CI 全绿 → squash 或按单元 merge。每个工作单元一份 devlog（`docs/devlog/`）；重大架构裁决走 ADR（`docs/adr/`）。
- **lifecycle**（ARCHITECTURE §3.5）：v1.0 前 API 标 `@experimental`；废弃走 `lifecycle::deprecate_warn`；NEWS.md 即 changelog；错误 class 遵守 `msuiter_error_<topic>` 规范，禁裸 `stop()`。
