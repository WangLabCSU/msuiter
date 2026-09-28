# 调研报告 03：应用文献与应用场景全景（2012–2026）
> ℹ️ **文档性质**：本篇为调研快照（archival snapshot，核实日期见文内）。活决策以 [ARCHITECTURE.md](../ARCHITECTURE.md) §0（D1–D16）与 [reviews/00-synthesis.md](../reviews/00-synthesis.md) 为准；文中方法命名（如 MSU-Extract、MSU-Corr）为当时措辞，现行命名见 ARCHITECTURE §5；benchmark 指标以 [CAPABILITY-MATRIX.md](../CAPABILITY-MATRIX.md) 与 ARCHITECTURE §8 为准。


> 调研日期：2026-09-27。所有 PMID 均经 PubMed (NCBI E-utilities) 当场核实；样本量取自摘要/正文。重点 2020–2026。每个场景映射到"软件套件必须交付的可复用工作流"。

---

## 1. 泛癌图谱（队列级 WGS）

| 研究 | 引用 (PMID) | n | 变异类型 | 分析 | 软件 |
|---|---|---|---|---|---|
| PCAWG SBS/DBS/ID | Alexandrov, Nature 2020 (32025018) | 2,780 WGS, 38 癌型 | SBS, DBS, ID | de novo + 修复归因 | 定制（SigProfiler 系），NMF/HDP |
| PCAWG SV | Li Y, Nature 2020 (32025012)；chromothripsis Park, Nat Genet 2020 (32025003) | 同队列 | SV（16 重排类） | SV 提取 | 定制 |
| 乳腺癌 560 WGS（奠基） | Nik-Zainal, Nature 2016 (27135926) | 560 | SBS, ID, SV, CN | de novo + 克隆计时 | 定制 |
| Hartwig 转移 | Priestley, Nature 2019 (31645765) | 2,520 | SBS, ID, CN, SV | 拟合 + 治疗关联签名 | 定制 |
| CN 签名 (TCGA) | Steele, Nature 2022 (35705804) | **9,873**, 33 癌型 | CN | de novo CN 提取；框架推广到 WGS/WES/scDNA/SNP6 | 定制（后为 SigProfiler CN 工具） |
| 英国 GEL SBS/DBS | Degasperi, Science 2022 (35949260) | **12,222** WGS | SBS, DBS | 拟合 + de novo；common/rare 框架；amber/red QC | SigProfiler 套件 |
| SV 签名 (100kGP) | Everall, Nat Genet 2026 (41688639) | **10,983** WGS, 16 癌型 | SBS+DBS+ID+CN+**SV（首个参考集）** | 五类 de novo；134 签名、26 个 COSMIC 新增 | SigProfiler + 定制 |
| 100kGP 精准肿瘤 | Sosinsky, Nat Med 2024 (38200255) | 13,880 实体瘤 | 全基因组 | 签名/CN 特征 + 临床结局 | 机构流水线 |
| 儿童图谱 | Ma X, Nature 2018 (29489755)；Gröbner, Nature 2018 (29489754)；**Greenhalgh, Cancer Cell 2026 (41825442)**：1,616 儿童对 2,203 成人，**10 个 SV 签名**，SV7=RAG 介导 | — | SBS, SV | SV 签名提取 + 易感背景 | 定制 |

**隐含工作流 —— "atlas 模式"**：五类变异摄入 → 标准化矩阵生成（SBS96/DBS78/ID83/CN/SV）→ QC 门控（纯度、FFPE/oxoG 标记）→ de novo vs 参考 refit 混合 → common/rare 分类 → 逐样本活性矩阵 + 临床特征关联。Everall 2026 使 SV 参考集成为一等公民 → **msuiter 应将 SBS/DBS/ID/CN/SV/RNA 作为对称数据类型**。

## 2. 环境/生活方式暴露流行病学

