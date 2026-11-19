# audit-78 — S125 试玩探针冷审 + 修复轮

**Verdict: NEEDS-FIX → FIXED**（修复轮与 S126 任务 8-9 扩展同批落地）

冷审零上下文复核了 `tools/playthrough.gd`（任务 0-7 链）与 S125 提交 `16b796e` 的证据链。
游戏链路本身判正（每个完成谓词都走真实生产代码），但探针自身有一簇真缺陷——
计时预算在 240tps 下失真、fixture alpha 比注释弱 4-8×、`find_pal` 对 benched
party kin 不可见导致三处 fielding fallback 全是死码。

## 冷审发现 → 处置

| # | 级 | 发现 | 处置 |
|---|---|---|---|
| 1 | MED | `_catch_one` 等待窗 130 帧 ≈0.54s，但 orb 解析需 ~1.8 real-s（~430 帧）——`done` 在成功时也常误判、fixture orbs 过发火 | **已修**：等待窗 130→600 帧 |
| 2 | MED | fiber 诚实车道无 verdict——`_kill_fiber`+fixture 全产 0 也照绿 | **已修**：`_ensure_mats` fiber 分支加 `ok()`（置于 reclaim 之后，防散落误判） |
| 3 | MED | fixture alpha `alpha=true` 设在 `gen_pal`→`setup` 之后——4×HP、1.6×缩放、lv+6 全落空，注释还声称"同 spawn_wild 构造" | **已修**：`_mint_alpha()` 设 flag 后 `apply_bonuses()`+`hp=max_hp`+精灵缩放，lv 10 |
| 4 | MED | `playthrough.gd` 不在 smoke 解析钉列表（audit-64 同类坑） | **已修**：加入 harness 列表 |
| 5 | MED | `player.hp=max_hp` 每挥重置——keeper 不死化，死亡（含 s124 截图里真发生过的 respawn 掉袋）完全无痕 | **已修**：每挥前检测 `hp<=0`，`_keeper_deaths` 计数+打印 |
| 6 | MED-LOW | `find_pal` 只扫 `pals`，benched party kin 不可见——`_kill`/P8/P10/P4 的 fielding fallback 全死码 | **已修**：`send_out(uid)` 直发（内部自处理 bench 查找）；P4 deploy 补 `bench_pal_of` |
| 7 | LOW-MED | fixture 披露不一致：minted sprigmelt 静默、orbs 标签恒打印"+1 fixture orb x0" | **已修**：mint 打印编号、orbs 标签条件化 |
| 8 | LOW | ROADMAP "无箱则永久滞留"失实——实际为 90s 有界抱货+脚边放弃 | **已修**：改为准确描述（90s give-up 机制） |
| 9 | LOW | `messages.size()` delta 永不动（ring 封顶 6）——craft 拒因不可见 | **已修**：直读 `messages[-1]`；修复后立刻在 run3 抓到 "Missing materials" 真因 |
| 10 | LOW | `_fiber_prey` 缺 alpha/boss 排除（其余过滤器都有） | **已修** |
| 11 | LOW | `kin_bed` unlock 未断言（ranch 有） | **已修** |
| 12 | LOW | `s125-elite.png` 缺 `.import` sidecar | **已修**：经 `--import` 生成 |
| — | — | "无 `.git`" 申报 | **误报**：`/tmp/plg_work` 是完整 clone（`git log` 可查 `16b796e`），审计环境误读 |

## 修复轮新抓到的探针缺陷（run 2/3 实证）

- **搬运工散货吞车道**：无 chest 时 hauler 抓掉落→抱 90s→随机处重丢——`_collect_drops` 只扫玩家身边，
  木材车道颗粒无收。修法：`_reclaim_all_drops()`（真实动词）扫全图掉落+`base_to_box`/`deploy_to_base`
  把爪上货回袋（跳过在岗工人）。`_ensure_mats` 每车道后调用。
- **`game.box` 存 Kin 对象非 uid**：`_ensure_mf_pair` 的 `find_pal(box[i])` 崩——party/box 两种迭代形态分别处理。
- **`tick_assign` 抢人**：2s 节拍把空闲 base kin 自动塞进任何空岗位——新部署的 kin 可能先被 auto-seat 到
  伐木场，`assign_worker` toggle 反而把它**摘下**。修 `_post_kin` 双按自修（先摘后挂）+蛋等待环断岗重挂。
- **craft 材料段裸 `_chop_until`**：本地树林砍空时产出 0 无顶账——换 `_ensure_mats` 统一车道。

## 修复轮第三批（S126 随机种子实证）

