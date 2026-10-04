# U-M4-02c 设计备忘：ms_convert() 机会转换（exome↔genome）

日期：2026-10-04（夜间窗口第二批随批）。范围：CAPABILITY-MATRIX L-G 行"机会归一化：基因组/外显子/panel 机会向量；exome↔genome 转换 | sigfit 似然内机会；sig_convert"——M4 面交付转换器；"似然内机会"（sigfit 语义）记 v1.x。

## §1 算法（sigfit convert_signatures 语义，[V] 溯源）

`conv = sig/opp_from·opp_to`，逐列重归一（每列独立，列和 1）。机会向量 = 96 通道 tri-nucleotide 频数（非份额——比值消尺度）。

**[V] 溯源链**：频数表出自 COSMIC v2/v3 签名数据库（sigfit → sigminer `human_trinuc_freqs`）；本机 sigminer 2.3.1（用户本人维护）源码即锚：`/Users/wsx/Documents/GitHub/sigminer/R/sig_convert.R:103`。genome 总量 8.505e9（≈2×3.1Gb 双链可突变位点量级）、exome 总量 1.53e8——量级健全性双锚。SP 标签序与我方注册表序不同（sigminer 按替换类×5'侧翼分块），**逐标签 match 后取值**，不按位置。

## §2 冻结设计

```r
ms_convert(signatures, from = "human-genome", to = "human-exome")
```
- `signatures`：96×k 矩阵（rownames == SBS96 注册表序；MsSignature 便捷法取 @signatures）。
- `from`/`to`：`"human-genome"` | `"human-exome"` | 用户自定义机会矩阵（96 向量或 96×k 列重复；正数有限）。
- 返回：同形状矩阵（列归一后）；零列保持零（不产生 NaN）；MsSignature 方法返回新 MsSignature（signatures 换、exposures/治理字段原样——exposure 是活性占比，转换不改变活性解释，[注] sigfit 语义）。
- 同名机会恒等（identity to machine-epsilon，sigminer 同款测试锚 3.5e-18）。
- **扩展口**：panel 机会 = 用户自定义矩阵（本批不捆绑 panel 表——无 [V] 锚）；`ms_convert_opps()` 内部构造器导出 genome/exome 表供复用。

## §3 验收锚

- 【逐位/数值】：genome→genome 恒等到 1e-15；genome→exome→genome 往返（先转后转回，列归一）到 1e-8（浮点往返可逆性，非逐位）；与 sigminer sig_convert 在同一输入上数值一致（≤1e-12，双侧独立实现）；零列不产 NaN。
- 名单：频数表进 R/sysdata（生成脚本 data-raw 记录溯源）或内联常量 + 注释溯源；测试字面抽查 3 个锚点值（A[C>A]A=1.14e8 等）。
- 错误路径：非 SBS96 空间 / 机会向量负值·零·非有限 / from=to 类型不匹配 → 结构化。

## §4 文档

CAPABILITY-MATRIX L-G 行注记 M4 转换器交付（"似然内机会"仍 ⏳）；NEWS.md。无新 FFI 面。
