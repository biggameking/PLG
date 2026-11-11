# Style DNA: Halftone Field Dossier · 半调野战档案

> 来源研究对象：coo.mx《COO · Covert Ornithological Operations》(Yegor Sak, 2026-11-05 公开)
> 研究日期：2026-11-10 · 分析人：Devin · 状态：**provisional → 已对 4 个独立证据族交叉验证**

开发者自述配方（AUTOMATON 访谈引用）：
> "a full 3D model of Toronto drawn as a **living comic book**, in **bold ink lines,
> pastel cel shading and halftone dots**"（活漫画书 = 粗墨线 + 粉彩赛璐璐 + 半调网点）

本文件是可复用的视觉语法，不是 COO 的复刻授权。角色、地名、Logo、文案均属隔离区
（见 §8），可移植的只有机制。

---

## 1. 证据清单（4 个独立族）

| 族 | 内容 | 采集方式 | SHA-256 (前16) |
|---|---|---|---|
| F1 直采 | 加载序列截图 ×16（SwiftShader 无头 Chrome，1600×900）| 2026-11-10 本机 puppeteer | `9fb37c7fb94da5cf` |
| F2 媒体 | 实机截图 ×3（AUTOMATON 报道图，1733×900 / 1080×563）| 公开新闻图床 | `f9477d553498e845` `dc3ba676e9d60820` |
| F3 代码 | `index-CLihewBS.css`(137KB,全 token)+ `index-C1NKrRwQ.js`(1.27MB，内含 28 个 `Dt()` 渲染调参注释）| 站点静态资源 | `6eb845fb422a592d` `5c6324be7b8bb66e` |
| F4 陈述 | 开发者推文引用 + 两家媒体报道 | webfetch | — |

参考图版（仅内部研究，勿进 build/分发）：`ref-loading-screen.png`、
`ref-ingame-street.jpg`、`ref-ingame-air.jpg`、`token-sheet.png`（自绘）。

---

## 2. 宏观语义

**载体隐喻**：1950–60 年代旅行海报 × 冷战间谍实地档案 × 周日报纸漫画。
整个产品被包装成一份机密 dossier：加载 = "打开 field file"；章节是档案条目
(WAKE / CITY / STREETS / PEOPLE / P-7 / OPTICS / FOCUS / RADIO)；NPC 对讲机是个
贴了 "ASSET CONDUCT" 标签的无线电盒；小地图是圆形纸上舷窗；任务卡是带复选框的
表单；电池条是印刷条纹；命中反馈是 "paper flash" 纸闪。

**情绪**：俏皮特工 + 印刷品的温度。自嘲公文腔文案本身就是美术资产
（"Your equipment is very modest. This is not a judgement."）。

**为什么读得顺**：所有层级共享同一套印刷语法——世界是"画出来的城市"，
UI 是"钉在画上的纸件"，连发光都不是光晕而是同色半调点环。没有一个元素
逃离"印刷品"这个物理隐喻。

---

## 3. 轴级 Style DNA

### 3.1 线稿 ink（第一公民）
证据：`Dt("ink*")` 旋钮注释 ×7 + 截图目检。置信度：高。

- 墨 = 暖调深蓝黑 `#1c1a2e`，**绝不纯黑**；亮主题 UI 同样用它。
- **线宽分级制**(inkWeight)：外轮廓最重 > 投影缘 > 内褶最细；背光面线更重、
  强光处线更细、随距离淡出（主线 ~650m、褶皱 ~200m 消隐于霾色）。
- **褶皱阈值 40°**(inkFold)：两面夹角 ≥40° 才画褶线，之下 10° 内渐隐——
  低模曲面近看不会变线框图。
- **线稿抖动**(inkWobble)：每 0.1s 重绘 ±0.2px 抖动 → 手绘"煮沸"感（boil)。
  这是"活"漫画书的核心动词——静态画面在微观上永远不稳定。
