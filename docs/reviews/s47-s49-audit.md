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

## 第十三轮外审处置（S52）
1M/6L —— 全部落地；审计同时验证 S51 全部主张成立。

### M respawn 未上膛 mount_req → 自愈车道可重绑
respawn 的释放请求是唯一不登记 pending 的发送方：陈旧 pal_sync
行（mounted_by=me）在回执窗口内触发自愈 → 第二个 toggle 把
刚释放的兽重新绑定（toggle 无法表达"仅解绑"）。修：respawn
发送前先 `mount_pending + mount_pending_uid` 上膛，与其他发送
方同约；自愈在 armed 窗口内被 pending 门挡住。

### L
- mount_done state 0/2 车道拆分：0（拒绝）只放握手不碰鞍——
  节流饿死的下马按键不再误清仍绑定坐骑；state 2 确认释放时
  顺手恢复 replica 可见性（不再等 500ms pal_sync）。
- build/bait 并入账本：删掉按"成本表"退款的 build_deny/
  bait_deny——退款现在来自挂账的实扣记录（拒路全部 _pay_rej /
  bait_done(false)，成功 build_done/bait_done(true) 结算）。
  throw_bait_remote 补返回值（ghost 缺失也回执——挂账不再悬挂）。
- 冒烟夹具纪律：kin_bait 备份还原。

### 审计验证为正确
pay() 退款无损耗、8 调用点全门控、myid 守卫正确（回执排序由
ENet 可靠通道保证）、net_live 严格等效 CONNECTED、infuse_done
签名一致、_close_peer 全状态安全。

### 验证
smoke 743/0 零 ERROR；新断言 3 条（拒绝下马保鞍、确认释放显形、
账本化退饵/退料）。

## 第十四轮外审处置（S53）
2M/8L —— 全部落地；审计同时验证 S52 全部主张成立。

### M1 board 结算非幂等 → 已付货可被节流吞 + 双倍扣货
`board_done` 先扣货再发 `board_paid`，后者挂 board_bkt 节流——
饿死则货没了金没了，重读板子再扣一轮。修：结算动词撤节流
（`board_paid_remote` 自验 pid+id 持有、首次成功即擦——天然
自我限流）；客户端 `board_paid_out` 旗标令 `board_done` 对同
ask 幂等（回执在飞期间重显示不再扣）。`rpc_id(1)` 改 `rpc()`
广播（叶子客户端唯一远端即主机，且消除对未注册远端的硬编码）。

### M2 路由层覆盖
新增真回环段（ENET 服务端+客户端握手）：board 幂等三断言 +
respawn armed 断言（`multiplayer.poll()` 同步泵 API 注册）。

### L
- `bait_req` 节流拒路补 `get_peers().has(pid)`（与全族对齐）；
  `_pay_rej` 同补 pid 存在性。
- `mount_done` state 1 补 `mount == null` 门（陈旧绑定回执不能
  顶掉现骑）；state 2 走 `_mount_guard()`。
- `_close_peer` 统一清 pending_pays/mount_pending/uid/retry/
  board_paid_out（peer-swap 即闸口）；两个断线回调补齐 uid/
  retry/board 旗标。
- `place_structure` 账本满拒时返回 false（点击按拒绝结算）。
- 冒烟夹具：wood 种子化+还原。

### 验证
smoke 746/0 零 ERROR。

## 第十五轮外审处置（S54）

外审快照 `3508a74`：**1M/6L**。S53 改动面全部复核通过；抓到一个协议级真 M 与一个存量真 bug。

### M1 board_paid_out 会话级楔死
旗标仅 `board_pay` 回执可清——`board_paid_remote` 返回 `{}` 时主机静默
（持有失效三路：过期被他人顶替 / `board_quest` 因日期/重生换 dict /
peer 中途消失），客户端已扣货+旗标永真，同 qid 后续 `board_done` 全吞，
且重claim蹲占共享板子 15s。
修法：`board_paid` 失败分支回 `board_rej(qid)`（peer 在播才发）；
客户端新处理器仅匹配 `board_paid_out` 时清旗。货物损失按先付协议归
payer 自担（与账本案一致），旗标不再楔死。

