# audit-62 — S109 tech 树图标 + sync_pos fixture 重写冷审

范围：`304c916`（tech_product/draw_tech 图标列 + sync_pos fixture 世界推导
重写 + shot_tech 证据 harness）+ 同工作区 S109b（decor_delta 分块、
env_sync unl diff-gate、load_from_file→load() 清理）。

**判定：NEEDS-FIX（minor）→ 全部已修。**

## MED

| # | 位置 | 缺陷 | 修法 |
|---|------|------|------|
| MED-1 | smoke_test.gd 7578 | "home blink cooldown bites" 潜在 flake：首个 kinbox 声明若落在 pos_allow(≈6) 内走步幅车道，`blink_t` 不置位→冷却断言必败（fixture 靠近地图左上首对相邻格时发生） | 首个 kinbox 声明前 `pos_allow=0` 强制 blink 车道——与 7599 的 reprime 同构 |
| MED-2 | hud.gd 1853 | `cap=int((rr.size.x-24)/colw)*18`=18 但实际放得下两列（draw break 用 -10/-12 偏移）→ tech_scroll 钳到 50 而非 34，尾部滚动区间渲染退化单列页 | cap 公式改用与 draw break 相同的算式 `int((rr.size.x-2.0)/colw)*18`=36 |

## LOW

| # | 位置 | 缺陷 | 修法 |
|---|------|------|------|
| LOW-1 | smoke 7483 | rockless 世界静默跳过 rock-claim 断言（唯一无存在钉的 fixture） | 加 `check("rock cell exists")`——静默跳过改响亮失败 |
| LOW-3 | hud.gd 1868 | label width=-1 不裁剪，12 字符 CJK 名+后缀可溢出 click rect 压右列图标 | draw_string width 改 `colw-30` 裁剪 |
| LOW-4 | hud.gd tech_product | out[0] 逐字返回——配方产物若非 ITEMS 成员恰好撞上 relic 归一（注释否认的 masquerade 本体） | tech_product 验证 `ITEMS.has(iid)` 否则 ""；outs109 钉扩至全配方形 tech + bare109 同步要求 out∈ITEMS（"解析成功"与"有图标"语义归一） |
| LOW-2 | hud.gd 91 | bogus tid 占槽挤掉真 tid 的 memo 位（仅非 draw 调用方可触发，~62 dict 重扫有界） | 判 ACCEPTABLE——真实调用点只喂 TECH id |
| LOW-5 | tech_product 回退 | `rec.get("tech", rec.get("id"))` 允许 tech id 撞配方 id（非 tech 字段）取错图标——数据依赖 | 判合理：recipe id==tech id 时产物图标正是该节点解锁物 |

## 交叉验证 PASS（实查非假设）

- `walk43` ≡ 生产门谓词逐字节一致（含 blocked() 的 from_x=-1 缺省）；
  扫描产不出"过自家谓词却死在别道门"的格
- `open_cell` 躲齐全部 blink 车道（_near_travel_node 普查 + dmin +
  sp_min）；`bad` >8 离锚 + >6 离 spawn → 精确死在 _legit_blink 而非
  更早的门；kinbox 2×2/waypoint 1×1 的 +2.5y 声明点落在扫描的 3×3
  净空内、≥5.45>BLINK_RADIUS 离 spawn——cc 角点约束的余量算过账
- lambda 捕获正确（game 对象/walk43 Callable/sp43 值拷贝定义后不再变）
- pos_pps/pos_allow 簿记：13 次声明 vs 60 burst + 各探针前显式刷新
- `rec.out` 全 58 配方非空——`[""]` 兜底永不触发但存在
- `_tech_out` 满槽时重算路径返回正确值（缓存拒绝不影响语义）
- shot_tech.gd 走真 `_draw→draw_tech`，tech_scroll=36 落在新 cap 内

## S109b 同审（net.gd 包效率）

- decor_delta 改 _send_chunked：收割暴发单包超 MTU 原路径是**整包丢
  弃=永久装饰 desync**（cell 不重脏，幽灵永存）——真缺陷不是效率；
  分块+`_decor_buf`+_close_peer 清批，钉：跨包装配/伪造 idx 整批弃
- env_sync unl diff-gate：unlocked session 内 append-only（load_game
  带客禁载已实查证实）→ size 即指纹；`unl.is_empty()` 接收语义恰是
  "未变"——empty=keep / 实载=replace 双钉
- load_from_file→load()：smoke 像素检查全走 import 路径——源 png 在
  盘而 .import 坏的场景从"照样绿"变"响亮失败"；296 条 export 警告清

smoke **994/0/0skip** · 全部修复落地。
