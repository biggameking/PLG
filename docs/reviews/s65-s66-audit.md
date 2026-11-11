# S65–S66 kin 美术管线外审（audit-24）

背景：S65 将全部 116 物种精灵从程序化占位方块替换为 Blender 参数化
rig 渲染（rig_auto.py → rigs_gen.py → render_kin.py → post_kin.py）。
无上下文外审结论 **HOLD（0C/4H/6M/4L）**，S66 全部落地修复。

## 外审发现与处置

| 级别 | 发现 | 处置 |
|---|---|---|
| H1 | dump 读 `d["body"]` 而非 `SpeciesData.body_of()`，CORE_BODY 虚构映射使 15 物种渲错原型（可骑乘渲成鸟/blob、不可骑渲成牛） | `dump_species.gd` 改走 `body_of()`；删除 CORE_BODY；全量重渲 |
| H2 | `gen_assets.py` 仍可一键回滚全部 kin 精灵 | kin 写盘门控为 `--kin-legacy` |
| H3 | 10 个传说种配饰（冠/环/面具/角/冠饰/鳍/背扇）静默丢失，冒烟断言被弱化放行 | ACCESSORY 表 + rig 配饰部件恢复；断言重新钉到真实暖色配饰像素 |
| H4 | 提交的 rig_auto.py 无法复现提交的 rigs_gen.py | 本提交内 rig_auto/rigs_gen 同步；AGENTS.md rule 97 |
| M1 | hedgehog 原型 fluff 掩埋面部、腿悬空 | 重构：体块+背部 fluff+前脸+前足 |
| M2 | 多原型眼珠半埋头球表面；bird 头没入体球；noctfang/murkwing 无脸 | 全原型眼睛推出表面、bird 头抬高+面色材质、serpent 眼加大 |
| M3 | f1≈f0（位移打在深度轴，80% 物种双帧无差别） | bob 打 Z 轴、阈值改按 rig 相对高度；117 只全验证 f0≠f1 |
| M | quadruped `head_z` 死参 | 接线（deer 抬头） |
| L | emit 空 rest 会产出 `, ,` 语法错误 | 空守卫 |
| L | 冒烟仅覆盖 4/116 精灵加载 | 全物种×双帧 load+不透明+墨迹像素检查 |

## 过程沉淀（AGENTS.md rules 97–100）

97 生成物必须可由已提交源码复现；98 dump 走权威访问器而非裸字段；
99 替换资产即退役旧写盘器；100 断言只迁移不放宽。

验证基线：smoke 763/0（1 skipped 为种子化夹具抖动）、IP CLEAN、
全 116 种 + player 双帧均有实体像素与差异帧。