- **蛋糕就是食物——被育种工人自己吃掉（真实机制浮现，非探针缺陷）**：
  `eat_food_item` 让 hunger>70 的 base kin 从 feed_box/任意 chest 取**最便宜**食物，
  cake.food=80 在箱内无更廉物时就是午餐；而 `tick_ranch` 的 `consume_ready` 一旦落空
  `st["timer"]=0`——60s 产蛋窗被一口吃没，且 `cake_warned` 每轮只闪一次，
  玩家在"我明明放了蛋糕"的错觉里死等。**这是探针照出的真玩法陷阱**：
  育种牧场必须同时备口粮（berry 类便宜粮会先于 cake 被吃）。判定为涌现设计——
  "饿着工人的牧场会偷吃种蛋"是自洽的生存逻辑，不改游戏；探针按真实玩法应答：
  轮询保箱≥1 cake（工人吃一个 hunger-200 约 140s 内不再饿），有界 8 次、逐次打印。
- **`_pair_on_ranch` 人头口径**：两只同性工（如 F 补 M 缺岗）数出 2 但牧场
  `has_m&&has_f` 永假——改按 M/F 双座计数；断岗自愈改为重跑整条
  `_ensure_mf_pair` 车道（roster/box/catch 车道连成员死亡也兜住）。
- **fiber verdict 口径**：袋中为 0 不代表世界无产出（掉落可能卡在 posted 工人
  爪上/结构库/未拾取的地上袋）——判据改为 `item_count + _carried_n + _stored_n +
  _dropped_n` 世界总量，"掉落表坏了"仍会红，散货不再误报；fixture 对
  `pals>=MAX_PALS-4` 的拒铸从静默改为打印（窗口版 ~20min 实时跑会把野生群
  养到 220 上限——fiber 车道的 0/0 双零现场）。
- **实时计时等待按帧计费失配（窗口版实证）**：`t`/breed `st["timer"]`/
  incubate `ready_t` 全部吃真实 dt；探针却按帧数等待——窗口版高帧率下
  16000 帧 ≈60-80 真实秒 < 90s 孵化窗必超时，任务 tick 的 1s 节拍甚至能
  快过一个 400 帧窗。修法：所有实时等待改 `game.t` 秒界
  （breed 150s / hatch 120s / mission 8s），帧数只作防挂兜底。
- **偷吃蛋糕的游戏侧 QoL 修复（不是探针补丁）**：`eat_food_item` 吃蛋糕
  全程静默——新玩家最贵的一件货被工人当午餐零反馈吃掉，配合 ranch 的
  timer 重置形成真 UX 陷阱。现 `eat_food_item(eater)` 在吃到 cake 时
  点名通报（en/zh 双文），smoke 钉 "cake theft is announced" 回归。

## 结论

S125 的 verdict 链有效（全走真动词），但探针工程有"计时语义失配"与"不可见空间"两类
系统缺陷——240tps 下帧预算必须按 real-dt 换算，`find_pal`/`send_out`/`bench_pal_of`
三个查找域必须分清。第三批还证明：**随机种子会替你走没走过的路**——
蛋糕-饥饿-产蛋窗的三角死锁只在工人恰好在产蛋窗内饿过线时才显形。
修复后 headless 完成 **49/49**（任务 0-9 含蛋链+试炼全通），且修复项均被
日志实锤触发（"pair broken → re-run"、"cake 2 restocked"）。

---

## audit-79 — cold review of the S126 final state (post-rescue)

Reviewer: independent subagent, zero context, read-only, pointed at 08b533f.
Verdict: **NEEDS-FIX → all fixed in `8abaf34`**.

### Verified correct
- SHOT_BLOCKERS semantics audited across every los_clear/decor call site —
  no consumer wanted all-decor blocking; movement still uses `blocked()`.
- Every claimed production verb is the real entry point (melee→harvest,
  place_structure, chest_deposit/withdraw, assign_worker toggle, send_out,
  throw_sphere→resolve_sphere, craft queue, deposit_egg, start_gauntlet).
- Fixtures bounded and labeled; waits correctly bound on real `game.t`.
- Cake-theft QoL reachable once per bite, bounded by the message ring.

### Findings fixed this round
| sev | finding | fix |
|---|---|---|
| MED | gauntlet grind print read `gauntlet["wave"]` after await — dict empties on the clearing frame → latent crash | `.get("wave", -1)` / `.get("left", 0)` |
| LOW | sigil debited before start, real use_item debits on success | debit only when `start_gauntlet()` returns true |
| LOW | `_ensure_mf_pair` fixture mint lacked the MAX_PALS-4 guard | guard + refusal print |
| LOW | `_mint_alpha` minted silently | per-mint print |
| LOW | `_fiber_prey` recursion could loop on a sealed prey once blacklist full | return null at cap |
| LOW | `_chop_until` swing budget accumulated across cells | per-cell counter |
| LOW | orb cost table hardcoded in the probe | `_ensure_mats(game.recipe("kin_orb"))` |
| LOW | 3 stale comments after SHOT_BLOCKERS (stump shadow / "same wall set") | reworded in probe + world.gd |
| NIT | reclaim redeployed a carrier after a kinbox-full refusal | gate redeploy on `p.mode == "box"` |
| LOW | `guard_xp` 60 → lv44 not lv45 (24750xp needed) | raised to 65 |

Post-round: headless playthrough **49/49**, smoke **1061/0** (1 seed-skip).
