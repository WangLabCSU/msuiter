# ID83 语义设计备忘（M1c 头号单元·先设计后实现）

> 2026-09-30。mutational signature 方法学专家独立备忘，供 PI 裁决后派实现。对象：ROADMAP M1c 首项「ID83（SPMG 语义逐位复刻：重复游走/MH 前向优先/封顶/Q 规则）+ ID83 golden」；ARCHITECTURE §7 条目 2（目录完备性契约）、§0 D11/D13；CAPABILITY-MATRIX L-B（ID83=SPMG 逐位）。
>
> **证据基线**：SPMG 上游克隆 /tmp/audit/SPMG（AlexandrovLab/SigProfilerMatrixGenerator）。master = `edccbea6`（Merge PR #256）；tag `v1.3.6` = `4923d61`。行号均指 master `MutationMatrixGenerator.py`（下称 MMG）与 `SigProfilerMatrixGeneratorFunc.py`（下称 Func）；ID 函数区域 v1.3.6 行号 ≈ master + 16（函数体逐字节相同，见 §1）。

---

## 0. 结论速览

1. **parity 裁决建议：以 master（edccbea）语义为准——且对 ID83 而言 master ≡ v1.3.6，无版本歧义**（分类函数逐字节相同）。差异声明清单在 ID 通道上为**空集**；但 PR #256 含一处 SBS bias 索引修复，对已发布的 SBS192/384 parity 声明有实质含义（§1.3，cross-cutting，需 PI 知晓）。
2. ID83 = Func:1054-1145 索引的**前 83 行**（写入路径 `iloc[:83]`，MMG:3738）。SPMG 计算了 Ins:M 通道（行 83-93）与 complex/non_matching（94/95）但**不进 ID83 文件**——我方对应为显式 skip ledger。
3. 游走/MH/封顶的精确几何已钉死到行号（§3）；三个最容易错对的分叉点见 §7（插入锚几何、R/M 优先级与 M 下界、染色体端点三连行为），另附 audit 04 文档两处勘误（§1.4）。

---

## 1. Parity 目标版本裁决建议

### 1.1 取证（tag/commit 级）

- `git log v1.3.6..master`：MMG 文件自 v1.3.6 以来仅被 **57f49cc**（"Fix matrix reference generation and validation"，即 PR #256 squash）触碰；master 头 = edccbea（同一 PR 的 merge commit）。
- `git diff v1.3.6 master -- MMG` 共 4 个 hunk，**无一触及 ID/indel 代码**：
  1. `BED_filtering` 解析健壮性（`:116-133` 区域）；
  2. `gene_range` 重构为 `transcript_reference.iter_transcripts`（`:303-342`；纯基因偏倚统计，ID83 不依赖）；
  3. **SBS 两处**：`start < 3` 左侧翼守卫（新 :781-782）与 **bias 索引修复** `tsb_ref[chrom_string[start]]` → `tsb_ref[chrom_string[start-1]]`（1.3.6 :811 → master :808；见 §1.3）；
  4. `exome_check`/`panel_check` 的 cushion 条件修复（`:2396`/`:2810` 区域）。
- **决定性验证**：将两版的 `catalogue_generator_INDEL_single` 整函数文本抽出做 diff——**逐字节相同**（v1.3.6 def 于 :1185，master def 于 :1169，偏移 +16 来自 gene_range hunk）。
- 结论：**重复游走、MH 前向优先、封顶、Q 规则在 v1.3.6 与 master 之间零差异**。bench 发现的 DBS 计入策略差（M1s-13 P0-1）不在 ID 通道，见 §1.4。

### 1.2 建议

**默认采纳（与 SBS/DBS 先例一致）**：以 master 源码语义为准 + 文档声明与 1.3.6 的差异清单。对 ID83 该清单为空集，故声明更强：**「ID83 语义逐位对 SPMG v1.3.6 与 master 同时成立」**——这比 SBS/DBS 的单版本声明更干净，bench 侧用 1.3.6（用户实际在用）或 master 跑 ID 对拍均可，无 parity 歧义。devlog/04-source-audit 的 ID 节行号按审计时点快照书写（如 TSB 规则 :1846-1857），现 master 已漂移至 :1789-1799——实现以本备忘行号为准。

### 1.3 Cross-cutting 警报（非 ID，PI 需知晓）

- **SBS bias 索引 bug（PR #256 修复）**：v1.3.6 的 SBS 循环把转录链偏倚读在**突变位点 3' 邻碱基**的注解上（`chrom_string[start]`，0-based = 1-based start+1），master 才是突变碱基本位（`[start-1]`）。M1s bench 的 SBS96 逐格差=0 用的是**合成平注解基因组**（相邻碱基注解相同）→ 该 bug 被掩盖。**真实基因组（hg38 注解异质）上，ms_tally 的 SBS192/384 与 SPMG 1.3.6 会分叉、与 master 一致**。建议 M1c 阶段把 M1s bench 的 SBS 对拍锚升级为 master 或在 TSB 注解异质的合成基因组上复跑。
- **DBS 成员计入 SBS96 需重新表述**（M1s-13 P0-1 说「与审计所锚上游 master 行为不符」）：本次逐行复核发现，SBS 循环 `for line in lines`（master :758）对 SNV seqinfo **全量计数、无任何 dinuc 成员排除**；dinuc 块（:491-543、:615）只是**附加**写 DBS seqinfo。即 **v1.3.6 与 master 都把 DBS 对成员计入 SBS96**——这是 SPMG 固有行为，不是 1.3.6 独有。我方「排除」语义相对**所有** SPMG 版本都是 deliberate divergence，PI 裁决时应按此框架重述（排除并声明，或复刻双重计数）。