- **烟草**：Alexandrov, Science 2016 (27811275, ~5,243 肿瘤；SBS4 + 剂量调制 SBS5)。Torrens, Nat Genet 2025 (40164736, HNSCC 烟草复杂性、场癌变)。从不吸烟者：Díaz-Gay/Landi, Nature 2025 (40604281, LCINS)。实验性烟草特异亚硝胺：Zavadil, Genome Med 2026 (42393796)。
- **UV/黑色素瘤**：Hayward, Nature 2017 (28467829；SBS7 vs 肢端 SBS38)。
- **马兜铃酸**：Poon/Hoang, Sci Transl Med 2013 (23926199/23926200)；Jelaković, IJC 2015 (25403517)；Lu, Theranostics 2020 (32292497)——**AA 签名定义 UTUC 低风险亚型**（暴露签名即临床分层器）。
- **colibactin**：Pleguezuelos-Manzano, Nature 2020 (32106218, 类器官→SBS88/ID18)；Dziubańska-Kusibab, Nat Med 2020 (32483361, IBD)；van Boxtel/Rosendahl Huber, Cancer Cell 2024 (38471458)；Cornish, Nature 2024 (39112709, 2,023 CRC，colibactin 与早发性 CRC)；Díaz-Gay, Nature 2025 (40267983, CRC 地理+年龄变异)。
- **Mutographs（地理病因）**：Senkin, Nature 2024 (38693263, 肾癌)；Van Loon, CEBP 2023 (37505926, 东非 ESCC)；Huang, Cancer Discov 2026 (41532847, 胃肠化生)。
- **酒精（临床前）**：Chavanel/Zavadil, Cell Biol Toxicol 2026 (42321443, 大鼠多器官)。
- **人工伪迹作为"暴露"**：福尔马林 Guo, Nat Commun 2022 (36068219)；FFPE WGS Basyuni, Nat Commun 2024 (39231944)；FFPEsig Methods Mol Biol 2025 (40779107)；Excerno J Comput Biol 2023 (36322906, 签名式 FFPE 过滤)；oxoG Costello, NAR 2013 (23303777)；综述 Chavanel 2024 (39216514)。

**隐含工作流 —— "暴露归因模式"**：暴露签名参考面板 refit（SBS4, SBS7/38, SBS22, SBS24/88, SBS32, SBS31/35, formalin/oxoG）→ bootstrap CI → 与暴露元数据/地理/年龄关联检验 → 队列地图。**要求：暴露参考面板 + 伪迹优先 QC（amber/red 式分级）**。

## 3. 治疗签名与治疗史解卷积

- **替莫唑胺（SBS11；MMR 失效→SBS1/6+ID1）**：Hwang, NAR 2025 (39656916)；Yaacov, Cells 2025 (41511341 综述)；panel 可行性 Kim, Pathobiology 2026 (42412714)；纵向 IDH 胶质瘤 Chowdhury bioRxiv 2025 (40791422)。
- **铂类（SBS31/35 + SV/CN 疤痕）**：Loveday, Nat Commun 2020 (32366847, 睾丸)；Tsang, npj Precis Oncol 2023 (36964191, HRD 签名与铂时长)。
- **5-FU**：Christensen, Nat Commun 2019 (31594944, 特征 T>G)。
- **硫嘌呤（SBS32）**：Li B, Blood 2020 (31697823, 复发 ALL)；Van der Ham, Haematologica 2025 (40371888)；Brown bioRxiv 2025 (40568177, 睾丸 GCT)。
- **放射**：Behjati, Nat Commun 2016 (27615322)；Sherborne, Cell Rep 2015 (26344771)；Davidson, Sci Rep 2017 (28794481)；Daino 综述 Biology 2025 (41007286)；Mossanen, Eur Urol 2022 (34953602)；核试验退伍军人 PLoS One 2026 (42378240)。
- **治疗史解卷积**：Mendelaar, Nat Commun 2021 (33495476, 转移性 CRC——既往化疗可从签名检出)；Brady 综述, Trends Genet 2022 (34483003)。

