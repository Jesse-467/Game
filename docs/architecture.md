# 架构与扩展约定

## 已落地的边界

- `project.godot` 和 `scenes/main.tscn`：应用入口与平台基础配置。
- `scripts/main.gd`：组合入口，连接输入、存档、事件与表现层。
- `scripts/core/run_session.gd`：局内生命周期、经验、升级、奖励与结束规则。
- `scripts/core/run_director.gd`：无尽节点、刷怪组合和难度曲线。
- `scripts/core/world_geometry.gd`：真实地图边界、逻辑视口、跟随镜头的停止位置与屏幕刷怪有效区。
- `scripts/core/spawn_sampler.gd`：打乱角度扇区袋，在视口内、玩家安全距离外采样，并避开操作区域。
- `scripts/core/combat_system.gd`：战斗模拟、角色状态、敌人行动、弹体与命中。
- `scripts/core/enemy_spatial_index.gd`：弹体宽阶段候选查找，精确几何和命中顺序仍由战斗系统决定。
- `scripts/core/enemy_attack_patterns.gd`：按生命比例和Boss轮次选择阶段，生成锁定的攻击几何计划，供预警、弹道/范围判定和召唤位置共用。
- `scripts/core/arena_field.gd`：场地轮换、预警、临时buff/debuff，与角色永久成长分离。
- `scripts/core/upgrade_catalog.gd`：祝福内容加载、候选生成、叠加记录和效果计算，与UI无关。
- `scripts/core/progression_store.gd`：版本化局外存档、临时文件写入与备份读取，与战斗无关。
- `scripts/core/run_snapshot.gd`：显式捕获/恢复模拟状态，不保存渲染资源或手指意图。
- `scripts/core/active_run_store.gd`：检查点文件的版本、原子替换、备份与完整清除；Variant格式保留向量、颜色和64位随机数状态。
- `data/balance.json`：初始属性、难度、Boss及能力数值。
- `data/upgrades.json`：带稳定ID的祝福内容、效果参数、标签和叠加限制。
- `data/characters.json`、`data/enemies.json`、`data/arena_afflictions.json`：角色、敌人、场地内容定义。
- `scripts/input/touch_controller.gd`：按触点归属生成操作意图，独立于战斗与GUI鼠标模拟。
- `scripts/ui/game_ui.gd`：营地、升级、设置、结算、HUD；通过信号发出选择。
- `scripts/ui/round_action_button.gd` 与 `joystick_view.gd`：固定在CanvasLayer中的圆形操作控件；`control_layout.gd`统一圆形外观与命中几何。
- `scripts/ui/run_readout.gd`：只读属性、场地实际收益、祝福和记录展示，不推进模拟或抽取选项。
- `scripts/presentation/`：场景实例、动画图集缓存、特效和声音。
- `tests/combat_smoke.gd`：隔离真实存档的战斗逻辑验证。
- `tests/arena_field_smoke.gd` 与 `tests/ui_smoke.gd`：场地规则、组合自由、动画和界面生命周期。

## 下一步拆分

目前模拟实体使用数据记录，表现实体使用独立 `actor_view.tscn`。当新武器或Boss行为复杂度上升时，继续按行为边界提取组件；已有独立模拟模型用于验证规则，避免让场景表现决定数值。

新增内容遵循：定义决定参数，行为组件决定行动，表现层决定画面。Boss行为以攻击状态/前摇/生效/恢复描述；新Boss不通过主循环堆积条件分支。

Boss的`phases`按基础到进阶的优先级排列，取最后一个满足`hp_below`与`min_rotation`的阶段。变阶段先完成已开始的前摇或冲锋，再重置招式顺序并给予额外准备时间。攻击准备时保存`telegraph_shapes`；表现层读取同一计划，弹体方向、圆形/圆环伤害和召唤落点不重新追踪玩家。新增攻击形状与行为分别在计划组件、模拟和表现层接入。

场地效果不修改永久属性，不限制玩家可组合的机制。攻击发射时记录场地对输出、暴击和控制时长的影响；离开区域后，新攻击立即恢复正常。升级与暂停冻结场地计时，死亡结算不会通过节点回血复活角色。

世界和HUD使用不同坐标层：战斗实体与场地区域保持世界坐标，Camera2D使用与模拟相同的视口计算；摇杆、按钮和血条固定在CanvasLayer。镜头边界保留HUD垂直空间，真实地图边缘的角色不会被顶部信息和底部控件遮住。场地按独立时钟循环，类型与空间网格分别用打乱袋，节点变化不重置其倒计时。

保持可测试的核心逻辑与Godot场景配合。当前规模不引入后台服务、在线账号、分布式组件或通用框架；未来联网作为独立需求评估。

## 内容与存档版本

内容ID一旦出现在存档中就保持稳定；显示名称可调整。祝福新增效果类型需要实现并验证对应行为。存档包含 `schema_version`，变更字段时提供显式迁移并验证旧存档；局外进度支持v1及初始未带版本字段，局内检查点当前为v2并提供v1迁移。

局外记录与局内检查点各自版本化。每局有稳定ID，奖励提交后将该ID写入局外记录，再删除检查点；启动时已结算的ID不得恢复，避免文件删除前进程退出造成复活或重复奖励。待选择的升级记录原选项ID与RNG状态，恢复不重抽。测试与渲染探针使用内存检查点仓库或独立测试目录。

0.4.0的敌人记录增加可选`phase_id`、`telegraph_shapes`，仍使用检查点v1。旧记录缺少这两个字段时，先按保存的`active_attack`和锁定目标完成原攻击，再进入适用的新阶段；不改写玩家已有构筑。

0.6.0检查点v2保存刷怪扇区袋、场地类型袋/网格袋、下一场地与轮换计数。v1迁移将玩家、敌人、锁定目标、攻击几何、弹体、经验与特效整体平移到大地图，保留相对关系、等级、冷却和已有前摇；新的随机袋从当前RNG状态继续。相机从玩家位置计算，手指意图仍不保存。

工具、构建产物与私有签名密钥不纳入Git。下载素材保留作者许可和来源，资产不引用开发机绝对路径。

## 验证层次

逻辑测试验证数值规则、经验、升级、节点和奖励；场景运行验证信号、资源和UI；渲染检查验证实际中文字体和布局；安卓导出验证平台配置；真机试玩验证触控、性能和战斗体验。任一层通过不能代替其余层。
