# 美术移交 — 给并行美术会话

Owner 决定：kin 美术全部归你（并行会话），本会话不再碰视觉面。
以下是当前状态与已知要求，照单接手。

## 你的最新指令（owner 原话转述）

> "风格基本没啥变化……全都是椭球体球拼在一起，看起来很奇怪、很廉价。
> 这是一个立体的真正的模型。能不能把每一个再调整修一下，做得更加
> 好看、有自己的风格。模型的面还要再丰富一下。"

含义：不要再在椭球体堆叠上修参数。要**真正的生物模型**——
你已验证的路线（render_src_asset.py：licensed .blend mesh +
subdivide/displace/bone-parented shell）就是正确方向。对所有物种：

- 每个物种一只真实网格生物，不是 primitive 堆叠。
- 身体应是融合拓扑（metaball→mesh、真网格建模、或 CC0 源模型
  改造皆可），保留脸/眼/喙/配饰等独立特征件没问题——但躯干
  不能是"一串球"。
- 风格统一、有辨识度；80×64 下剪影与脸必须可读。

## 现状（已验证，勿回退）

- 116 物种 + player 均已渲染，`assets/kin/<sid>_f{0,1}.png`
  双帧（运行时 `src/kin.gd` 按此约定加载；player 同款路径）。
- 管线：`tools/dump_species.gd`（**必须走 `SpeciesData.body_of()`**，
  裸 `d["body"]` 会让 15 个核心物种渲错原型、坐骑关系颠倒）→
  `tools/art/rig_auto.py` → `rigs_gen.py`（生成物，勿手改；改完
  `python3 tools/art/rig_auto.py` 必须零 diff）→
  `render_kin.py`（primitive 回退路）/ `render_src_asset.py`
  （mesh 优选路）→ `post_kin.py`（posterize/ink/halftone→80×64+x4 预览）。
- fenjelly 已是 Quaternius Sheep.blend（CC0 24 骨 Idle 动作采样）网格版，
  是当前质量标杆；primitive 栈只作 fallback。
- 传说种配饰（冠/环/面具/角/冠饰/鳍/背扇）在 rig 配饰层，10 种
  ACCESSORY 表在 rig_auto.py。
- `gen_assets.py` 的 kin 写盘已门控 `--kin-legacy`——不要恢复默认。
- `tools/art/render/` 已 gitignore；`farm_animals.zip` 已删（保留解压包
  + License.txt）。

## 硬约束

- 只用 CC0/CC-BY 源；每个外部来源记 `tools/art/PROVENANCE.md`。
- 提交前跑：`godot --headless --path . --import` 然后
  `godot --headless --path . -s tools/smoke_test.gd` 必须 0 failures。
  套件含全物种 sprite 检查（load+opaque+ink 像素）与 scalbeak 冠 /
  vermtrot 背扇的配饰像素钉——**不要放宽断言，改资产不是改测试**。
- IP 安全：`bash tools/check_ip.sh` 必须 CLEAN（Palworld 相关零命中）。
- 游戏内实拍验证：`godot --path . -s tools/shot_kin.gd -- <sid>`
  → `/tmp/plg-kin-<sid>.png`（窗口模式，需有显示环境）。
- `tools/species_dump.json` 里 `body` 字段与 `mountable()` 语义绑定：
  quadruped/deer/cow/boar 可骑乘，渲成什么形态必须自洽。

## 已知弱项（owner 观感 + audit-24 残余）

- 全阵容椭球拼装感（本次返工主因）。
- ~~serpent/blob 系脸偏淡；human 系眼睛 80px 下偏小~~ — S97 已修：
  eyes() 半径全体 +30~40%（human 0.06→0.085、serpent 0.078→0.105、
  blob 0.085→0.115 等），player 同款，116 物种全量重渲过检。
- ~~f1 帧差异幅度小~~ — S97 已修：head_dy 0.04→0.08、fluff_dy 0.06→0.10、
  ear_drop 0.3→0.45。