**隐含工作流 —— "治疗法证模式"**：治疗参考集拟合（SBS11/25/31/32/35/36 + 治疗 ID/SV 模式）→ 与治疗记录验证 → 克隆计时（克隆=治疗前、亚克隆=治疗中）→ 纵向复发对差异。**无主流工具提供治疗史报告模块——差异化机会。**

## 4. 生殖系/修复缺陷综合征与 HRD

- **POLE/POLD1（SBS10a–d, SBS14/28）**：van Gool, CCR 2015 (25878334)；**Davila, BMC Med Genomics 2021 (34158040)——RNA-seq 签名检出 POLE 超突变**；Mur, Genet Med 2020 (32792570)；Cui, Diagn Pathol 2023 (36765365)。
- **MMR/MSI**：**Chung, Cancer Discov 2021 (33355208)——聚合酶 vs MMR 的 MSI 签名区分（含 indel）经典**；Lynch 正常上皮 Lee BCH, Nat Commun 2022 (35581206)；Martin, HMG 2024 (39180486)。
- **MUTYH（ID 签名）**：Robinson, Nat Commun 2022 (35803914)；**Georgeson, Nat Commun 2022 (35668106)——仅凭肿瘤签名识别双等位 MUTYH CRC（诊断级用例）**。
- XP/NER：Badja, Cell Rep 2024 (38805398)；BRCA1 切口签名 Feng, Nat Commun 2022 (35879372)。

**HRD 工具格局**：
- **HRDetect**（Davies, Nat Med 2017, 28288110）：WGS 输入（SBS3+ID6+SV3/SV5+HRD-LOH）→ 校准概率。WGS 研究金标准（SCAN-B Staaf 2019 31570822；Banda CCR 2026 42201779；Davies HR Commun Med 2026 41699108）。
- **scarHRD**（Sztupinszki, npj Breast Cancer 2018, 29978035）：CN only（HRD-LOH+LST+TAI）→ 数值分。临床研究采纳最高。
- **CHORD**（Nguyen, Nat Commun 2020, 33149131）：SV/CN 特征随机森林 → BRCA1 vs BRCA2 型 HRD 子型；WES 友好。
- 对比证据：Sztupinszki CCR 2021 (34380641)；**Nacer, Breast Cancer Res 2026 (42351273)：7 方法 vs FDA 检测不一致是活问题**；Fortuno, EBioMedicine 2026 (41797047, HRD 辅助 BRCA1/2 VUS 分类)；RNA-based Brown, JCO PO 2023 (38061006)；Corti, npj PO 2024 (39402170)；Zhao CCR 2017 (29246904)；Chopra Nat Commun 2020 (32471999)。

**隐含工作流 —— "HRD 评估"**：SBS3/ID6/SV3+SV5 拟合 + LOH/LST/TAI + CHORD 式 SV 特征 → 集成判定 + 置信度 → 报告（HRD 状态、BRCA1 vs BRCA2 倾向、PARPi/铂意义、生殖系佐证）。**临床需求最大的复合物，2026 年对比显示工具分歧未解——msuiter 集成+不确定性实现即插即用。**

## 5. 临床决策与生物标志物

- **ICI 响应**：Litchfield, Cell 2021 (33508232)；APOBEC+TMB 尿路上皮 Natesan, Front Oncol 2022 (35321431)；**Yaacov, ESMO Open 2026 (42378718)：APOBEC 签名预测 TMB-low NSCLC 的 ICI 获益（独立于 PD-L1）**；Chumsri, JNCCN 2020 (32380464)；肺腺癌脑转移风险 Li Q, Transl Oncol 2024 (38402722)；CHIP TET2 与免疫治疗 Rondeau, Cancer Res 2026 (41218172)。
- **预后**：骨髓瘤 APOBEC 与不良易位 Walker, Nat Commun 2015 (25904160)；泌尿肿瘤 Karihtala, Neoplasia 2023 (37678146)；早发乳腺 Basmadjian, Genes 2024 (38790221)；膀胱腺癌 Yang, J Pathol 2024 (38180342)；**CN 核型顺序与预后 Watkins, Nature 2020 (32879494)**。
- **签名作为诊断线索**：MUTYH (35668106)；AA-低风险 UTUC (32292497)；POLE 超突变子宫内膜管理 (25878334)；panel 签名性能 Lawrence, APLM 2021 (33571361)。
- 药敏：Levatić, Nat Commun 2022 (35614096)。报告框架：van de Haar, Ann Oncol 2024 (39112111)；Black, Lancet Oncol 2025 (41072453)。
- 淋巴系 AID：Kasar, Nat Commun 2015 (26638776)；Maura 实践指南 Nat Commun 2019 (31278357)。