### L2 server_relay 存量 bug（本批最重要的隐藏发现）
`ENetMultiplayerPeer` 上无此属性——relay 开关在 `SceneMultiplayer`
（`is_server_relay_supported` 探明）。默认 true 下：客户端广播经主机
转发给全体客人 → 3+ 人聊天双打印（原始包+主机中继包各一份），"叶子
唯一远端"注释为假。
修法：`host()` 置 `multiplayer.server_relay=false`。回归面核实：
客人互见走主机 `peer_pos` 中继、`peer_joined` 广播名册、`sync_pos`
的 `id!=1` 守卫变纵深防御。聊天处理器无需改动。

### L3-L6
- L3/L4 mount_done 门与 place_structure 返回语义复核通过，不动。
- L5 `_close_peer` 补 `chest_ref` 清 + 注记 ghost/镜像归属场景层。
- L6 回环夹具补齐：`hunger` 还原、connect-hook 生成的 `ghosts[1]`
  按 had 旗标回收、`user://plg_net.cfg` 备份还原（规则 30）。
- `_on_connection_failed` 补 `unbind_retry_t`。

### Nits（留档）
`board_done` 信任权威 qn（模型内主机即权威）；`board_quest.pending`
存而不载（设计内）；`unbind_retry_t` 缺 connection_failed 清——已补。

### 验证
smoke 745/0 ×2 零 ERROR（首次误设 `peer.server_relay` 即时脚本探明
真名 `SceneMultiplayer.server_relay`——API 名未经验证的教训）。

## 第十五轮外审处置（S54）

外审快照 `3508a74`：**1M/6L**。S53 改动面全部复核通过；抓到一个协议级真 M 与一个存量真 bug。

### M1 board_paid_out 会话级楔死
旗标仅 `board_pay` 回执可清——`board_paid_remote` 返回 `{}` 时主机静默
（持有失效三路：过期被他人顶替 / `board_quest` 因日期/重生换 dict /
peer 中途消失），客户端已扣货+旗标永真，同 qid 后续 `board_done` 全吞，
且重 claim 蹲占共享板子 15s。
修法：`board_paid` 失败分支回 `board_rej(qid)`（peer 在播才发）；
客户端新处理器仅匹配 `board_paid_out` 时清旗。货物损失按先付协议归
payer 自担（与账本案一致），旗标不再楔死。

### L2 server_relay 存量 bug（本批最重要的隐藏发现）
`ENetMultiplayerPeer` 上无此属性——relay 开关在 `SceneMultiplayer`
（`is_server_relay_supported` 探明）。默认 true 下：客户端广播经主机
转发给全体客人 → 3+ 人聊天双打印（原始包+主机中继包各一份），"叶子
唯一远端"注释为假。
修法：`host()` 置 `multiplayer.server_relay=false`。回归面核实：
客人互见走主机 `peer_pos` 中继、`peer_joined` 广播名册、`sync_pos`
的 `id!=1` 守卫变纵深防御。聊天处理器无需改动。

### L3-L6
- L3/L4 mount_done 门与 place_structure 返回语义复核通过，不动。
- L5 `_close_peer` 补 `chest_ref` 清 + 注记 ghost/镜像归属场景层。
- L6 回环夹具补齐：`hunger` 还原、connect-hook 生成的 `ghosts[1]`
  按 had 旗标回收、`user://plg_net.cfg` 备份还原（规则 30）。
- `_on_connection_failed` 补 `unbind_retry_t`。

### Nits（留档）
`board_done` 信任权威 qn（模型内主机即权威）；`board_quest.pending`
存而不载（设计内）。

### 验证
smoke 745/0 ×2 零 ERROR（首次误设 `peer.server_relay` 即时脚本探明
真名 `SceneMultiplayer.server_relay`——API 名未经验证的教训）。

## 第十六轮外审处置（S55）— 存档/生命周期/迁移面

外审快照 `ff88557`：**1H/6M/13L**。首轮非 net 面专审即中彩——存档
反序列化是本弧最后一块未硬化的信任边界。

### H1 非数值 Variant 炸 load_game → 半重建世界 → 存档覆写
`int()`/`float()`/`x == true` 遇 Array/Dict/String-vs-bool 一律 abort，
中止点介于"旧世界已清"与"世界重建"之间——半空世界在 play 态存活，
下次 save 直接覆写真档。
修法：边界强转 `Game._i/_f`（仅 bool/int/float/String 可转，余归默认），
~35 个载入点全部接管；`== true` 同型炸点 7 处改 `is bool` 双段；
冒烟新增敌意 Variant 夹具（day:[1,2]、items:{7:5}、meal:5、lv:{}、
cap 伪种、inc.pair=5）——断言载入完成+袋键纯 String+meal_buff 纯
dict+raid 旗按模式擦洗+伪造 captive 清空+pair 归一 null。