### 1.4 audit 04 文档勘误（随本备忘提出，不改既有文档）

1. **Q 规则方向写反**：04 §1 说「累积重复/MH 序列全为 C/T 或全为 G/A 时事件链不可解析 → 偏倚 Q」。源码（master :1789-1798）正相反：序列**全嘧啶（^[CT]*$）或全嘌呤（^[GA]*$）或 bias=="N" → 用真实 bias**（首碱基定向对整段一致，链可解析）；**混合 Pur/Pyr → "Q:"**（首碱基定向对整段无意义）。机制解释：定向翻转只看首碱基（:1431-1434/:1440-1443），全同类序列翻转后与 revcompl 谱系自洽，混合序列不自洽。
2. **「150 通道 ID-TSB」过时/有误**：现行 TSB 家族 = `indel_types[:-13]`（恰为规范 83 行，Func:1155）× `tsb_I = ["T","U","N","B","Q"]`（Func:198）= **ID415**；折叠 B（//2 入 T、余数入较大侧，MMG:3690-3736 区域）得 ID332。文件名前缀见 MMG:3612-3624（limited → ".ID83"，常规 → ".ID94"——文件名叫 94 但内容是 83 行，SPMG 自身命名残留）。

---

## 2. ID83 通道集、标签拼写与规范序

### 2.1 权威索引

`indel_types`（Func:1054-1145）共 **96 行**；写入 ID 文件时取 `iloc[:83]`（MMG:3738）＝规范 ID83。结构（我方 `ID83_CHANNELS` 按此生成，经 `data-raw/build_channels.R`，与 SBS/DBS 同纪律）：

| idx | 块 | 行数 | 说明 |
|---|---|---|---|
| 0-5 | `1:Del:C:0..5` | 6 | 1bp 缺失，C 类，key4=串联延伸数封顶 5 |
| 6-11 | `1:Del:T:0..5` | 6 | 1bp 缺失，T 类 |
| 12-17 | `1:Ins:C:0..5` | 6 | 1bp 插入，C 类 |
| 18-23 | `1:Ins:T:0..5` | 6 | 1bp 插入，T 类 |
| 24-29 / 30-35 / 36-41 / 42-47 | `{2,3,4,5}:Del:R:0..5` | 24 | 串联重复缺失 |
| 48-53 / 54-59 / 60-65 / 66-71 | `{2,3,4,5}:Ins:R:0..5` | 24 | 串联重复插入 |
| 72 | `2:Del:M:1` | 1 | MH 缺失，key4 下界 1 |
| 73-74 | `3:Del:M:1..2` | 2 | |
| 75-77 | `4:Del:M:1..3` | 3 | |
| 78-82 | `5:Del:M:1..5` | 5 | |
| （83-93） | `{2..5}:Ins:M:1..{1,2,3,5}` | （11） | **SPMG 扩展行，不入 ID83** |
| （94/95） | `complex` / `non_matching` | （2） | 簿记行，不入 ID83 |

计数校验：24+48+11 = **83** ✓；96 = 83+11+2 ✓。`non_matching` 在代码中为不可达防御分支（mut_type 只可能以 Del/Ins 开头，MMG:1733-1734；complex 在 :1445-1449 已 `continue`）。

### 2.2 拼写与序的精确规则

- 标签 = `key1:key2:key3:key4`；key1 ∈ {1,2,3,4,5}（5 = "≥5bp"）；key2 ∈ {Del,Ins}；key3：key1=1 时 ∈ {C,T}，key1>1 时 ∈ {R,M}；key4 单个十进制数字。整表 = 标签字符串的 ASCII 字典序（Del<Ins、C<M<R<T、key4 单位数字字典序=数值序），与 SBS96/DBS78 的 ASCII 序先例一致。
- 1bp 的 key3：被删/插碱基 ∈ {C,G} → "C"，∈ {A,T} → "T"（即 revcompl 归一后的嘧啶类；MMG:1681-1685 用原始 `ref[1]` 判、:1727-1730 用原始 `mut[1]` 判——注意 bias 翻转用的 `ref_base`/`mut_base`（:1431/:1440）是独立局部变量，**不**回写 allele）。
- ID83 与转录链注解**完全无关**：`indel_key`（:1771-1779）不含 bias；bias/strand 只进 tsb/complete 矩阵（:1794/:1858）。⇒ 我方 ID83 装配层**不需要** transcript/TSB 输入（比 SBS192/384 少一个注解依赖）。Q 谓词仍按 §3.6 实现为纯函数，供后续 ID415 复用（ROADMAP M1c 点名 Q 规则）。

---

## 3. 变异 → 通道判定算法（伪代码级）

### 3.1 坐标与输入约定（源头钉死）