**隐含工作流 —— "生物标志物模式"**：单样本 refit + 不确定性 → 标准化生物标志物调用（APOBEC 活性、HRD 复合、ID 签名 MSI、UV 载荷、时钟暴露）→ 结局建模表。**阴性/混合结果要求报告 CI 与预注册签名定义。**

## 6. 正常组织、体细胞嵌合与克隆性造血

- 皮肤 Martincorena Science 2015 (25999502)；食管 Science 2018 (30337457)；结肠 Lee-Six Nature 2019 (31645730)；IBD 结肠 Olafsson Cell 2020 (32697969)；子宫内膜 Moore Nature 2020 (32350471)；胃 Coorens Nature 2025 (40108450)；膀胱 Lawson Science 2020 (33004514)；慢性肝病 Ng Nature 2021 (34646017)。
- 血液/CHIP：Bick Nature 2020 (33057201, 97,691 基因组)；Fabre Nature 2022 (35650444, CHIP 纵向)；Moore Nature 2021 (34433962)；淋巴细胞 Machado Nature 2022 (35948631)；AML 风险 Abelson Nature 2018 (29988082)；9/11 应答者 Verma, Cancer Discov 2025 (41031953)。**CHIP 无独立"CHIP 签名"被正典化——正常造血由时钟 SBS1/5 族主导，研究以克隆特异谱处理。此为 msuiter 机会。**
- 嵌合/神经元/肌肉：SMaHT Coorens Nature 2025 (40604182)；Lodato Science 2018 (29217584)；Miller Nature 2022 (35444284)；心肌 Choudhury Nat Aging 2022 (36051457)；皮质发育畸形 Chung Nat Genet 2023 (36635388)；单神经元 indel Luquette Nat Genet 2022 (36163278)。
- 癌前病变：胃 IM Huang 2026 (41532847)；乳腺癌前 Chmelova, Nat Commun 2026 (42156386)。

**隐含工作流 —— "低突变计数模式"**：50–1,000 突变/样本；克隆/集落的层级池化估计；时钟 vs 超额分解；肿瘤-正常活性对比；克隆谱系感知拟合（TrackSig 式, 32024834）。

## 7. 细胞系、类器官、QC

- 细胞系 Giacomelli, Nat Genet 2018 (30224644, CCLE TP53/APOBEC)；药敏 Levatić 2022 (35614096)。
- **体外暴露筛选：Kucab, Cell 2019 (30982602) 环境诱变剂签名大全——暴露 refit 的基础**；黄曲霉毒素 Huang, Genome Res 2017 (28739859)。
- 类器官 colibactin van Boxtel 2024 (38471458)；XP iPSC 2024 (38805398)。
- QC/伪迹：amber/red 分级 (35949260)；oxoG (23303777)；福尔马林 (36068219; 40779107; 36322906)；FFPE 大规模效用 (39231944)；固定替代 Berrino, Lab Invest 2024 (38345263)。

## 8. 单细胞、超低输入、ctDNA

