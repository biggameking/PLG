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
- 批量映射：`tools/art/mesh_map_gen.py` → `mesh_cfg_gen.py`（生成物，
  勿手改），按 body 套源 mesh 模板+配色派生；`bash tools/art/
  batch_mesh.sh` 全量重渲。**覆盖 116/116**（9 手调含 fenjelly
  +107 生成条目，零 primitive 残余）。
- S101 player 迁移：Alien_Tall（zone_mats 分带裤/夹克/肤、`hat` 配饰
  锚剪影顶、眼用 `eye_abs_z` 显式锚）。教训：
  1. Q 版怪物的"脸"分布在全身——烘培眼球/口腔是**独立网格岛**，
     `strip_islands` 按区域删岛（z_min>0.9 & y_max<-0.15 → 只摘眼球，
     手臂/口腔保住）；口腔腔体留在眼位下方即读作脸（勿当洞补）。
  2. zone_mats 必须 `materials.clear()` 再 append——slot 索引错位会让
     整条配色链偏移一格。
  3. 簇带钳制在某些 rig 把面中夹成真空（Alien: Head≤0.87/Head3≥1.14）
     ——`eye_abs_z` 显式世界 z 逃生口。
  4. player 已进批渲清单（hand 正则按 `# Xxx.blend` 注释解析），
     sprite 像素断言已含 "player"。
- S100 配饰层落地：`render_src_asset.add_accessory()` 以 primitive
  件（crown/halo/horns/crest/fins/mask/wings）骨绑补全源 mesh 缺失的
  身份标志，暖调 hue-shift accent 与 rig_auto 同源派生（暗体种有
  value 下限防吞）。锚定教训（三次返工收敛）：
  1. "剪影最高点"不是头顶锚——抬起的翅膀会占据头列 xy+z；
  2. 骨端坐标也不可信——Wolf 的 Bone.003 在 Idle 姿态下尾端落到
     喉下，face 锚点把角拖到颏底；`head_group_top()` 直接取
     **头骨权重组顶点簇的顶**做颅顶锚，任意 rig/姿态自洽；
  3. 骨绑件必须在**目标帧姿态下**装配——动作驱动前的 rest 姿态算
     相对偏移会被 f0 姿态差拖走（先 assign action + frame_set(f0)
     再 add_eyes/add_accessory）；`real_head_bone()` 按权重投票再
     纠一次名不符的 cfg 骨（Ghost 'Head'→'Body'、Slime→'Head3'、
     Eagle→'Bone.004'）；4. 侧视体型（狼/马/牛）的横向配饰在深度
     轴上不可见——crown/halo/horns 的展开平面转 fwd-z 才能在纯
     侧视读出。10/10 标志放置，smoke 像素钉（scalbeak 冠>6、
     vermtrot 背扇>4）通过。
- S99 扩批补源：cute_monsters 包（CC0）供 Ghost→ghost、
  Alien_Tall→human、Yeti→monkey、Cactus→hedgehog；monsters_basic
  包供 Slime→blob（no_eyes，自带眼材质）。注意该包是 Q 版大头
  风格——human/monkey 用 rot_z≈35° 露出手臂/犄角剪影，正对镜头
  只剩一张脸。Skeleton/Cyclops/Demon 试过不合用（骨头碎片/同样
  大头）；Bat/Dragon 留作未来源。
- 归一化教训（S98c 实战）：bound_box 看不见 modifier 变形——必须用
  evaluated 顶点；烘缩放要**两侧共轭**（骨 rest 矩阵+顶点同烘 k，
  只烘骨骼在 rest-pose 下输出零变化）；子 mesh 的 location 不要动；
  动作 location F-curve 必须**每 pass 同步 ×k**（放循环外会让
  Cat/Dog 类姿态主导 rig 反向发散——姿态位移把网格拉糖稀；
  Blender 5.x 动作结构是 layers→strips→channelbags→fcurves，
  4.x 是 act.fcurves，`_loc_fcurves()` 两侧兼容）；直立头骨
  （Skeleton）侧向向量退化——前向改取模型 -Y；眼位 z 向钳在
  evaluated 包围盒内（风格化 rig 的骨坐标可远超网格；X/Y 暂无钳，
  新源 mesh 接入后必须 x4 目测眼位）。
  迭代归一上限 10 pass，Dog 类强变形 rig 收敛最慢。