- SPMG 的 ID 输入 seqinfo 由转换器**逐字保留 VCF 四元组** `(sample, chrom, POS, REF, ALT)`（convert_input_to_simple_files.py:74-77 解析、:383-385 原样写出；indel 判据 = 非 (len(ref)==1 ∧ len(mut)==1)，:94）。因此：
  - `start` = **1-based VCF POS = 锚碱基位置**（无锚剥离）；缺失 = REF=锚+被删段、ALT=锚（:1427-1434 判 Del，`type_sequence = ref[1:]`）；插入 = REF=锚、ALT=锚+插入段（:1436-1443，`type_sequence = mut[1:]`）。
  - 被删段占 1-based `[start+1, start+L]`（L = type_length）；插入点位于锚 `start` 与 `start+1` 之间。
  - `:1312-1315` 的 `"-"` 前缀分支只服务于非 VCF 输入格式（seqinfo 里 ref/mut 为 "-"），msuiter 不需要。
- 我方映射：`VarRecord{pos: u64(0-based), ref_, alt}`（mnv.rs:63-70）。ID 层入口约定 pos0 = 锚位置（pos0+1 = 1-based start）。**VCF 左锚/右锚表示不变式**：同一缺失/插入的不同合法锚表示必须落入同一通道（golden G36 钉死）。

### 3.2 验证链（进入分类前；全部落 skip ledger）

按 MMG:1305-1421 顺序：
1. allele 字符 ∈ {A,C,G,T}（SPMG 允许 "-" 且大写化；我方由 mnv.rs validate 已保证，等价 :1322-1359）；
2. `ref == alt` → skip（:1361-1374，mnv.rs RefEqualsAlt 已覆盖）；
3. **相邻全等记录去重**：`line == prev_line`（同染色体相邻两行逐字段相等）→ 丢弃第二条（:1376-1386）。← M1s-13 P0-2 裁决项；ID 侧同样适用；
4. 锚位置越界（`start` 出染色体）→ skip（:1391-1406）；
5. **锚碱基 vs 参考基因组比对**：`genome[start] != ref[0]` → skip（:1408-1421）。注意：**只比对锚一个字节**；被删段对错由游走的匹配隐式保证。锚位为参考 N → skip（tsb_ref[16] = ["N","N"]，save_chrom_tsb_separate.py:129-150）。

### 3.3 分类（:1427-1449）

```
del_len = len(ref) - 1;  ins_len = len(alt) - 1        # 锚各占 1
if del_len >= 1 and ins_len == 0  -> Del(L = del_len)
if ins_len >= 1 and del_len == 0  -> Ins(L = ins_len)
otherwise                          -> Complex（:1445-1449）
```
（两 allele 均 >1 且不等长 → complex；单记录等长块替换在 msuiter 属 MNV 路由，见 §4。）

### 3.4 串联重复游走（Del :1451-1482 / Ins :1543-1571）

**几何（Del）**——单位 = 被删段 `unit = ref[1..]`，长度 L：
- 左窗口初值：1-based `[start-L+1, start]`（**止于锚、含锚**；0-based `[start-L, start-1]`，MMG:1462-1463 `range(pos_rev-L, pos_rev)`，pos_rev=start）；
- 右窗口初值：1-based `[start+L+1, start+2L]`（**紧接被删段之后**；0-based `[start+L, start+2L-1]`，:1471-1473，pos=start+L）；
- 扩展步进 L：左窗每步前移 L（`pos_rev -= L`，先拼 `actual_seq + sequence`），右窗后移 L（`sequence += new_seq`）；**比较是逐字节的 EXACT 匹配**（`== type_sequence`，:1464/:1474-1477）——旋转单元（unit 的循环移位）**不**延伸（golden G27）；
- 守卫：左 `while pos_rev - L > 0`（:1464）；右 `while pos + L < len(chrom_string)`（:1474-1477，**比"窗口末碱基是染色体最后一位"严一格**——末位恰为染色体终点的窗口会被拒绝延伸）；
- **无窗口上限**（游走直到失配或端点；对照 MutationalPatterns 的 19/20bp 有界近似——audit 04 §2 已判反例）；
- 序列累积：`sequence = 左延伸 + unit + 右延伸`。

**几何（Ins）**——单位 = 插入段，插入点在锚后：
- 左窗口初值：1-based `[start-L+1, start]`（止于锚、含锚；:1551-1552，pos_rev=start）；
- 右窗口初值：1-based `[start+1, start+L]`（插入点后 L 个碱基，不含锚；:1560-1562，pos=start）；
- 守卫同 Del（:1553/:1563-1566）。Del/Ins 完全对称于"受影响区间/插入点"。

**端点行为三连（分叉点 F3，见 §7）**：初值读**无守卫**（:1462/:1471/:1551/:1560 在 try 块外）——被删段贴近染色体端点时 SPMG 直接 IndexError 崩溃；扩展守卫见上；左窗起点 `start-L < 1` 时 Python **负索引回卷**读染色体**尾部**碱基（`chrom_string[-i]`）参与比较。我方决策建议见 §7-F3。

### 3.5 微同源 MH（仅 `L > 1 且 len(sequence) == L`，即**重复游走零延伸**；Del :1484-1540 / Ins :1573-1629）

