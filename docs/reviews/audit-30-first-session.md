# audit-30 新手前 15 分钟外审（S74/audit-29 后无上下文复核）

背景：对"首次会话前 15 分钟"镜头做无上下文外审——引导、节奏、首夜
存活、软锁点。结论 **HOLD（1C + 多项 M/L）**，全部落地修复于本批
（S75 first-session hardening），smoke 835/0。

## 外审发现与处置

| 级别 | 发现 | 处置 |
|---|---|---|
| C1 | **任务 1 软锁**：kinbox 要 4 流明石，但前期零产出——化石床限 zone≥2、碎石机要 kinbox+水系、钓竿要流明石、藏宝图是下游循环；商人又晚又随机 | 新手包改为 3 精灵球 + 4 流明石（恰够 kinbox）；岩石/金矿/煤矿采集 12% 掉流明石碎片——可再生、不喂祭坛经济 |
| C2 | 首夜约 130 真实秒即至——教学弧线塞不进两分钟白昼 | day==1 时钟半速，首个黄昏 ~4 分钟 |
| M | 新玩家要在 8 格外找首只野生 kin——空手开局靠运气 | `spawn_wild(true)` 仅在 `place_pois` 播 3 只 zone-0 温顺种进出生环（4.5-7.5 格，可见半径内） |
| M | 首个基地刚立起就可能吃突袭 | 首个 kinbox 落地 `raid_t = max(raid_t, DAY_LEN+60)`——一整个白昼宽限 |
| M | 死亡掉落物 600s 衰减——跑不回尸体就永久丢包 | corpse bag `mine` 旗免衰减，随存档往返（`"m"` bool 校验）；死亡日志明示墓碑+M 键 |
| M | 单人草床白天可睡——与来客规则不一致且跳时钟 | 主机侧 `straw_bed` 也走 `is_night()` 门，提示 "It's not night yet" |
| M | 有存档时点 NEW GAME 直接覆盖——无确认 | `new_game_armed` 两步确认：行变红字 "SURE? this overwrites your save"，碰其他行即解除 |
| L | 提示系统不教采集/造价/图鉴/篝火备夜 | 新提示 chop（采集动词）、kinbox（造价 4流明+6木+6石）、guide（N 开手册）、dusk（日落备篝火/草床）；night 提示从"带火把"改为"靠篝火/火系"——旧文案误导（新手火把本是幽灵物品行） |
| L | 帮助覆盖层无 GUIDE 行 | 补 GUIDE n 行 + 滑翔翼/病药行；卡片高随行数自适应（原 8 行已溢出 96px 壳） |
| L | 建造栏 `cost.left(9)` 把配方截成乱码 | 选中行头行显示全名全配方；缺料行整行淡红 |
| — | 顺带存量 bug：新手包 "torch" 不在 ItemData——幽灵物品行 | 从新手包移除（torch 本是结构 id，物品表无此行） |

## 设计保留（审后不改为佳）

- **睡眠不回饥饿**：过夜不喂食是生存压力设计，非缺陷。
- 任务绳回看即付、捕捉反馈给赔率、zone-0 夜兽被动——外审认可的
  既有强项，未动。

## 回归覆盖（tools/smoke_test.gd S75 块）

- `grant_starter_kit()` 抽出成函数：新手包流明石 ≥ kinbox 流明石价
  （grant=4 cost=4）、3 球。
- 可再生碎片：同格 600 种子观测——hit/miss 两侧都出现。
- day-1 半速钟：`d1=0.0250 d4=0.0500` 精确二倍关系。
- 主机草床：白天拒（"It's not night yet"）、夜间睡到 6 点。
- corpse bag：mine 旗 spawn→700s 免疫衰减→`save→load` 旗仍在。
- 出生环：`spawn_wild(true)` 后 8.5 格内新增野生 ≥1（实测 ring=3）。
- 首 kinbox：`raid_t` 拉到 DAY_LEN+60。
- 提示 cond：kinbox（无基地时）/dusk/night（无篝火）/guide（t>30）
  逐条布景断言。
- 标题确认：armed→他行解除→重 armed→确认进 play（在 launch sweep
  真链路上跑）。

## 实拍证据（tools/shot_s75.gd → /tmp/plg-s75-*.png）

- spawn：出生屏内 3 只温顺 kin + 提示栈 + drift lumenite 进包日志
- buildbar：头行 "(placing: Kinbox — 4 Lumenite Shard, 6 Wood, 6
  Stone)"，缺料行淡红
- help：10 行全在卡片内，GUIDE/GLIDER 行可见
- confirm：标题第二行变红 "SURE? this overwrites your save"
