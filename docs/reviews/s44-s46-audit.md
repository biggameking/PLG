# S44–S46 — 第九轮无上下文外审与落地

第九轮外审覆盖 S34–S43 联机对等弧 + S44 终局 + S45 Android 导出。**0C/2H/3M/5L**。

## 产品发现 → 处置

### H1 世界生成确定性只修了 join 车道没修 boot 车道（最高杠杆）

`_ready` 里 `world.generate(seed)` 后四个 spawn 走 Time-seeded session `rng`
（且顺序是 wild→lairs→camps→fossils），而 `regenerate` 先
`rng.s = (seed ^ 0x9E3779B9)` 再按 lairs→camps→fossils→wild 放。客人加入
**全新主机**时本地重放的 POI 与主机实际不同——grotto/尖塔岩石环、石门是
`world.decor`/`world.hp`，只以 delta 同步，整局幻影墙/隐形墙。S4–S7 审过的
bug 类，当时只打了 `regenerate` 一个点。

**修法**：抽 `place_pois()`（lairs→camps→fossils→wild，顺序是契约），`_ready`
与 `regenerate` 都在 `world.seed ^ 0x9E3779B9` reseed 下走同一车道。外部
clean-boot 探针实证：boot 与 `regenerate(seed)` 产出完全一致的
grotto/room2/40 structures/42 pals。冒烟补 regen 同种子双跑断言。

### H2 效果先于支付——诚实断线窗口铸造持久共享状态

一批动词主机先落效果、echo 再扣袋：echo 丢在断线窗口 = 货在袋也在箱
（`chest_dep` 洗进共享储物）、minted kin 到手金未扣（`buy`）、蛋在孵化器也在
袋、soul_boost/技能白送（`infuse`/`fruit`）、天气/施肥免费（`shrine`/`fert`）。

**修法**：先付后请账本（`net.pending_pays`）。客户端在请求飞出时乐观扣袋 +
挂账；主机**每一条**失败路径（节流+校验拒）发 `pay_rej` 退款，成功 echo 结算。
断线窗口从 mint 变成 payer 自担 loss——诚实玩家严格更好，伪造端仍在既有
bag-trust 边界内。`buy`/`infuse` 回执改为"退乐观价再扣主机真价"（镜像价可能
陈旧）。`board_paid` 核查后确认已是先付后请，不动。

### M

- **`create_server` 无 `max_clients`** → `MAX_PEERS := 8`（ghost/tag/扇出随连接数增长）。
- **`sync_pos` 无包率帽** —— 距离桶管步长不管包数，1kHz 合规小步强制逐包中继放大 →
  `POS_PPS 45 / POS_PPS_BURST 60` 包数桶，读包前先饿死泛洪。
- **主机包在客户端仍被客人桶警察**（S43 L1 只豁免首 fix）——稳态主机包走
  40u/s 桶+blink 整形，非常规传送冻住主机 ghost → 客户端对 `id==1` 完全豁免
  （规则 76 残差闭合）。

### L

- `state_sync` 只加不删——本地 regen 残留的 lair 箱会挡 `place_free`、wire 状态永远落不上 → 入同步前清空 `structures`/`world.structures`。
- echo 无条件扣款可出负栈 → 先付后请协议内自然消解（`bought`/`infuse_done` 退乐观扣真价）。
- 客人永远不能骑乘 → **记延期**：客人坐骑是 host 端 replica，`try_mount` 拒绝 replica 是正确边界，真坐骑同步是独立设计（鞍具归属+控制权移交），非本批边角。
- `net_live()` 把 CONNECTING 当 live → 改 `== CONNECTION_CONNECTED`；冒烟断言翻转为"半开拨号无 CHAT 行" + 真回环握手正例。
- 断线不清 `chest_ref` → `_on_server_disconnected` 一并清。

## 流程发现 → 规则沉淀（77–79）

- **77 同型修复必须枚举全部站点**：确定性、门、镜像、先付——一个模式打在一个
  站点上时，先列同型站点清单再动手。幻影墙类第三次回潮（S4→regen、S46→boot）
  就是因为"修被报告的那个点"而不是"修这一类"。写代码时强制做 sibling-site
  sweep，不靠下一轮外审兜底。
- **78 支付动词：先付后请，拒绝必退款**。效果是主机真值、袋是客户端真值——
  效果先于支付把断线窗口变成 mint。所有新增"花袋换效果"动词默认走
  `pay → req → done/rej` 三步；回执语义是"结算挂账"不是"扣款"。
- **79 镜像与真值同字段时，快照必须整体替换**。`state_sync` 只 `place_free`
  不清场，本地生成的同位结构会挡掉主机行并留下幻影——加入路径的替换语义
  是 raze-and-replace，不是 merge。

## 验证

冒烟 **711 checks ×4 绿**（1 次 "node-to-node hop" 存量传送时序抖动复跑消失）、
零 ERROR、零泄漏。断言净增：regen 同种子双跑、pay 账本三态、半开拨号无 chat 行、
回环握手有 chat 行。

## 延期（均有档）

- 客人骑乘（replica 坐骑=控制权移交设计，非边角）
- 线级 `sender_id` 伪造面（harness 限制，直连调用覆盖）
- Android release keystore / 真机安装（ADB 无设备）
- 制作级美术/音频、并行 Ink 会话字节
- chest-dep 完全溯源（会破坏诚实手造存款，记录在案的设计权衡）