- 派生串（Del，`ref` 含锚故 `ref[1:]` 为被删段 D，|D|=L）：
  `forward_homology = D[0..L-1]`（去末碱基，:1486 `ref[1:-1]`）；`reverse_homology = D[1..L]`（去首碱基，:1487 `ref[2:]`）。Ins 对称用插入段（:1575-1576）。
- **前向搜索**（Del :1512-1521，pos = start+L；Ins :1601-1610，pos = start）：`for i in (L-1)..1`：读插入/被删区间**紧后**的 i 个碱基，比较 `forward_homology[:i]`（**前 i 个**碱基）；**从最长起试，首中即停**（最长 MH）。
- **反向搜索**（Del :1523-1532，pos = start；Ins :1612-1621）：`for i in (L-1)..1`：读区间**紧前**的 i 个碱基（**止于锚、含锚**），比较 `reverse_homology[-i:]`（**后 i 个**）；同样最长优先。
- **裁决（:1534-1540）**：`for_hom > rev_hom 或 for_hom == rev_hom → 前向`（`sequence += for_seq`，`mut_type += "_Micro_for"`）；仅 `rev_hom > for_hom` → 反向（`sequence = rev_seq + sequence`）。**前向优先含等长平局**。注意：等长平局时两条路径的 `len(sequence)` 相同 ⇒ **对 ID83 通道不可观测**（只影响 ID-complete 字面与 ID415 的 Q 判定成分）——golden 只能钉「平局标签一致」，规则本身以行号为准。
- MH 找到 ⇒ key3 = M，key4 = MH 碱基数 = `len(sequence) - L`；**≥1**（进 MH 分支即 hom>0）⇒ M:0 通道不存在。**重复延伸压倒 MH**：游走一旦延伸（哪怕 1 个拷贝）即跳过 MH 分支（:1485/:1574 条件），即使可行 MH 更长（golden G37）。

### 3.6 键构造与封顶（:1641-1730）

```
Del, L>1:  key1 = min(L,5)                       # :1645-1650
  纯 Del:   key3=R;  key4 = min( len(sequence)/L - 1 , 5 )   # int() 截断；:1653-1659
  MH:       key3=M;  key4 = len(sequence) - L;  >5 → 5    # :1662-1670
Del, L=1:  key1=1; key4 = min(len(sequence)-1, 5);      # :1673-1679
           key3 = "C" if ref[1] ∈ {C,G} else "T"        # :1681-1685
Ins 完全对称（:1688-1730），仅 M 封顶写法为 >=5 → 5（:1711-1716，通道结果与 Del 相同）
```
细节钉死：(a) key4 的归一化用**未封顶的原始 L**（局部变量 key_1 = len(ref)-1，:1655/:1702——7bp 单元 2 拷贝缺 1 → key4 = int(14/7-1) = 1，key1 才封 5）；(b) `len(sequence)/L` 为 Python3 浮点除后 `int()` 截断（正数域 = floor）；(c) R 的 key4 = 序列中单元总拷贝数 − 1（缺失语义 = 参考中剩余拷贝 + 被删 1 拷贝；插入语义 = 两侧匹配拷贝 + 插入 1 拷贝）；(d) **R:0 的语义不对称**：Del 的 R:0 = "单元不在串联语境"（游走零延伸）；Ins 的 R:0 = **非重复插入的默认值**（非 MH 插入即使毫无串联语境也是 `N:Ins:R:0`）——读反即错（F1 附注）。

`limited_indel` 重映射（Ins+M → R:0，:1766-1769）与 complete/simple 矩阵（:1737-1787）**不在 M1c 范围**（记录备查：limited 版输出文件名恰为 ".ID83"，与常规版 ".ID94"=83 行的命名错位，勿混淆）。

### 3.7 Q 谓词（:1789-1799；ID83 不消费，为 ID415 预置）

```
q = NOT ( sequence 全 ∈ {C,T}  OR  sequence 全 ∈ {G,A}  OR  bias == "N" )
q = true  -> tsb key = "Q:" + indel_key（strand := 0）
q = false -> tsb key = bias + ":" + indel_key      # bias 已按首碱基 revbias 翻转（:1431-1443）
```
sequence = 累积的重复/MH 序列（含被删/插入段本身）。

### 3.8 参考基因组窗口需求与接口

- 静态需求：任意事件至少需要被删/插入区间两侧各 L（≤5，MH 再 −1）个侧翼碱基；**动态需求无上限**（串联游走无窗口上限——卫星阵列可游走整臂）。
- 接口建议：genome.rs 增加 `range(chrom, start0, end0_exclusive) -> Result<Vec<u8>, MsError>`（与 `context` 同错误纪律：topic `"bounds"`、1-based i/j、**绝不 clamp**，genome.rs:106-113 语义直承）；`context()` 改为 `range` 的薄包装（签名不变，既有调用零破坏）。ID 游走器用游标按 64B 块懒取、触边倍增续取（摊还 O(游走长)），D12 无状态借用在调用内闭环不变。
- 端点三态（F3）：初值读越界 → SPMG 是未捕获 IndexError（上游崩溃）→ 我方**结构化 bounds 错误 + ledger skip**（sbs.rs:47-54 硬化先例）；扩展守卫的单 base 过严**逐字复刻**；Python 负索引回卷——**建议复刻**（`chrom_string[-i]` = 染色体尾部第 i 位；经 range 两端取数拼接即可，确定性、代价 ≤4 碱基/事件），使 D11「语义逐位」无例外成立；若 PI 选「端点即停」则必须写入 D13 失效条件并在 golden 钉死两种回卷场景（G31）。

