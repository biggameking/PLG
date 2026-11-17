# audit-63 — S110 input walkthrough 冷审

**Verdict: NEEDS-FIX** → 全修并复测 19/19

## 发现与修复

| # | 级 | 发现 | 修法 |
|---|---|---|---|
| 1 | HIGH | "felled wood reaches the pack" 空转——hp30 需 3 有效挥击而 atk_cd 0.45s 与空闲帧配速失配，实测 30→10 树从未倒、拾取路径没跑过；且随刷新率漂移 | 预埋 hp=20 + `create_timer(0.55)` 墙钟配速 + 新增 "tree actually fells" 闸；实测 hp30→0、wood 0→4 真收集 |
| 2 | — | **连坐发现真产品 bug**：harness 跑过 120s 时 `tick_weather` 调 `rng.randf()`——自定义 Rng 只有 `next()`，天气 roll 每次到点即炸死、天空永不变化 | `rng.randf()`→`rng.next()`（game.gd:1451）+ smoke 钉 "weather roll consumes rng"（rng.s 推进证明执行体跑完） |
| 3 | MED | `_tap_act` 用 InputEventAction 按名匹配，绕过 InputMap——B/Q/Esc 绑死也不挂 | 全改 `InputEventKey` 真 keycode（B=66/Q=81/Esc） |
| 4 | MED | pad dodge 闸的 `stamina<st0` 半支在游泳落点空转 | 收紧为 `dodge_t>0` 单证 + 瞄准落点改扫非水同架层格 |
| 5 | LOW | ATK fixture：mark 落高差格挡 LOS；mark 被杀时 `mark.hp` 悬空解引用 | 邻格扫同架层非阻；`is_instance_valid` 守卫 |
| 6 | LOW | 杂项：二次 spawn_wild 多余（优先复用）；ui_accept 兜底会误点 "continue"；shot 双前缀；外环不早退 | 全修（兜底改响亮 FAIL；文件名去重） |
| 7 | — | smoke 既有噪音：`"dead=%s" % dead_acts` 空数组展开报格式化 ERROR | `dead=%s` 单参包裹 |

## 审计者验证为真的闸
title 点击→run_click→new_game、长压键→InputMap→行走、LMB→melee→
try_harvest→hp、JoypadButton→dodge、ScreenTouch→touch_verb→atk/
摇杆、orb 消耗链——全部真路径。

## 流程评语
有窗 harness 是对的工具（真帧缓冲+warp_mouse 光标保真），与 headless
smoke 互补而非重复；ROADMAP 唯一失实表述"伐倒拾取入包"已在修复后
变为事实。

## 验证
walkthrough **19/19, 0 failures**（含收紧后全部断言）· smoke **998/0/0skip**
（+weather roll 回归钉 PASS）· audit_data ALL CLEAN