- 单细胞：Zhang, Nat Protoc 2024 (37996541)；PTA 工具箱 Middelkamp, Cell Genom 2023 (37719152)；神经元 (36163278)；Satas bioRxiv 2025 (40060559)。scDNA 签名仍被扩增错误/等位基因丢失主导——论文在队列/池化层面拟合。
- ctDNA：**Wan, Nat Commun 2022 (35999207, 低覆盖 WGS cfDNA 全基因组签名)**；Hollizeck, Nat Commun 2024 (39543119)；Chabon, Nature 2020 (32269342)；Nordentoft, Eur Urol 2024 (38811314)；Adalsteinsson, Nat Commun 2017 (29109393)；**cfDNA CN 签名 vs ICI 耐药 Front Oncol 2026 (42601918)**。

**隐含工作流**：超低计数/低覆盖模式：QC 感知计数、灵敏度界（多大 N 才可信）、纵向活性追踪、cfDNA CN 签名支持。

## 9. RNA-seq 签名

- **IMAPR**：Tang, Commun Biol 2024 (38783092, TCGA 级 RNA 体细胞突变发现)；OncoDB 2.0 NAR 2025 (40995640)。
- 前驱：Davila 2021 (34158040, RNA 签名检出 POLE)；Jessen, BMC Med Genomics 2021 (33648520, tumor-only RNA TMB+签名)。
- **RNA-SBS**（COSMIC v3.5 起）源自 TRACERx：Martínez-Ruiz, Nature 2023 (37046093)。
- RNA-based HRD：Brown 2023 (38061006)。

**隐含工作流**：RNA 突变调用 → RNA 伪迹感知（G>A/C>T 偏斜、RNA 编辑）拟合（DNA 派生 + RNA 特异参考集）→ DNA-vs-RNA 一致性报告。**数以千计的 RNA-seq-only 队列是巨大未满足需求。**

## 10. 非人类/跨物种与非癌

- 小鼠：**Riva, Nat Genet 2020 (32989322, 已知人类致癌物的小鼠签名谱——COSMIC 小鼠集之基)**；Connor, J Hepatol 2018 (29958939)；Xu, Cell Rep 2025 (40638383)；Smith-Roe, EMM 2026 (42277565)；Ohno, Genes Environ 2025 (41131588)；Gurevich bioRxiv 2026 (41959104)。
- 大鼠：乙醇多器官 (42321443)。酵母：Loeillet, PNAS 2020 (32968016)。犬：Hwang, Gene 2026 (42342053)。综述：Daino 2025 (41007286)。

**隐含工作流 —— "临床前/毒理模式"**：非人类基因组上下文（mm10/rn6/canFam）、物种参考集、暴露筛选评分（超越 Ames 的遗传毒性排序）、跨物种签名匹配。

## 11. 软件生态使用模式与痛点

**应用论文实际在用什么**：SigProfiler 套件（MatrixGenerator: Khandekar, BMC Genomics 2023, 37605126；Extractor: Islam 2022, 36388765）主导高调 WGS 图谱；deconstructSigs (26899170) 主导旧/临床 WES-panel；MutationalPatterns (29695279; 更新 35168570) 主导 R/Bioc 正常组织与非人类研究；sigminer/sigflow；MuSiCal (38361034) 新锐；mmsig——血液肿瘤拟合标准（Maura 2019, 31278357 实践指南：误归属、局灶超突变过判、过拟合）；TrackSig (32024834)；TensorSignatures Vöhringer, Nat Commun 2021 (34131135)；Pollock (35603231)；MuSiCa web (29898651)；SigFormer bioRxiv 2026 (41648438)；Palimpsest (FunGeST)。

**门户/流水线**：mSigPortal（NCI DCEG; CBIIT/nci-webtools-dceg-mSigPortal）；MutSpec Galaxy (27091472)；OncoDB 2.0 (40995640)；**nf-core/tumourevo（唯一带签名模块的 nf-core 流水线；无专门的维护中 nf-core 签名流水线）**。

**痛点文献（机会清单）**：Medo 2024 (39487150)；Jiang 2024 (39910776)；**变体调用器依赖 bioRxiv 2025 (41427300, Alexandrov 组)**；概念警示 Koh, Nat Rev Cancer 2021 (34316057)；领域综述 Steele, J Pathol 2022 (35420163)。