---

## 4. 与 MNV 路由的交界（mnv.rs 改接方案）

现状：`classify_single`（mnv.rs:276-310）把单侧 1bp indel 记为 `LedgerEntry::Skipped(SkipReason::SimpleIndel)`、无事件；complex 记为 `RoutedEvent::ComplexIndel`。M1c 改接：

1. **SimpleIndel 升级为事件**：新增 `RoutedEvent::Indel { record, pos, ref_, alt }` + `LedgerEntry::Id83`（`Destination::Id83`）；`SkipReason::SimpleIndel` 退役（保留编译期 `#[non_exhaustive]`-式过渡由实现定）。模块文档路由表（mnv.rs:13-25）同步改写——该表 :23 已预埋「double indel → 各自去向 = ID83 destination, lands in U-M1c」。
2. **相邻 indel 不合并**：SPMG 的 dinuc/MNV 配对只作用于 SNV 记录流（:491-543 逐 SNV 行两两距离），indel 记录永远独立逐条分类；我方重连条件（mnv.rs:37-54）本就不合并不等长拼接，两个相邻 simple indel 各自成 Indel 事件、各计一次 ✓ 与 SPMG 一致。
3. **complex**：SPMG 计入扩展索引第 94 行 `complex`（:1445-1449），**无 ID83 通道** → 我方 `ComplexIndel` 目的地保留为 ledger/目的地桶（计数进 provenance，不入 83 向量），不改既有枚举。
4. 单记录等长块替换 ≥2bp：msuiter 走 MNV/LongMnv（U-M1s-07 已裁决）；SPMG 实际把这类记录放进 INDEL seqinfo 并落入 `complex` 行（转换器 :94 的 SNV 判据 + :1445）——属 mnv.rs 层的既知分歧，**不属于 ID83 单元**，此处仅备案供 PI 在路由审计时取舍。
5. 验证链次序：mnv.rs `validate`（invalid_base/empty/ref==alt）在前，ID 层再做锚-基因组比对与去重（P0-2），失败各自落 ledger——全路由保持 TOTAL（每记录恰一去向）。

---

## 5. Golden 设计（36 条手推清单规格）

记号：基因组按 1-based 列出，`s` = 锚位，`POS/REF/ALT` 为 VCF 四元；每条附 SPMG 行号可独立核验。实现时落为 `tests/indel83/golden_*` + 双端（R/Rust）布局夹具（沿 M1s 体系）。

**1bp 缺失（key4 = 游走延伸数，:1673-1685）**

| # | 基因组（1-based 片段） | POS/REF/ALT | 期望 | 推导要点 |
|---|---|---|---|---|
| G1 | `C A T G` | 2/AT/A | 1:Del:T:0 | 左窗=锚A≠T(:1462)、右窗=G≠T(:1471)；ref[1]=T→T(:1684) |
| G2 | `G A C A` | 2/AC/A | 1:Del:C:0 | 双向零延伸；ref[1]=C→C(:1682) |
| G3 | `A C C A` | 1/AC/A | 1:Del:C:1 | 右窗 pos3=C ✓ 一延伸 → key4=1 |
| G4 | `A T T T T G` | 1/AT/A | 1:Del:T:3 | 右链 3×T 延伸(:1474-1482)；左=锚A 截止 |
| G5 | `A T⁷ G`（7 连 T） | 1/AT/A | 1:Del:T:5 | key4=6>5→5（封顶 :1676-1677） |
| G6 | `A G G A` | 1/AG/A | 1:Del:C:1 | **嘌呤缺失映射 C**：ref[1]=G∈{C,G}→C(:1682) |
| G7 | `T C A`（1-based: T@1,C@2,A@3） | 2/TC/T | 1:Del:C:0 | 零延伸（对照 G1 验证锚不变性） |
| G8 | `A T T T T G` | 3/TT/T | 1:Del:T:3 | **锚不变式**：中跑锚左窗含锚 2×T+右 1×T → 同 G4（:1553 守卫 pos_rev−L>0 止于 pos1） |

**1bp 插入（:1543-1571 游走 + :1718-1730 键）**

| # | 基因组 | POS/REF/ALT | 期望 | 推导要点 |
|---|---|---|---|---|
| G9 | `C A` | 1/C/CT | 1:Ins:T:0 | 左窗=锚C≠T、右窗=A≠T；mut[1]=T→T(:1729) |
| G10 | `A A A G` | 2/A/AA | 1:Ins:T:3 | 左窗含锚 2×A + 右 1×A（:1553 左界守卫 pos_rev−1>0 止）→ 4×A |
| G11 | `C A` | 1/C/CG | 1:Ins:C:0 | mut[1]=G∈{C,G}→C(:1727-1728) |
| G12 | `A T⁶ G` | 2/T/TT（锚=首个 T 后…取 T@2） | 1:Ins:T:5 | 插后 7 连 → 延伸 6 → 封 5（:1722-1723） |
| G13 | `A T C` | 1/A/AT | 1:Ins:T:1 | 左窗=锚A≠T；右窗=T@2 ✓ → run2 语义 |

