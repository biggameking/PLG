# S47–S49 批次 + 第十轮外审处置记录

## 外审输入（第十轮，无上下文）
1C / 2H / 3M / 6L —— 全部核实并落地于 S49。

## 产品发现 → 处置

### C1 player.mount 悬空于已释放副本（最高杠杆）
pal_sync 缺失行即 `queue_free()`，但 `game.player.mount` 若指向该副本，
每物理帧 `mount.pos = pos` 对 freed instance 解引用 → 报错刷屏 + 骑手永远卡死
（try_mount 的 `mount != null` 对悬引用恒真，无法再骑）。
处置：pal_sync 移除循环 + purge_replicas 三循环（pals/box/bench）在 free 前
清 mount 引用；player.gd `_mount_guard()` 兜底每个消费点（flying/can_enter/
speed_mult/_physics_process/dismount_if/try_mount）。

### H1 骑乘态在兄弟站点不清除
mounted_by>0 的 kin 被收回/装箱/KO/部署/屠售/孤儿化/宿主死亡时，
`mounted_by` 与 `visible=false` 残留 → kin 永远隐身、AI 沉睡、不可再骑。
处置：`_unbind_mount(p)` 集中助手，9 个出口全部调用；冒烟覆盖
retract/KO/orphan/despawn/respawn 五条路径 + 拒绝换骑保鞍（先验后解）。

### H2 成熟世界 decor/hp 快照缺失（幻影墙第四站）
world_sync 只发种子 → joiner 重新生成的是原始几何；主机运行期砍掉的树、
挖掉的石头、建筑脚印清理在成熟世界全部丢失 → 客人看见幻影墙/缺墙。
处置：state_snapshot 捎 `decor`/`hp_map` PackedByteArray（~97KB 一次性，
与存档同格式）；state_sync 先 `decor_snapshot_apply` 再放结构行
（place_free 读 decor，顺序即正确性）。冒烟断言应用+畸形包拒绝。

### M
- chest_dep 部分接受：pay 全扣、accepted 是子集 → 差额蒸发。
  chest_took 先算 `claimed-accepted` 回补再 settle。
- throw_bait 无锁且本地造 lure（host truth 分叉）→ bait_req RPC +
  throw_bait_remote 锚定 ghost pos；包消耗走客端权威通道。
- board_paid/board_release 与 act_bkt 共桶——动作刷屏可饿死结算
  （货已出袋、金未到账）→ 独立 board_bkt。

### L
- state_snapshot kin 行改用 pal_state_pack（12 字段，hp/mounted_by 入快照）。
- _on_connection_failed 清 pending_pays/chest_ref/mount_pending。
- mount_req 拒绝也回 mount_done（r=0 曾经无回执 → mount_pending 永久卡死）。
- 主机骑手 mounted_by=1：坐骑副本对所有观察者隐身，不只本地。
- mount_req_remote 先验证后解绑（拒绝换骑不再丢鞍）。
- 信任边界注记（chest 洗钱通道、bait 包信任）随代码注释落地。

## 验证
- smoke：729/730/731 checks ×3 轮，0 failures，skip 0-1（既有抖动类）。
- 新增断言 13 条：unbind 五路径、换骑保鞍、副本 despawn 清引用、
  respawn 解绑、chest 差额退款、remote bait 落点、decor 快照应用/拒绝、
  kin 快照 12 字段。
- 环境：本批在 /tmp 克隆开发（卷掉线），Godot 4.7.2 官方二进制 +
  HOME 隔离 user://；推回 origin/main 后主仓 pull 即齐。

## 延期（均有档）
线级 sender_id 伪造不可测（RPC 门靠直调覆盖）；chest-dep 完全溯源
（会破坏诚实手造存款——设计权衡）；Android release keystore、真机、
制作级美术音频、客人骑乘手感打磨（ghost 锚定 vs 自由移动）。

## 第十一轮外审处置（S50）
2H/1M/5L —— 全部落地。

