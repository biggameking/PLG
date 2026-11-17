# audit-64 — S110–S112 输入验收链冷审

**Verdict: NEEDS-FIX → 全部落地。** 冷审覆盖 play/loop 双 harness、
export_check.sh、本阶段全部 smoke 新钉、weather 修复与 ROADMAP 声明。

## HIGH — 已修

| # | 发现 | 修法 |
|---|---|---|
| H1 | `loop_walkthrough.gd:237` 孤儿续行（sed 删 DBG 只删了首行）→ **文件无法解析**，提交的 15 门声明对一具坏文件 | 删孤儿行 + 重跑验证 LOOP 0 failures（修复后文件真跑通） |
| H2 | 无任何环节编译 harness 文件——坏文件带证据链混过一个 commit | smoke 新钉 `harness parses:` ×2——`--check-only` 解析失败也退 0，钉按输出文本判（SCRIPT ERROR / Failed to load script） |

## MED — 已修

| # | 发现 | 修法 |
|---|---|---|
| M3 | chip 门 hp0 在 poke 前取样→挥空也过（30→20<30 恒真） | hp0 移到 poke 后读，门改证"打过 20" |
| M4 | kinbox 放置门用全局 `has_structure`，歪到合法格也过 | 改格点严格 `structures.get(cell).id=="kinbox"`（与 bed 门同规格） |
| M5 | `interact()` 尾部全局回退：E 任意点开 kinbox——头注写"near kinbox"，空场 E 永远不报 Nothing；门不能证近身路径 | 删回退（近身路径 862 行已有）——E 开盒现在必须真的站在箱边 |
| M6 | export_check：web `rm -f` 只清 index.html，陈旧 wasm/pck 可满足 bundle 检查；APK 仅查存在；日志有 ERROR 也放行 | 导出前 `rm -f index.*` 全清；APK `unzip -t` 完整性+签名块存在性；每 preset 日志 grep `ERROR:` |

## LOW — 已修/记录

- L7 `is_instance_valid(prey)` 守卫×4（击杀→free→悬空引用崩溃→响亮失败）
- L9 捕获断言收窄为 `prey.mode != "wild"` 直接信号（去同种误捕宽松项）
- L10 facing 再戳注 "(fixture)"
- L11 `_stamp()`：run 起手打 timestamp+git SHA——PNG 可溯产生树
- L8 位移门无方向断言：**接受**——stick 门有 live vec 配套，且击退
  方向与拖拽同向概率低；记录为已知宽松

## 冷审验证为实的项（tried to break, held）

- 全部动词走 `Input.parse_input_event` 真队列；pad B→dodge 是运行时
  `bind_gamepad()` 注入（project.godot InputMap 仅键盘）——B 从
  ui_cancel 正确摘除
- weather 修复正确（Rng 只有 next()，randf 每次必炸）；同级扫描：
  sfx.gd 的 randf_range 在 RandomNumberGenerator 上，不同类
- lightning-rod 基线修复正确；全套件 weather/tod 惯例 save→set→
  restore 无同级裸用
- fixture 纪律：授予物全在"非被测物"上，每个断言动词都要真事件
- 无磁盘残留：两 harness 不调 save_game；smoke 备份+还原真存档

## 验证

- `LOOP: 0 failures`（15 门，修复后文件）· smoke **1002/0/1skip**
  （+2 解析钉）· export_check 0 failures（收紧后三产物全过）

## 流程课

**删调试行用编辑器不用 sed 行删**——多行表达式删首行留孤儿尾；
且"声明证据的脚本本身"必须进解析门禁，否则证据链可随文件腐化
而全链失真。