**>1bp 串联缺失（key4 = 拷贝数−1，:1653-1659）**

| # | 基因组 | POS/REF/ALT | 期望 | 推导要点 |
|---|---|---|---|---|
| G14 | `T A CG CG A`（A@2 锚） | 2/ACG/A | 2:Del:R:1 | 右窗=pos5,6="CG" ✓ → 2 拷贝 → int(4/2−1)=1；左窗="TA"≠ |
| G15 | `T A C G A A` | 2/ACG/A | 2:Del:R:0 | 右窗="AA"≠ → 零延伸 |
| G16 | `C A A (CAG)² T`（锚 A@3） | 3/ACAG/A | 3:Del:R:1 | 右窗=pos7-9="CAG" ✓ → 6/3−1=1 |
| G17 | `(CAG)⁴`（任一锚） | 3/ACAG/A | 3:Del:R:3 | 4 拷贝 → 12/3−1=3 |
| G18 | `(ACGT)³` | 1/ACGT…/A | 4:Del:R:2 | 12/4−1=2 |
| G19 | `(ACGTA)³` | 1/ACGTA…/A | 5:Del:R:2 | key1=5；15/5−1=2 |
| G20 | `(CGTACGA)²`（7bp 单元） | 1/…7bp…/锚 | 5:Del:R:1 | **key4 归一化用原始 L=7**：int(14/7−1)=1；key1 封 5（:1646-1650 vs :1655） |

**MH 缺失（先 R 后 M 优先级 + 最长优先 + 前向优先，:1484-1540）**

| # | 基因组 | POS/REF/ALT | 期望 | 推导要点 |
|---|---|---|---|---|
| G21 | `G A A C A G` | 2/AAC/A | 2:Del:M:1 | 游走零延伸；fwd_hom="A"，区间紧后=pos5=A ✓(:1512-1521) → key4=3−2=1(:1664) |
| G22 | `A T G T A`（锚 T@2） | 2/TGT/T | 2:Del:M:1 | 被删 "GT"@3-4；fwd_hom="G" 落空（pos5=A）；rev_hom="T" 命中锚(:1523-1532) → 反向路径；通道与正向同（M 不分方向） |
| G23 | 见下方文字版（基因组 `T T C C A G C A G A T`） | 4/CAGC/C | 3:Del:M:2 | fwd(2) > rev(1) → 前向(:1534-1537)；完整推导见文字版 |
| G24 | `A A A T CGT C A A`（T@4 锚，deleted CGT@5-7，pos8=C） | 4/TCGT/T | 3:Del:M:1 | **平局→前向**(:1535)：rev_hom="T" 命中锚=1；fwd_hom="CG"→次选 "C" 命中=1；等长 → 前向；ID83 标签与反向胜出时相同（等长不可观测，钉规则而非标签） |
| G25 | 6bp 缺失 `CGTACG`，区间紧后恰为 `CGTAC` 且第 6 位 ≠ G（不触发 R 游走）、左侧不构成匹配 | 相应锚 | 5:Del:M:5 | fwd 5 命中 → key4=11−6=5（不触发 >5 封顶，:1665-1666）；key1 封 5 |
| G26 | deleted `TGCC`，区间紧后 `TG X`（X≠C），锚及左侧不构成 `GCC` 尾匹配 | 相应锚 | 4:Del:M:2 | fwd i=3 败、i=2 "TG" ✓（最长优先，:1514） |
| G27 | `A A A T A` 前置串联 + 后接 MH：pos1-3="ATA"、A@4 锚、deleted ATA@5-7、pos8-9="AT" | 4/AATA/A | **3:Del:R:1** | **重复压倒 MH**：左窗游走先延伸 1 拷贝 → :1485 条件失败 → 跳过 MH，即使 2bp MH 可得 |

G23 文字版（修正表内占位）：基因组 `T T C C A G C A G A T`（pos1..11：T,T,C,C,A,G,C,A,G,A,T）。POS=4/REF=`CAGC`/ALT=`C`（锚 C@4，被删 `AGC`@5-7，pos8-9="AG"）。左窗 pos2-4="TCC"≠；右窗 pos8-10="AGA"≠；fwd_hom="AG"：i=2 读 pos8-9="AG" ✓ for=2；rev_hom="GC"：i=2 读 pos3-4="CC"≠、i=1 读 pos4="C"≠"C"？——rev_hom[-1:]="C"，pos4='C' ✓ rev=1。for(2)>rev(1) → 前向 → sequence="AGCAG" → key4=5−3=2 → **3:Del:M:2** ✓。

**MH 插入 / complex / N / 端点 / Q / 去重（含 ledger 期望）**