### M（6/6 全落）
- 载入结构缺 `pos`/`turret`（放置路都写）：demolish 的 kinbox 锚守卫
  `st.get("pos")==kinbox_pos` 读 null→永不触发→存档后末座 kinbox 可拆
  →基地孤儿化；载入炮塔 `turret` 恒 0→永不开火。重建补齐两键。
- `meal_buff` 未验 is Dictionary → 每帧 `.get` abort→移动死。补验。
- `items` 键未 `str()`+未过 ITEMS → `item_wt(sid:String)` 每帧参数错误
  →速度死。双验（键白名单+值强转）。
- 载入环无容量帽：kin/pals/box/bench/party/rparties/structures 全部接
  既有 MAX_*（box 432 溢出道、bench 32、party 5、rparties 32、
  structures 400）——规则 1 对存档同样生效。
- `captive.sp` 未验 → `free_captive`→`gen_pal` 中道 abort→半建孤儿 kin
  游离于 pals 之外。SpeciesData 白名单，载入+`_struct_wire_apply` 双端。
- `egg_parents`/`inc.pair` 未验 Array → tick_ranch 每帧炸 / hatch 读
  型化 sp_id 炸。egg 限 Array 滤项；pair 归一化 null（野蛋血统），
  不丢蛋槽。

### L（13/13 全落或证伪）
- `np.raid` 仅 wild 模式可载（roster 化 raid 旗永钉 danger_active）；
- KO 溢出释放补 `revive_t=0`（陈旧计时器会 wipe 再捕获的兽至 30%）；
- `cap_lv` 钳 1..6 与线一致（原 1..20）；`unlocked` 过 TECH id+STRUCTURES
  双白名单（TECH 是 dict 数组——`has(id)` 恒 false 的教训）；
- `SAVE_VER` 前向闸门（v>2 拒载防静默误读）；`dirty_decor` 载入/重生
  双清；`statuses/catch_streak/mission_t/last_merchant_day/focus_t`
  载入复位补齐（与 regenerate 对称）；
- box/bench 三处 `free()`→`queue_free()`（box_holder 在树内，规则 2）；
- `bought` 价 `Game._i`；`struct_sync` store 逐键强转；
- respawns pos 元素型验；board kind 白名单 supply/hunt；
- drops id 过 ITEMS 白名单。
- party_idx 损坏条目索引偏移：记档（uid 仍有效，mode 门限害）。

### 自修复三处（套件抓回）
1. `pd.get("raid") == true` 遇 "y" 字符串炸——`== true` 全族改 `is bool`
2. `StructureData.TECH` 是 dict 数组，`has(id)` 恒 false→unlocked 滤空
   →net_place 拒放：TECH id 展开成真集合
3. 敌意夹具孵化器残留吃掉后续 deposit 测试：夹具尾 net_remove 清场

### 验证
smoke 749/0、747/0 零 ERROR。

## 第十七轮外审处置（S56）— S55 修复面复核

外审快照 `76184d4`：**4C/3H/2M/3L**。S55 的数值强转层全部成立，但
"非数值 abort" 还有第二类——typed 参数传递 / 迭代 / 键类型——四类
全部 post-teardown，同属"半重建世界覆写档"杀伤链。

### C（4/4 全落）
- `world.generate(d["seed"])` raw Variant → typed `int` param。seed 加
  入类型检查链：非数值**拒绝载入**（pre-teardown，世界不动），调用点
  `int(d["seed"])`。夹具新增拒绝路断言：seed="abc" → 返回 false 且
  live 世界 pals 存活。
- `ks.split(",")` on non-String dict keys — `store_var` 保留 int/
  Vector2 键，`ks is not String → continue`。
- `species_of(pd.get("sp"))` raw Variant → `id: String` — 包 `str()`，
  与同函数其余调用点一致。
- `for pi in d["party_idx"]` — `has()` 不挡 null/scalar，`is Array` 闸。

### H（3/3 全落）
- migrate.gd 四循环（drops/crafts/kin/respawns）跑在 load 守卫**之前**
  ——`is Array` 闸；game.gd 同名字段循环同样补闸（post-teardown 更致命）。
- `boss_respawns` 条目 `duplicate()` 保留敌意尾——`lv:{}`/`alpha:{}`
  会在 tick 时 `int()`/`bool()` abort 且 `add_child` 先于 `setup` →
  树内幽灵节点 + 每帧 ERROR。改为**重建白名单 dict**（sid/pos/lv/
  alpha/boss/at 全强转，sid 过物种白名单）。