- **实心墨闭合**(inkBlacks)：最深遮蔽处直接涂死成墨块，中层用排线，
  不用渐变。
- **材质分类**：树冠等 outline-only 类（`userData.ink=3`）只画外轮廓不画内褶。

### 3.2 半调 screentone（签名机制）
证据：CSS `radial-gradient` 点阵 + `Dt("tone*")` + F2 建筑阴影面。置信度：高。

- **贴表面而非贴屏幕**(toneStick=1)：网点跟着表面走，是"印在物体上的网"。
- **暗部 = 网点密度，不是明度下降**(toneDark)：背光面/底面向 shade 色 + 墨色
  加深，通过点的覆盖率表达深浅（实测：点 1–1.4px、网格 4–8px、墨 α 0.10–0.32)。
- **遮蔽 relief = 网点**(inkReliefReach)：墙角、物底的 AO 也用点，收集半径
  ≤4m、320m 外消失。
- **发光 = 同色点环**(frameHalo)：灯/氖/车灯发光体不做柔光晕，做"自己颜色
  的半调点环";45m 内全 halo，更远退化为点（远灯保持点状）。
- **纸纹**：`repeating-linear-gradient(0deg, ink6% 1px, transparent 4px)`
  细横线 + 点噪，给所有纸件。

### 3.3 色彩（粉彩纪律）
证据：CSS 变量全表 + 截图中位切量化。置信度：高。

- **底**：纸奶白 `#f4ecd8` / 暖白 `#fffdf6`——世界和 UI 都坐在纸上。
- **中调粉彩**：天青 `#8fd3e6`、沙 `#e8cf9a`、赭 `#d9a441`、陶土 `#c8643b`、
  珊瑚 `#f08a6b`、玫瑰灰 `#e3a79a`、砖红 `#a05c4b`、鼠尾草 `#9fbf8f`、
  苔绿 `#6f9a5e`、混凝土 `#ddd5c4`——大面积、低-中饱和。
- **高饱和小面积三件套**：信号橙 `#ff6a13`、印刷红 `#e8413a`、电讯青
  `#74e6ff`（夜间/扫描主题下青是主墨）。点缀面积 <5%。
- **阴影偏紫不偏灰**：紫丁香 `#8c7bb8` → 紫罗兰 `#5b4a8a` → 深靛 `#1c1a2e`。
  暗部是"紫化的本色"，这是漫画感的关键色相纪律。
- **远景守色相**(tonePlanes)：距离衰减用"保持色相的平色层"，不用
  往灰/雾色的阶调渐变。

### 3.4 形状语言
- 低多边形 + 几何概括：树冠 = 纸团状秋色块簇（只外轮廓）；云 = 三段式平形
  (lit / shade / flat underside 三调，`skyCloudLight`)；建筑 = 大色块 + 墨棱。
- **贴上去的标签**：人名条 "GRAHAM PIKE"、提示 "▼ 7 M DOWN"、警戒
  "RECORDED" 都是带小尾巴的纸质标签，不做世界内发光牌。
- 云的高空层 `skyHigh`：第二层更高更慢的细描云（卷云跟随天气）。

### 3.5 印刷后期 frame
- **套准错位**(frameMis/frameDrift)：色版向画面边缘错位 ~1px@1080p——
  模拟真实印刷的 misregistration，边缘轻微"叠影"。
- **速度线/撞击**(frameLines)：速度线是画出来的线，受击是 "paper flash"——
  反馈特效也是印刷语汇。
- **金色时刻**(skyBands)：低空色带经点屏阶调化（dusk/dawn 专用）。
- **光束**(frameShafts)：低日斜光是平楔形光片，非体积雾。

### 3.6 UI / 版式（纸件系统）
- 卡纸件：奶底 `#f4ecd8` + 2.5px 墨边 + **3–5px 硬偏移投影 0 模糊**
  (`--drop: 3px 3px 0 #04102a`)。