| # | 输入 | 期望 | 推导要点 |
|---|---|---|---|
| G28 | 插入 `CT`，插入点紧后碱基 = `C` | **无 ID83 通道 → ledger** | SPMG 键 "2:Ins:M:1" 属扩展行 83-93（Func:1128-1138），`iloc[:83]` 剔除（MMG:3738）→ 我方显式 skip（理由码建议 `ins_mh_no_channel`） |
| G29 | 插入 `ACA`，紧后两碱基 = `AC` | ledger（"3:Ins:M:2" 同上） | 同 G28 |
| G30 | POS=2/REF=ACGT/ALT=AG | **ComplexIndel 目的地，不入 83** | :1445-1449 |
| G31 | 2bp 缺失锚 POS=1（contig 首端） | **F3 裁决项**：复刻回卷 → 左初值读 contig 尾+首 2 碱基参与比较（golden 备两个变体：尾+首≠unit → R:0；==unit → 延伸发生）；端点即停 → 固定 R:0 + D13 声明 | :1462 `range(-1,1)` 负索引语义 |
| G32 | 1bp 缺失锚 POS=1（contig 首端） | 正常通道（1bp 左窗=锚本身，无回卷） | :1462 `range(0,1)` |
| G33 | 被删段紧贴 contig 末端（start+2L−1 > 末位） | **结构化 bounds 错误 → ledger skip**（SPMG 上游为未捕获 IndexError 崩溃——我方硬化偏离，D13 声明） | :1471 无守卫初值读 |
| G34 | 锚位参考碱基 = N | ledger skip（`anchor_n`） | :1408-1421 + tsb_ref[16] |
| G35 | 锚=A/C/G/T，但被删段紧后为 N | 正常通道、N 视为失配截断（非 skip） | tsb_ref 基础映射 :129-150；游走比较逐字节 |
| G36 | 2bp 缺失 `CG`，紧后为 `GC`（旋转 tandem） | 2:Del:R:0 | **EXACT 单元匹配**：`new_seq == type_sequence`（:1476）不认旋转 |
| G37 | 同相位相邻重复记录 ×2（全等四元组） | 第二条 ledger skip（**P0-2 裁决挂钩**） | :1376-1386 |
| G38？ | ——（Q 谓词钉死两例，作谓词列而非通道） | del `CG`（混合）→ q=true；del `CT`（全嘧啶）→ q=false | :1789-1798（audit 04 勘误 §1.4-1） |

（上表 38 个编号含 1 个文字版修正与 1 个谓词列，有效 golden ≥36；实现时 G23/G24 的 B 占位按文字版展开。）

**验收形态**：每条 = (基因组片段, VCF 四元) → (ID83 83 维 one-hot 或标签, ledger 期望, q 谓词期望)。双端同步：`build_channels.R` 生成 `ID83_CHANNELS` + `R/sysdata.rda` 位等（沿 test-channels-sync 先例）；结构契约测试钉：表长 83、ASCII 序、块界 0/24/72/83、逐块前后缀。

---

## 6. D13/D11 声明审查（ID83 的"语义逐位"边界）

- **对哪个版本成立**：SPMG master edccbea **且** v1.3.6（ID 分类函数逐字节相同，§1.1）——D11 硬验收，双版本一次性钉死。
- **输入域**：大写 ACGT allele 的 VCF 锚式记录（等价 SPMG seqinfo 全域）；坐标已排序；参考基因组为 2bit（ACGT+N，软屏蔽关闭 genome.rs:23-31）。**ID83 不需要任何转录注解输入**（§2.2）。
- **域外行为（逐项声明）**：非 ACGT allele → ledger（同 SPMG :1322-1359）；ref==alt → ledger（:1361）；全等相邻重复 → P0-2 裁决（:1376）；锚 N → ledger（:1408-1421）；侧翼 N → 失配截断非 skip（与 SPMG 有效行为一致，:1463 等逐字节比较的自然结果）；侧翼窗越界 → 结构化 bounds 错误 + ledger（**硬化偏离**：SPMG 为未捕获崩溃 :1471；先例 sbs.rs N-窗口策略）；contig 首端回卷 → F3 裁决（复刻=逐位无例外 / 即停=D13 失效条件）。
- **不成立的声明**：ID415/ID332（TSB 家族）、ID-complete、limited_indel 变体、ID89/476（Koh 2025，v1.x）均**不在**本单元的逐位声明内；Q 谓词实现但仅作内部纯函数测试，不构成 ID415 parity 声明。
- **失效条件**：SPMG 未来若再触 ID 函数（当前 v1.3.6..master 唯一文件级 commit 57f49cc 未触）需重跑 golden；参考基因组版本更换不影响语义（无注解依赖）但影响通道分布。

---

## 7. 最容易错对的分叉点（供 PI 重点复核）

- **F1 · 插入/缺失的锚几何与 R:0 语义**（§3.1/§3.4）：SPMG 的 start = VCF POS = **锚**，游走窗口是"含锚左窗 / 排锚右窗"——按"从被删段直接走"的直觉实现会整体偏 1 个碱基（所有 R/M key4 系统性错一格，且只在 tandem 语境暴露）。附带：Ins 的 R:0 是非重复插入的**默认通道**，Del 的 R:0 是"无串联语境"——同码不同义。golden G4/G8（锚不变式）、G13-G15、G36 钉死。
- **F2 · R/M 优先级 + M 下界 + Ins:M 无通道**（§3.5/§2.1）：先游走后 MH（零延伸才进 MH，:1485）且旋转不延伸（:1476）——重复延伸 1 拷贝即吞掉更长 MH（G27）；M 通道 key4 ≥1（无 M:0，进 MH 分支即 hom>0）；**SPMG 计算了 Ins:M 但 ID83 无此通道**（iloc[:83]）——实现者极易顺手把 "N:Ins:M:x" 计进 83 表（或反向把 Del:M 漏掉）。golden G21-G22 vs G28-G29 钉死。
- **F3 · 染色体端点三连行为**（§3.4/§3.8）：①初值读无守卫（SPMG=上游崩溃；我方=结构化错误+ledger，硬化偏离须声明）；②右窗扩展守卫 `pos+L < len` 比"窗口末=染色体末位"严一格（末位恰终点时丢一次合法延伸，逐字复刻）；③左窗 Python 负索引回卷读染色体尾部（建议两窗取数复刻以保 D11 无例外）。三态必须分别有 golden（G31/G32/G33）与 D13 措辞，PI 裁决 ③ 的复刻 vs 即停。
- **附：audit 04 Q 规则方向勘误**（§1.4-1）：全同类→真实 bias、混合→Q（源码 :1789-1798 与 04 文档表述相反）。实现照源码；04 文档由 PI 安排勘误（本备忘不改既有文档）。