- `pending_jobs` 在容量路由**之前**入队——溢出 lane `np.free()` 后
  引用悬垂，job 应用循环 abort 跳过 `_reset_shell_state()`。移到
  `loaded.append(np)` 之后（三个成功 lane 的公共点）。

### M（2/2 全落）
- `_norm_pair()` 共享归一器：entry 必须 `[String,String,num,num]` 头
  ——`["a","b",{},{}]` 通过旧 `size>=4`+头检却在 `int(pair[2])` 炸。
  三处全替：存档 inc.pair、线级 inc.pair、`egg_parents` 过滤（连
  `_claim_egg_parent` 的默认 `[0]` 车道一并封死）。
- `int(u)`→`_i(u)`（wk 循环）；`spawn_net_pal` 全部线级强转
  （lv/lucky/nid/boss/alpha/mount）**前置**到 `gen_pal` 调用之前——
  `int(d[6])` 原在 gen_pal 之后跑，abort 即树内幽灵 kin。

### L（3/3 全落）
- bench 上限 32 → `MAX_BENCH = 5 + MAX_REMOTE_TAGS*5`（165）——
  联机存档的真 orb 曾被静默 free。
- `pr["node"].queue_free()` 补 `is_instance_valid` 对称守卫。
- 两处"box pals aren't in the scene tree"过时注释更正（box_holder
  在树内；`free()` 在树内节点合法且立即）。

### 夹具扩展
敌意存档新增：seed="abc"（拒绝路断言）、`sp:5`、int 结构键、
`party_idx:null`、`drops:null`/`crafts:5`、敌意 respawns 尾、
`pair:["a","b",{},{}]`、`egg:[[5,6,7,8]]`；线级新增 dict lv/nid
`spawn_net_pal` 强转断言。

### 验证
smoke 752/0、749/0 零 ERROR ×2。

## 第十八轮外审处置（S57）— S56 复核

外审快照 `8cac4a4`：**1C/3M/3L**。S56 主架全部验证通过（类型链、
迭代闸、`_norm_pair`、spawn 预估值、seed 拒绝路、schema 无漂移），
剩余四类真伤：

### C — meal_buff dict 值未强转
`d["player"]["meal"]` 只验容器型——`{"glow":{}}` 直达
`player.gd:319` 的每帧 `int(meal_buff.get("glow"))` → 物理帧死。
修法：按六键白名单逐值重建（atk/def/spd/warm/cool/glow），`_fin`
数值门 + 0..10 钳制——伪造键值永远到不了消费端。

### M（3/3 全落）
- NaN/±INF 穿所有 `is float` 闸——`maxf(0,NaN)=NaN` 让 respawn
  `at` 立即触发、`pos` 落 NaN 实体、`seed` 走 impl-defined。
  `_i`/`_f` 加 `is_finite` 层（NaN→dflt），新增 `_fin(v)` 门并
  替换全部 18 处边界 `is float or is int`（seed/drops/respawn
  pos/grotto/treasure/ppos/home/pbx/rparties/store/fert/wk/
  wire sync/drop_sync/decor_sync/settings/`_norm_pair` 尾）。
- `remote_parties` 行帽被 `rebind_owner` 的裸写绕过 + 被逐行的
  orb 留在 bench → 每驱逐周期 +5 无界。`rebind_owner` 新 tag 走
  `rparty_by_tag`（驱逐车道唯一入口）；驱逐时 orb 归箱（box 满
  →queue_free）。新增 `_bench_add` 溢出车道：bench 满→box、双满
  →queue_free，六个 bench.append 站点全部改道，strip uid 只在
  true lane 追加。
- `hatch_incubated` 是唯一无帽 kin 入口——`pals`/`box` 双帽 +
  `max_base_pals()` 劳动力帽，双满→queue_free。

### L（3/3 全落或升级）
- `hr_ok` 只验 3 字段→全六字段白名单断言；新增**真触发一条
  respawn** 端到端断言（`at` 设为过去→tick→pal 出现→清场）。
- `pd["sp"]` raw Variant→`str()` 进 typed param（最后一个此类）。
- `spawn_net_pal` 坐标 `_fin` 门（NaN replica 不可达）。
- schema 对账：顶层写读 1:1，无漂移；`craft.cost`/`board_quest.
  pending`/`craft_target` 死字段记档不删。

### 验证
smoke 750/0、749/0 零 ERROR ×2。
