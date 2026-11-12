# audit-29 联机安全外审（S74 后无上下文复核）

背景：S74 本地化收口后，对联机面做无上下文外审。结论 **HOLD
（1H/3M/若干 L）**，全部落地修复于 `bb46a8d`，smoke 816/0。

## 外审发现与处置

| 级别 | 发现 | 处置 |
|---|---|---|
| H1 | `struct_wire_state()` 把 `placed_tag`/`own_tag` 广播给所有来客；`hello()` 又把"持有 tag"当身份证明——断线 keeper 的 tag 被广播公开后，恶意来客 hello 冒领即可继承其孤儿名册与拆除权 | 线上协议删两字段（客户端本就不消费）；hello 改为首绑即锁（同 pid 换 tag 拒、同 tag 幂等） |
| M1 | 来客睡眠可无限刷共享天数——只要够得着床就推进全局时钟 | `sleep_req_remote` + sleep RPC 加 `is_night()` 语义门；一觉翻页到 6 点天然限频 |
| M2 | 蛋种父母档按会话 pid 记——回收的 peer id 可冒领死者血统 | `egg_parents` 存 `owner_tag`；领取按 `peer_tags[pid]` 匹配；旧 int/无 tag 行仅 keeper(pid 0) 可领 |
| M3 | 客户端回执信线上数字——`bought`/`infuse_done` 按主机宣称价扣款、`board_done` 信任 ask | `pay_hold()` 暴露实际挂账；回执以挂账封顶；板 ask 必须匹配镜像公告且数量 clamp |
| L | `guest_hit`/`guest_skill_hit` 无限流——脚本包可超野生 DPS | hurt_bkt 令牌桶（10/s, burst 16） |
| L | `take_drop` 无 ghost 仍进 drops 循环 | ghost 缺失即拒 + 距离门 |
| L | `throw_bait_remote` 可反复覆盖活饵堆 | 活饵期内拒绝重放 |
| L | 多个 float 参 RPC 无 `is_finite` 顶门——NaN 坐标可绕过全部邻近门 | chest/mimic/dig/cage/mount/infuse 处理器补守卫；全量 any_peer 处理器复核确认覆盖 |

## 回归覆盖（tools/smoke_test.gd）

- 线上包断言无 `"by"`/`"own"` 身份字段；重绑 hello 拒、同 tag 幂等
- 日间客睡拒 / 夜间准 / 天亮后不可连刷（世界敌意钉死、生命体征快照还原）
- 蛋种按 tag 领取、错 tag 拒、旧 pid 行成僵尸、旧 keeper 行归主
- 回执按挂账/镜像封顶：bought 伪价 9999 实扣 30；板 ask 错 id 拒、虚量 clamp 到 4

## 过程沉淀（AGENTS.md rules 109–113）

109 身份秘密不上广播；110 会话身份首绑即锁；111 回执按挂账对账；
112 世界时钟动词用语义门而非限流桶；113 夹具假行走 `structures.erase`
（真实拆除函数对缺键假行中途崩，残留污染后续全部存档断言）。

附带：音频收口——6 个新合成音（quest/craft/hatch/coin/eat/drop）+ 8 接线点，
套件新增 `sfx_play` 键全解析 lint（"drop" 此前被调 3 次却无音源）。