- **微倾角**：元素带 −0.2°~±0.6° 随机旋转（`--r`)，像手钉上去的纸片。
- **表单美学**：复选框、进度条 = 斜纹警示带
  (`repeating-linear-gradient(-45deg, ink 6px, cap-2 6px 12px)`)、裁切角标、
  骑缝虚线。
- **四层字体制**：Bangers（漫画拟声词/大数字"53%")→ Comic Neue（手写对白）
  → Courier Prime（打字机档案文本）→ IBM Plex Mono（技术遥测/HUD 数字）。
  每个字体有明确角色，不混用。
- **罗盘带**：顶部白纸条带印刻度（N/015/NE/030…)，小红菱标指北。

### 3.7 动态（"活"的来源）
- 线稿 10Hz 抖动；云形 ~2.5min 慢变；星 = 画点四芒、阶梯式闪烁（`skyStars`);
  落叶/沟纸随风（`natureLeaves`);UI 微交互 0.08–0.12s。
- 昼夜双主题：`--paper: #f4ecd8` 纸面 ⇄ `--paper: #0c1c3c` 深靛版，
  `--ink: #1c1a2e` ⇄ `--ink: #74e6ff` 电讯青——同一套 token 直接换皮。

---

## 4. 渲染配方重建（从 shipped code 还原的管线）

```
低模几何
 → 分级墨线 pass(轮廓/投影/褶皱@40°阈值/远淡出/10Hz抖动/实心墨闭合)
 → 粉彩赛璐璐填色(lit·shade·flat 三段，云同法)
 → 贴面半调网点(暗部密度+AO relief ≤4m)
 → 保色相远景平色层(非雾灰)
 → 帧后期:1px套准错位→边缘+半调点环halo(45m内)+画线速度线+纸闪
 → 纸件UI叠加(墨边+硬偏移影+微倾角)
```

夜景分支：深靛底 + 暖色墙脚光带 + 灯池光照图（lamp pools) 漫到路面。

---

## 5. 不可移植（隔离区）

多伦多实景地图/建筑布局、P-7 鸽子形象与 COO 标志、"Covert Ornithological
Operations" 文案与任务文本、商标/dress。借鉴 = 机制级语法 + 全新内容。

---

## 6. 对 PLG 的可执行借鉴（2D 俯视 Godot，现状=扁平矢量卡通风）

PLG 现状（`src/hud.gd`、assets):`PressStart2P` 像素字 + 半透明黑条
`Color(0,0,0,0.55)` 底 + 白字；sprites 平色无描线；阴影 blob 灰黑。
与 COO 同为"平色卡通"，机制完全可移植——按投入产出排序：

### P0（低成本高回报）
1. **HUD 纸件化**：`Color(0,0,0,0.55)` 黑条 → `#f4ecd8` 纸卡 + 2.5px `#1c1a2e`
   墨边 + 右下 3–4px 硬偏移影（画两个叠置 rect，无模糊）。菜单行同步。
   文本墨色/深青，数字/警报才用 `#ff6a13`/`#e8413a`。
2. **阴影紫化**：kin/树的落地 blob 由灰黑改 `#8c7bb8`→`#5b4a8a` 方向偏色
   （α 0.3–0.45)；夜雾叠加层已有 `#0.015,0.025,0.05` 藏青——方向一致，保留。
3. **点缀纪律**：全局盘点色板，把高饱和色收敛到 ≤3 个信号色（橙/红/青），
   其余降饱和到粉彩区。现 `#ff5544 #e64533 #e8452f` 三红可并为一红。
4. **字体分层**：PressStart2P 保留作 "sfx/标题"层；数字/遥测可用等宽字体
   （若引入新字体需 import 后跑一次 `--import`，AGENTS 规则7)。

### P1（中成本）
5. **描线分级**:kin 外轮廓加 1.5–2px `#1c1a2e` 描线（f0/f1 两帧同描）;
   大剪影（树/屋/BOSS）外重内细。生成器 `tools/gen_*.py` 里加描线 pass,
   新 PNG 记得 `--import`。
