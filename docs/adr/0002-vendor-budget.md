# ADR 0002：vendor 体积预算与 MSRV 构建证明（U-M0-02 spike）

- 状态：accepted（2026-09-28）
- 裁决单元：U-M0-02 M0 spike（W1 硬截止）
- 上游依据：ARCHITECTURE.md §0 D4、§2 构建条目 8（Makevars.in 按 string2path 模式 + vendor.tar.xz + offline + CARGO_BUILD_JOBS=2 + cleanup；MSRV 目标 1.71）；IMPLEMENTATION-PLAN.md §3.1 U-M0-02
- 关联：ADR 0001（twobit 解锁，最终依赖树含 twobit 0.2.2）

## 1. 实验环境（本机证明范围）

macOS arm64（Darwin 25.6.0）、R 4.5.2、xz 5.6.4、cargo/rustc stable 1.97.1、rustc 1.71.0（rustup 最小 profile）。**平台残留：Linux/Windows 构建证明由 U-M0-07 CI 矩阵承接，本 ADR 不覆盖。**

## 2. vendor 体积数字（最终依赖树，含 twobit）

命令（在 `src/rust/`，lock 状态 = Cargo.lock v3，matrixmultiply 钉 0.3.9，见 §4）：

```sh
cd src/rust
cargo vendor vendor
find vendor -type f -print0 | xargs -0 stat -f%z | awk '{s+=$1} END {print s}'
tar -cf /tmp/vendor.tar vendor && stat -f%z /tmp/vendor.tar
tar -cJf /tmp/vendor.tar.xz vendor && stat -f%z /tmp/vendor.tar.xz   # xz -6 默认档
```

| 口径 | 字节数 | MiB |
|---|---|---|
| `vendor/` 未压缩（22 crates，970 文件） | **10,674,351** | 10.18 |
| tar（未压缩） | 13,832,192 | 13.20 |
| **tar.xz（`tar -cJf`，xz -6）** | **1,125,136** | **1.07** |

参考基线（加入 twobit 前的 21 crates：10,580,063 / 13,652,480 / 1,107,780 字节）；`xz -9e` 与默认 `-6` 差 <0.1%（1,102,288 vs 1,102,296 @ 基线），采用默认档即可。压缩比 ≈ 12.3:1。

**增量记录（按本节纪律追加）**：

| 日期 | 单元 | 新增 vendor 内容 | 未压缩增量 | xz 增量 | 新基线（未压缩 / tar / xz） |
|---|---|---|---|---|---|
| 2026-09-28 | U-M0-09 | rayon 1.10.0 + rayon-core 1.12.1（FFI per-call 线程池，ARCH §2 预算内依赖；lock 钉版因 ≥1.11 需 rustc 1.80，方法同 §4） | +1,851,707 B | +282,452 B | **12,526,058 / 16,516,096 / 1,407,588** |

当前生效基线 = 上表末行；`tools/vendor.sh --check` 的内置常量随之更新（xz 口径仍保留 ±0.1% 版本容差带）。

**预算判断**：vendor.tar.xz 当前 ≈ 1.41 MB（U-M0-09 后），加全包源码（src/rust 13 KB + R/ 侧 ~48 KB 量级）仍远低于 CRAN 5 MB 包体积指导线；后续新增依赖每 ~0.1 MB xz 增量需在本 ADR 追加记录，超出预算即触发依赖再收缩决策（ARCH §11 风险条目）。

## 3. Offline 与 CRAN 模式构建证明

### 3.1 纯 cargo offline（vendor 目录直用）

```sh
mkdir -p .cargo && cp vendor-config.toml .cargo/config.toml
CARGO_HOME="$PWD/.cargo" CARGO_NET_OFFLINE=true cargo build --workspace --offline   # exit 0
CARGO_HOME="$PWD/.cargo" CARGO_NET_OFFLINE=true cargo test  --workspace --offline   # 1 passed (ffi_links_engine_and_catalog)
rm -rf .cargo
```

`CARGO_NET_OFFLINE=true` 下任何联网尝试都会使 cargo 报错退出；实测 build/test 全绿 → **offline 构建可行**。

### 3.2 R 侧 CRAN 模式（vendor.tar.xz 接线，string2path 模式全链路）

```sh
cp /tmp/vendor.tar.xz src/rust/vendor.tar.xz        # Makevars/config.R 期望位置
env -u NOT_CRAN -u DEBUG R CMD INSTALL . -l /tmp/msuiter-testlib
```

实测输出关键证据（exit 0，`* DONE (msuiter)`，安装后 `library(msuiter)` 加载成功）：