### H1 pay() 记声明成本 → 欠资铸造
`pay()` 存的是 click 声明，`add_item` 静默取 0 下限 → 0 金可买、
拒绝退款反而铸金。修：`pay()` 记实际扣款差量（add_item 前后
item_count 差），空扣不立账；`buy`/`infuse` 调用点补余额门
（buy 镜像价、infuse 1+soul_boost）；`MAX_PENDING_PAYS=32` 封顶
（规则 1）。冒烟断言实扣记账/空袋不立账。

### H2 mount_req 节流丢包无回执 → mount_pending 整局卡死
act_bkt 是 ~18 动词共享桶，拾取风暴即可饿死 mount_req 且旧码
拒绝时不回 mount_done → pending 永卡。修：节流拒绝也回
mount_done(uid,0)；pending 记 uid 作用域（mount_pending_uid），
杂散回执不能提前复位；新增 `_mount_selfheal_check`——pal_sync
应用端发现 replica 仍绑自己而本地未骑 → 2s 冷却内重发 unbind。

### M respawn 解绑静默失败残留
被 H2 回执保证 + 自愈检查双保险关闭；respawn 先 `_mount_guard()`
再解引用（L6）。

### L
state_sync 清 kin 时同步清 player.mount（L5）；pal_sync 应用端
补 mode 字段（L8，副本转岗也跟线）；uid 作用域 handshake（L4）；
账本封顶（L7）。

### 验证
smoke 736/0 全绿，新增 6 断言（实扣账本/空袋无账/uid 回执作用域
/自愈离线门）。审计另证：unbind 覆盖确属全面、快照字段序双端
一致、has_saddle_for 为已记录客端权威通道。

## 第十二轮外审处置（S51）
1H/1M/4L —— 全部落地；审计同时验证 S50 全部主张成立。

### H build_req 节流丢包静默吞材料
`place_structure` 点击即扣料（非账本通道），build_bkt 0.7/s 节流
丢包时无任何回执 → 正常连点摆墙每两块丢一块成本。修：节流分支
回 `build_deny(sid)`（既有处理器退款）。同类面：`bait_req` 补
`bait_deny` 退 kin_bait。

### M deploy-while-mounted 客户端幻影坐骑
`deploy_to_base` 是唯一解绑后 replica 仍存活的路径——客户端
`player.mount` 悬在可见性=0 的基地工蜂上，保留坐骑速度与通行权。
修：pal_sync 应用端 `p==mount && (mounted_by==0 || != myid)` →
本地解绑+复显。myid 取 peer 守卫值（离线 0 不撞哨兵）。

### L
- pending_pays 驱逐→**封顶拒绝**：满 32 条时 pay() 退款返回 false，
  调用点门控 rpc（8 站点）。原驱逐语义允许被逐挂账的回执错配
  同 tag 挂账（需 34 并发在途，伪造端界限内——防御纵深改为
  "挂账一旦建立永不消失，回执永远配对自己的请求"）。
- respawn 解绑重复请求：pending 握手已锁定同 uid 时跳过（在飞
  unbind 的回执会解绑，第二个 toggle 会重新绑定）；客户端路径
  补 net_live() 门（半连状态不发 rpc）。
- to_title 改走 `net._close_peer()`——优雅断连，远端见 disconnect
  而非超时。
- pal_sync `nid<=0` 行直接跳过——原会每 tick 生成无法追踪的幻影
  kin（本地可打可捕）。
- infuse 镜像价：soul_boost 不在线上字段——`infuse_done(uid,cost)`
  回执顺手让客户端 replica sb+1，镜像价下次诚实。
- unbind_retry_t 倒计时移出 ghosts 守卫（半断会话也冷却）；
  self-heal 补 net_live() 门。

### 审计验证为正确（拒绝的假设）
pay() 实扣记账、FIFO 配对、空扣不立账、全动词拒路回执完备
（build_req 是唯一漏网的——已修）、自愈/按钮互斥无抢占、
uid 作用域握手、全 unbind 兄弟站点（唯一缺口即 deploy M 项）。

### 验证
smoke 741/0 零 ERROR；新断言 5 条（存活 replica 掉鞍、wire 等级
落地、非正 uid 不生成、满账拒绝+退款、deny 退饵）。
IP CHECK: CLEAN。
