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