- `tools/config.R` 检测 `src/rust/vendor.tar.xz` 存在 → 注入 CRAN flags `cargo build -j 2 --offline --lib --release`（`CARGO_BUILD_JOBS=2` 同步生效）；
- Makevars 从 tarball 解包 `vendor/` 至 `src/vendor`，复制 `vendor-config.toml` → `src/.cargo/config.toml`（`=== Using offline vendor tarball ===`）；
- `--print=native-static-libs` RUSTFLAGS 生效；`cargo run --bin document` 生成 wrappers；
- `rust_clean` 清理 `src/.cargo`、`src/vendor` 与 `rust/target`（CRAN 模式 cleanup 契约成立）。

同一命令换 1.71 工具链再跑一遍亦通过（见 §4）。

### 3.3 vendor 产物入库策略

`vendor/` 与 `vendor.tar.xz` **不入 git**（根 `.gitignore` 与 `src/rust/.gitignore` 均已覆盖，`git check-ignore` 验证通过）；spike 后两产物已从工作区删除。发布期（U-M8-01）由 `tools/vendor.sh` 重新生成并附入 CRAN tarball（脚本输出三口径字节数，供 U-M0-07 CI 与本 ADR 基线做漂移对照）。`vendor-config.toml`（离线模板）入库且不再变动。

## 4. MSRV 证明（rustc 1.71.0）

### 4.1 基线 lock：失败（确切记录）

```text
$ cargo +1.71.0 build --workspace
error: package `matrixmultiply v0.3.11` cannot be built because it requires
rustc 1.75.0 or newer, while the currently active rustc version is 1.71.0
```

根因：ndarray 0.16.1 的传递依赖 `matrixmultiply` 0.3.11 在其 Cargo.toml 显式声明 `rust-version = "1.75.0"`（0.3.10 同）；其余 22 个依赖（含 syn 2.0.119/3.0.6、proc-macro2 1.0.107、once_cell 1.21.4、portable-atomic 1.15.0、twobit 0.2.2、memmap2 0.9.11）实测均在 1.71 可编译。

### 4.2 修复：lockfile 钉版（不放宽 MSRV）

```sh
cargo update -p matrixmultiply@0.3.11 --precise 0.3.9   # 0.3.9 无 rust-version 声明
cargo +1.71.0 build --workspace   # exit 0（冷构建）
cargo +1.71.0 test  --workspace   # 1 passed (ffi_links_engine_and_catalog)
```

### 4.3 1.71 × CRAN 模式端到端

```sh
env -u NOT_CRAN -u DEBUG R_ENVIRON_USER=/tmp/empty-renviron \
  PATH="$HOME/.rustup/toolchains/1.71.0-aarch64-apple-darwin/bin:$PATH" \
  R CMD INSTALL . -l /tmp/msuiter-testlib
# Using cargo 1.71.0 / rustc 1.71.0 → offline vendor tarball → -j 2 --offline --release → * DONE (msuiter)
```

**结论**：MSRV 1.71 声明成立，无需放宽 D4/§2；代价是 Cargo.lock 内一条钉版（matrixmultiply = 0.3.9，已入库）。

### 4.4 MSRV 维护约束（进 CI/流程注意，U-M0-07 承接）

1. **matrixmultiply 不得随 `cargo update` 升至 ≥0.3.10**（1.75+）；dependabot/lock 检查需保留该钉版或等价 rust-version 门。
2. **Cargo.lock 必须保持 version 3**（v4 需 cargo ≥1.78 才能读取）；当前即为 v3。
3. 本机复现坑：`~/.Renviron` 注入 `PATH="/Users/wsx/miniconda3/bin/:${PATH}"`，R 子进程内 conda 自带 cargo 1.92.0 会遮蔽前置的工具链目录（Makevars 将 `~/.cargo/bin` 追加在 PATH 尾部，无法纠正）。本机验证 MSRV 时需 `R_ENVIRON_USER=/tmp/empty-renviron` + 1.71 bin 前置 PATH；CI 镜像无 conda rust，不受影响。

## 5. 验收对照（U-M0-02 【工程】项）

| 项 | 结果 |
|---|---|
| 真实 vendor + xz 字节数落 ADR | §2（1,125,136 B xz） |
| offline 构建证明 | §3.1 通过 |
| CRAN 模式接线证明 | §3.2 通过（stable 与 1.71 各一遍） |
| rustc 1.71 构建结论 | §4 通过（matrixmultiply 钉 0.3.9；确切错误与版本已记录） |
| 三平台构建证明 | **残留**：macOS arm64 已证；Linux/Windows 由 U-M0-07 CI 矩阵承接 |
| vendor 超预算 → 依赖再收缩决策 | 不触发（1.07 MB ≪ 预算） |