6. **半调补丁**：做 1 张 8×8 可平铺点阵 PNG(dot 1.5px / ink α 20%),
   树冠暗部、屋墙阴面、水面阴处手动点贴几块——"贴面网点"立刻出漫画感。
   远处地块别贴（COO 也是近 320m 内才有 relief)。
7. **标签化交互**:E 交互提示、"RAID IN"警告、捕捉率浮字改成带尾巴的
   纸标签（白底墨边小卡 + 1px 尾巴），别用裸字浮屏。

### P2（风格深化，选做）
8. **线稿抖动**：对描线 sprite 做每 0.1s ±1px 的 UV/位置微抖（ boil ),
   只在近景/选中态开，成本可控——"活漫画"的招牌动效。
9. **金色时刻**:dusk/dawn 把地平渐变换成 3–4 阶色带（守色相），可加
   点屏过渡；低日斜影拉成长平楔形（已有长影系统，换形不换机制）。
10. **套准错位**：受击/警报瞬间把 UI 卡的 CMYK 层错开 1px（画 2 次
    offset 红/青副本）即得印刷错版反馈。
11. **发光 = 同色点环**：篝火/灯/稀有掉落的光晕改"同色半调点环"贴片
    而非 radial 渐变——与现 floaters/drops 体系兼容。

### 反向守则（学了不能丢的）
- 暗部**紫化**，不降明度成灰；远景**守色相**变平色层，不刷雾灰。
- 墨 `#1c1a2e` 暖黑，**永不纯黑**；纸 `#f4ecd8`，不用冷白 `#ffffff`。
- 每个 UI 元素都应是"一件印刷品"；想加光晕时先问"能不能用点环"。
- 文案腔调也是资产：PLG 的 log_msg/floater 若走公文冷幽默，与视觉同源。

---

## 7. 图像生成适配器（provider-neutral recipe)

```
new subject: <your subject>
style: 1950s travel-poster × field-dossier comic print; flat vector cel shading;
bold warm-navy ink outlines, weight-graded (outer heaviest, folds ≥40° fine,
thin in full sun); halftone screentone dots for shade and glow (dots 1–1.4px,
4–8px grid, ink 10–32%); pastel palette on cream paper #f4ecd8; shadows shift
toward lilac #8c7bb8 / violet #5b4a8a — never grey; distance flattens into
hue-preserving planes; sky stepped into flat bands at golden hour; lights ring
with same-color halftone halos; subtle 1px plate misregistration at edges;
paper grain (1px lines, light speckle); UI props as printed paper cards with
2.5px ink borders and 3–5px hard offset shadows, slight −0.2° tilt.
negative: photorealism, soft gradients, grey shadows, pure black, lens blur,
3D-render sheen, brand logos, real city maps, the pigeon character itself.
```

---

## 8. 权利与边界

- 截图/代码仅作内部研究；参考图版不得进商店素材、宣传图或 build。
- CSS/JS 阅读用于提炼机制，不复制其文案与具体实现。
- 开发者 7 天 + 生成式工具流水线完成的背景说明：风格成立靠"克制的一致性
  系统"，不靠资产量——这本身就是最值得学的一课。

## 9. 验收状态

- 图像迁移：**provisional** —— `transfer-mock.png` 用 PLG 风格内容做了机制
  round-trip（墨描线/贴面网点/紫化影/纸件 UI/斜纹条/键帽 chip/带尾标签），
  语法可读性成立；尚非生产资产。
- 可运行 UI:**not evaluated**（目标为 Godot 项目，UI 适配已并入 §6 条款）。
- 游戏资产迁移：**provisional** —— §6 为规范级建议，首个 sprite/UI 落地
  后应回头验证轮廓可读性与色板收敛是否达标。
- 证据完整性：F1/F2/F3/F4 四族独立一致；F3 为确定性一手机制文档。