---

## 8. 实现落点（裁决后备查）

`src/rust/catalog/src/indel83.rs`（ARCHITECTURE §5 树位 :112）+ `channels.rs` 增 `ID83_CHANNELS`（build_channels.R 生成）+ mnv.rs 事件改接（§4）+ genome.rs `range`（§3.8）+ tests（golden 36 条 + 表结构契约 + 锚不变式/对称性 property + 端点三态）+ bench：10⁶ 合成变异 SPMG vs ms_tally ID83 逐格差=0（生成器需按 P0-2 裁决处理重复记录；SPMG 侧 CHECKSUMS 绕过与 input 缓存清除沿 M1s-13 先例）。

---

## 9. 实现与审核更正记录（2026-09-30）

> 本节由独立审核 U-M1c-01 修复轮补记（修复与记录强耦合，授权实现轮代笔）。只增不改：§1-§8 保持审阅时点原貌，以下如实登记与正文/既有声明不一致之处。

### 9.1 「R 冻结 golden 稳定」表述更正（27bfbb5 commit message）

实现 commit 27bfbb5 说明中的「tally.rs 编译垫片保持 R 冻结 golden 稳定」不准确，更正如下：

- **记录 9/10 被强制改写**（`tests/testthat/helper-tally.R`、`test-catalog-tally.R`、`test-ffi-tally.R`）：ledger 行由 `9\tmnv`/`10\tmnv`（等长 del+ins 相邻对拼成的 3 bp 块替换）改为 `9\tskipped:simple_indel`/`10\tskipped:simple_indel`，`n_skipped` 9→11。该改写是路由修复（§4.2：SPMG 配对只作用于 SNV 记录流，indel 永不合并）的**必然后果**，语义正确；不实的是「golden 稳定/未动」的声称——冻结 golden 在强制处被打开并改写。commit message 无法重写，以本节为准。
- **记录 15 确实逐字未动**（`15\tskipped:simple_indel` 前后一致），但机制是 tally.rs 的过渡映射 `LedgerEntry::Id83 -> SkippedSimpleIndel`（编译垫片）使路由层 Id83 更名对 R 侧不可见；接线单元翻转垫片时 R 侧需同步评估。

### 9.2 独立审核 P0 修复与 golden 补充（本轮）

- **P0-1（key4 R 类缺封顶）**：§3.6 正文写对（`min(len(sequence)/L - 1, 5)`，:1653-1659/:1699-1705），实现漏译 `.min(5)`：≥7 拷贝串联（key4=6 起）debug 触发构造哨兵 panic、release 静默错桶（(AC)⁹ 缺失被计为 3:Del:R:2）。已修；补 4 条 golden——Del R 与 Ins R 各「恰好 7 拷贝边界 + 9 拷贝远界」，逐条与独立 oracle（/tmp/audit-id83/oracle.py，master edccbea6 誊写）对拍一致。
- **P0-2（release profile 编译失败）**：`label_of` 原挂 `#[cfg(debug_assertions)]`，而 `debug_assert_eq!` 函数体在 release 仍参与类型检查 → `cargo build --release -p msuiter-catalog` E0425（CRAN 模式 R CMD INSTALL 必挂）。修复：去 cfg 常驻（构造正确性哨兵，两种 profile 下均无死代码）。**release profile（build + test）自本轮加入验收门。**
- **P2（同轮顺带备案）**：DuplicateRecord 去重按上游作用域扩展到 INDEL 流全部行（转换器 :94 判据：一切非纯 SNV 记录，含 complex 与块替换；流内 `prev_line` 跨 SNV 连续，golden G37b-G37e）；右窗循环体内无守卫复读（:1477/:1566）补结构化 bounds golden（G33b，oracle 同位 IndexError 对拍）。

### 9.3 正文 golden 坐标勘误备案（§5 表，正文不改）

- **G7**：正文写 POS 2/TC/T；锚不变式意图要求锚为 T@1（2 号位落在被删碱基上），实现按 POS 1/TC/T 修正，期望通道 1:Del:C:0 不变。
- **G17**：正文写 3/ACAG/A；在 `(CAG)^4` 上该四元组的锚字节 ≠ 参考碱基（:1408-1421 会判 mismatch），实现按锚规则取 3/GCAG/G——同一物理事件，期望 3:Del:R:3 不变。

两处均为备忘笔误而非语义分歧；测试注释已就地说明，本节登记备案。