- S98 首批网格迁移落地 8 种（scalcrest→Eagle、scalfang→Wolf、
  branpurr→Cat、tidscale→Piranha、piplump→Cow、digsnout→Pig、
  dozantler→Horse、cindpaw→Dog，源见 PROVENANCE.md Vol.2+farm 包）。
  render_src_asset.py 现支持 `mat_map` 多材质、`head_bone` 指定、
  armature 缩放烘焙（transform_apply——不改骨骼数据空间的缩放在
  modifier 下无效）。扩批方法：在 CFG 加条目（材质名映射物种
  palette、头骨、rot_z、action+frames、target_h），渲+post 后必看
  x4 预览再扩。
- 传说种配饰（冠/环/面具/角/冠饰/鳍/背扇）：primitive 路由走
  rig_auto.ACCESSORY 表（10 种），mesh 路由走 cfg `accessory` 字段→
  `add_accessory()`；两者都保证身份标志不落。
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

## S102 环境美术（nature pack → decor）

- `render_decor.py`（静态网格版渲染器：mat_map 重上色→归一到 target_h→
  与 kin 同机位→单帧 512）+ `post_decor.py`（复用 post_kin 链，DIMS 表按
  旧文件尺寸输出——装饰池底锚绘制，尺寸不变=零代码改动）。
- 7 个 decor 全部迁到 Ultimate Nature Pack（CC0，见 PROVENANCE）：
  tree_a=PineTree_2、tree_b=BirchTree_1（White/Black 树皮槽）、
  berry_bush=BushBerries_1、rock/ore_coal/ore_gold=Rock_2 三色变体、
  stump=TreeStump_Moss。
- 坑：旧 Quaternius blend 的节点树是双输出，渲染输出接 BSDF_DIFFUSE——
  给 Principled 设 Base Color 无效。mat() 一律重建干净节点树。
- smoke 新增装饰钉：每个 decor PNG 必须存在、opaque≥40、ink≥2、且
  非全出血（opaque<95% 总像素——全出血=相机裁了网格）。
- 实机证据：`docs/reviews/s102-world.png`（tools/shot.gd play 帧）。

## S103 地砖迁移（程序几何 → tiles atlas）

- `render_tile.py`：factory-startup 起空场景，每 tile 程序化建 slab+细节
  （blades 锥体/flowers 球/ripples+waves 环/stones+clods 球/ridges 立方条），
  dimetric 相机（az45/el30 → 顶面投影恰为 2:1 菱形），kin 同 rig。
- 坑：kin rig 曝光 ≈1.45×——CFG col 必须按目标色 ÷~1.4，否则整体发白。
- `post_tile.py`：裁→cel/warm→64×32→严格菱形 mask（任何超出会渗进邻格）
  →贴进 64×64 cell 上半部；**不打墨描边**（描边=全地图暗格线）。
- `build_tiles.py`：只装 GROUND 16 格 + 仍由 gen_assets 程序画 wall/stair/
  marker（cliff 暗紫是刻意的对比）；manifest 布局与 world_drawer 约定一致。
- smoke 新钉：atlas 每地面格菱形内 opaque≥800 且亮度方差非零。
- 回退路径已堵：`gen_assets.py` 的 atlas() 也加了 `--tiles-legacy` 门
  （audit-55 课的直接应用，不再等审计发现第二遍）。
- 实机证据：`docs/reviews/s103-terrain.png`。

## S104 崖面（wall_*）迁移

- `render_wall.py`：1×1×0.4 立方体、同 dimetric 相机（跟踪点下移 -h/2
  让侧面进帧）→ `post_wall.py`：按 cell→render 线性映射抽两面进
  wall_sx/sy/corner 格（覆盖区=游戏 edge+16px 下落几何），post 里重画
  顶边墨线+淡紫 rim+t∈{5,10} 层理线。stair/marker 格仍程序画（台阶
  平涂更读得清）。
- 实测：顶菱形 x[8,247] y[39,158]，面高 58px（=16cell px×3.72 缩放✓）。
- 坑：SUBSURF 必须先于 DISPLACE（audit-56 已踩过的同坑——直接写对
  别复错）；modifier_move_up 的 while 条件是反的，别用。

## S105a 结构迁移批次1

- `render_structure.py` CFG：id → {build 构件族, h 世界高, ortho, tz
  跟踪点}；构件库 cube/cyl/cone/ico/roof_prism，材质 wood/wood_d/
  stone/iron + emit 火焰/水晶/宝珠。
- 机位与 decor 相同（upright 3/4 ortho），非 tile 的 dimetric——
  结构是竖直 sprite 不是地面格。
- `post_structure.py` DIMS 逐 id 钉输出尺寸（与旧图一致保锚定）。
- 坑：emit>0 的材质在 Standard view_transform 下会过曝变白——
  kinbox 宝珠 emit=1.8 已到边界，别再调高。