1. 小队列与 panel 的 refit 歧义与过拟合 → 原则性不确定性（CI、LRT、自适应先验）应为一等输出。
2. 变体调用器/矩阵生成依赖 → 版本化、可测试的 SBS/DBS/ID/CN/SV 矩阵构建器。
3. 多类支持碎片化 → CN/SV 需要独立工具链；Everall 2026 要求统一 SV 参考。
4. COSMIC 版本漂移 → 参考集必须版本化、捆绑、可 diff。
5. QC 伪迹临时处理 → Excerno/FFPEsig/amber-red 逻辑应内置过滤器。
6. 非标准基因组（小鼠/大鼠/犬、非规范 contig）→ Rust mmap 基因组读取让任意参考基因组平凡化。
7. Panel/WES/低覆盖 → 三核苷酸覆盖度校正与灵敏度界全面缺失。
8. 可复现端到端流水线 → 无维护的 nf-core 模块；每篇图谱论文自带胶水。Rust/R 混合 + CLI + R 绑定 + 工作流模板正好补位。

---

# Top-10 交付工作流（按论文/影响价值排序）

1. **临床 HRD 复合报告** — SBS3/ID6 拟合 + HRD-LOH/LST/TAI + SV 特征（CHORD 式）→ 集成 HRD 判定 + 不确定性 + BRCA1-vs-BRCA2 倾向 + PARPi/铂文本。理由：临床需求最大、FDA 检测不一致未解 (42351273)、支持 WES/WGS。
2. **临床 WGS/tumor-only 签名报告（atlas refit）** — common-vs-rare refit、amber/red QC、伪迹清除、可药性注释（38200255; 35949260 模式已成 NHS 级标准）。
3. **暴露归因与流行病学模块** — 捆绑暴露参考面板（烟草/UV/AA/colibactin/铂/硫嘌呤/福尔马林）、病例-对照检验、地理/年龄/生活方式映射（38693263; 40267983; 40604281; 37505926）。
4. **五类联合提取（SBS+DBS+ID+CN+SV）+ 版本化参考集** — Everall/Steele 图谱模式；无单一工具端到端覆盖五类；SV 参考全新、论文级。
5. **Panel/WES 修复缺陷诊断（MSI/MMR、POLE、MUTYH）** — ID 签名 MSI 分类、SBS10/POLE 检出 + 灵敏度界（33355208; 35668106; 25878334; 33571361）。FFPE panel 是最大临床样本池。
6. **治疗史法证与纵向复发对模式** — 治疗参考集 + 克隆计时 + 纵向差分（31594944; 33495476; 31697823; 40371888; 40791422; 32024834）。近零竞争、高新颖度。
7. **正常组织/癌前低计数模式** — 层级池化拟合（50–1,000 突变）、时钟 vs 超额分解、肿瘤-正常对比（40604182; 40108450; 41532847; 35948631; 35581206）。SMaHT/癌前浪潮加速中。
8. **RNA-seq 签名模块** — RNA 感知调用 + RNA-SBS 参考（COSMIC v3.5）+ DNA-RNA 一致性（38783092; 37046093; 34158040; 33648520）。
9. **ctDNA/低 VAF 液体活检模式** — 灵敏度界约束的签名存在性检验、低覆盖 WGS 支持、cfDNA CN 签名（35999207; 39543119; 42601918; 32269342）。
10. **临床前/毒理与跨物种模式** — 任意基因组（小鼠/大鼠/犬/酵母）、物种参考集、体外暴露筛选、跨物种匹配（32989322; 30982602; 28739859; 42321443; 42277565）。

**横向使能件**：版本化捆绑参考集 + diff；bootstrap/CI 原生 API；内置 QC 伪迹过滤；panel 灵敏度界；一键 R/CLI/Nextflow 接口（nf-core 今日所缺）。
