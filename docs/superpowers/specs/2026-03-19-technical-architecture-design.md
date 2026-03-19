# 技术架构设计文档
**日期**：2026-03-19
**版本**：1.2
**状态**：已确认
**引擎**：Godot 4.x / GDScript（强制静态类型）

---

## 一、架构总览

### 设计原则
1. **纯粹的逻辑解耦**：核心逻辑类（`RefCounted`/`Resource`）严禁混入 UI 或节点操作
2. **单向数据流**：数据层 → 逻辑层 → 表现层，表现层不持有业务逻辑
3. **信号驱动表现**：状态变更通过信号广播，Scene Tree 监听后自行更新 UI
4. **TDD 优先**：所有核心计算逻辑（EV、陷阱触发、手牌判定）先写 GUT 测试
5. **静态类型强制**：所有变量声明类型，所有函数声明返回类型

### 模块两分法

```
┌─────────────────────────────────────────────────────────┐
│              通用游戏模块 (Universal Modules)             │
│   EventBus · AudioManager · FeedbackSystem · UIManager  │
│   SaveManager · AchievementSystem · ResourceCache        │
│   InputManager                                          │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│              核心玩法模块 (Core Gameplay Modules)         │
│   GameFlow · Economy · Casino · NPC                     │
│   PokerEngine · PlayerAbility · Narrative               │
└─────────────────────────────────────────────────────────┘
```

### 分层结构

```
[数据层] Resource / RefCounted（纯 GDScript，无节点依赖，可完整 TDD）
    ↓ 状态变更时发射带参信号
[逻辑层] Autoload Managers（协调各系统，驱动状态机）
    ↓ 通过 EventBus 广播跨模块事件
[表现层] Scene Tree（监听信号，纯展示，不持有业务逻辑）
```

---

## 二、通用游戏模块（Universal Modules）

所有通用模块均注册为 **Autoload 单例**，提供全游戏通用服务。

---

### 2.1 EventBus
**职责**：全局信号中继站，所有跨模块通信的唯一通道，不持有任何状态。

```
autoloads/EventBus.gd
```

**核心信号分组**：

```gdscript
# ── NPC 心理系统 ──
signal npc_physiological_changed(npc_id: String, excitement: float, stress: float)
signal npc_trap_triggered(npc_id: String, trap_type: StringName)
signal npc_decision_made(npc_id: String, action: StringName, amount: int)

# ── 牌局事件 ──
signal betting_round_started(round: int)
signal ability_window_opened(round: int, ap_remaining: int)
signal ability_used(card_id: String, ability_type: StringName, target_npc_id: String)
signal poker_sub_round_won(npc_id: String, reward_count: int)
signal poker_session_ended(winner_id: String, pot: int)

# ── 经营事件 ──
signal facility_upgraded(facility_id: String, new_level: int)
signal npc_entered_casino(npc_data: NPCData)
signal casino_event_triggered(event_id: String)
signal casino_rating_changed(new_rating: int)

# ── 经济事件 ──
signal funds_changed(new_amount: int, delta: int)
signal bankruptcy_triggered(severity: int)
signal chapter_objective_updated(objective_id: String, progress: float)

# ── 进度 / 叙事 ──
signal chapter_completed(chapter_id: String)
signal npc_archive_unlocked(npc_id: String)
signal story_node_triggered(node_id: String)
signal ability_pool_updated(available_cards: Array[AbilityCardData])

# ── 游戏流程 ──
signal game_phase_changed(old_phase: int, new_phase: int)
signal run_started()
signal run_ended(result: StringName)
```

---

### 2.2 AudioManager
**职责**：BGM/SFX 播放调度、音频池管理、音量控制。

```
autoloads/AudioManager.gd
universal/audio/SFXPool.gd (RefCounted)    # 管理可用播放槽的索引/队列状态，不持有 Node 引用
universal/audio/AudioProfile.gd (Resource) # 音频配置（音量、循环、淡入淡出参数）
```

**关键行为**：
- 监听 `EventBus` 特定事件自动触发音效（如 `npc_trap_triggered` → 播放心跳加速音效）
- BGM 根据 `game_phase_changed` 切换曲目，支持交叉淡入淡出
- `AudioManager`（Node-based Autoload）持有所有 `AudioStreamPlayer` 节点实例；`SFXPool` 仅管理可用槽位的索引与排队状态，不持有任何 Node 引用，符合 RefCounted 禁止持有 Node 的约束

---

### 2.3 FeedbackSystem
**职责**：屏幕震动、粒子触发、UI 闪烁、动画调度，纯事件驱动，不持有游戏状态。

```
autoloads/FeedbackSystem.gd
universal/feedback/FeedbackProfile.gd (Resource) # 反馈配置：震动强度、粒子类型、持续时间
universal/feedback/ShakeController.gd (RefCounted)
```

**关键行为**：
- 订阅 EventBus，将游戏事件映射为视觉反馈
- 如 `npc_trap_triggered` → 屏幕红色边缘闪烁 + 轻微震动
- 如 `poker_session_ended(winner=player)` → 金币粒子爆发

---

### 2.4 UIManager
**职责**：场景切换、弹窗栈管理、loading 过渡动画。

```
autoloads/UIManager.gd
universal/ui/ModalStack.gd (RefCounted)    # 弹窗层级管理，支持 push/pop
universal/ui/SceneTransition.gd (RefCounted)
```

**关键行为**：
- 提供 `push_modal(scene_path)` / `pop_modal()` 接口
- 场景切换时统一处理加载进度与过渡动画
- 订阅 `game_phase_changed` 自动切换主场景

---

### 2.5 SaveManager
**职责**：存档序列化/反序列化、自动存档触发点管理。

```
autoloads/SaveManager.gd
universal/save/SaveData.gd (Resource)      # 存档数据结构（章节进度、NPC档案、设施状态）
universal/save/SaveSerializer.gd (RefCounted)
```

**存档包含内容**：
- 主线进度（已通关章节、触发的剧情节点）
- NPC 档案解锁状态
- 赌场设施状态（等级、数量）
- 能力池解锁上限

**不存档内容**（章节失败/破产后重置）：
- 当前章节内的资金积累
- 局内 Build

**自动存档触发点**：
- SETTLEMENT 阶段完成时（关卡结算后）
- 章节结算完成时（章节通关或重度破产后）
- 无局内自动存档，防止利用存档规避破产惩罚

---

### 2.6 AchievementSystem
**职责**：成就追踪、解锁判定、奖励触发。

```
autoloads/AchievementSystem.gd
universal/achievement/AchievementData.gd (Resource)  # 成就定义：触发条件、奖励
universal/achievement/AchievementTracker.gd (RefCounted)
```

**关键行为**：
- 订阅相关 EventBus 事件（如 `npc_trap_triggered` 计数）
- 成就解锁后通过 EventBus 广播，FeedbackSystem 和 UIManager 响应展示

---

### 2.7 ResourceCache
**职责**：资源预加载、缓存管理、异步加载封装。

```
autoloads/ResourceCache.gd
```

**关键行为**：
- 章节开始前预加载本章 NPC 资源、能力卡图片
- 提供同步/异步两种加载接口
- LRU 缓存策略，防止内存膨胀

---

### 2.8 InputManager
**职责**：输入映射抽象层，统一键鼠/触屏接口。

```
autoloads/InputManager.gd
```

**关键行为**：
- 将 Godot 输入事件转换为游戏语义动作（如 `ACTION_USE_ABILITY`）
- 通过 EventBus 广播，避免场景直接处理原始输入

---

## 三、核心玩法模块（Core Gameplay Modules）

---

### 3.1 游戏流程模块（Game Flow Module）
**职责**：主状态机，驱动章节推进与游戏阶段切换。

```
autoloads/GameManager.gd              # 主状态机，持有当前阶段

gameplay/game_flow/
├── GamePhase.gd                      # enum: CASINO / BUILD_SELECT / POKER / SETTLEMENT
├── ChapterData.gd (Resource)         # 章节定义：目标金额、规模要求、事件池、NPC池
├── RunState.gd (RefCounted)          # 当前局内状态：章节索引、已完成关卡、故事进度
└── ChapterObjectiveChecker.gd (RefCounted)  # 关卡目标达成判定（收益 + 规模 + 特殊条件）
```

**阶段切换流程与触发条件**：

```
章节开始（GameManager 初始化 RunState）
    ↓
CASINO（经营阶段）
  触发条件：玩家点击「开始牌局」按钮（玩家主动触发）
    ↓
BUILD_SELECT（选卡阶段）
  触发条件：AbilityDraftSystem 完成抽卡后，玩家确认选卡（玩家主动触发）
    ↓
POKER（牌局阶段）
  触发条件：PokerSessionMgr 检测到 poker_session_ended 信号（系统自动触发）
    ↓
SETTLEMENT（结算阶段）
  触发条件：ChapterObjectiveChecker 完成本关目标判定后自动推进
    - 通过 → 下一关卡（回到 CASINO）or 触发章节结算
    - 失败 → BankruptcyHandler 执行惩罚，根据严重程度重置或降级后回到 CASINO
```

`GameManager` 持有阶段状态机，所有阶段切换均通过 `game_phase_changed` 信号广播。`ChapterObjectiveChecker` 只负责判定并返回结果，由 `GameManager` 决定下一阶段。

---

### 3.2 经济模块（Economy Module）
**职责**：全局资金流转、破产判定、资产变更记录。

```
autoloads/EconomyManager.gd           # 资金总账，所有收支必须经此模块

gameplay/economy/
├── EconomyState.gd (RefCounted)      # 当前资金、本章累计收益、设施总投入
├── BankruptcyHandler.gd (RefCounted) # 破产层级判定（轻度/重度）、设施降级逻辑
└── EconomyTransaction.gd (RefCounted)# 单笔交易记录（类型、金额、来源）
```

**破产判定规则**：
- **轻度破产**：资金归零但本章尚有时间 → 随机降级1个设施，扣除部分积累资金
- **重度破产**：章节结算时未达收益目标 → 降级2-3个设施，当前章节重置（剧情碎片保留）

**跨模块触发路径**：`BankruptcyHandler` 判定完成后通知 `EconomyManager`，由 `EconomyManager` 在 EventBus 上发射 `bankruptcy_triggered(severity)` 信号；`CasinoManager` 订阅该信号并执行设施降级逻辑。`BankruptcyHandler` 不直接调用任何 Casino 模块内部类。

---

### 3.3 赌场经营模块（Casino Management Module）
**职责**：设施管理、NPC引流计算、经营事件处理、赌场规模评级。

```
autoloads/CasinoManager.gd            # 持有 CasinoState，对外暴露经营操作接口

gameplay/casino/
├── CasinoState.gd (RefCounted)       # 当前设施列表、赌场评级、被动流水收益率
├── FacilityData.gd (Resource)        # 设施定义：类型、等级上限、每级效果、联动能力卡ID
├── FacilityUpgrader.gd (RefCounted)  # 升级逻辑、费用计算、降级处理
├── NPCAttractionCalc.gd (RefCounted) # 根据设施组合计算各 NPC 出现权重
└── CasinoEventData.gd (Resource)     # 随机事件定义：类型、奖励/惩罚效果、触发条件
```

**设施-能力池联动规则**：
- 每个 `FacilityData` 携带 `unlocked_ability_ids: Array[String]`
- 设施升级/降级时，`CasinoManager` 发射 `facility_upgraded` 信号（EventBus）；`AbilityPoolManager` 订阅该信号，根据新等级重新计算当前可用卡池
- `FacilityUpgrader` 不直接调用 `AbilityPoolManager`，所有跨模块通知均通过 EventBus

---

### 3.4 NPC 模块（NPC Module）
**职责**：NPC 静态定义、三位一体心理引擎运行时实例、决策输出。

```
autoloads/NPCManager.gd               # 管理当前局内 NPC 实例池，广播 NPC 事件

gameplay/npc/
├── NPCData.gd (Resource)             # 静态定义：类型、阈值、陷阱类型、战利品、档案ID
├── NPCInstance.gd (RefCounted)       # 单个 NPC 运行时实例，持有三大系统引用
├── NPCPhysiologicalSys.gd (RefCounted)   # 兴奋度/压力实时计算
├── NPCRationalSys.gd (RefCounted)        # EV 计算与跟注/弃牌决策
├── NPCTrapSys.gd (RefCounted)            # 阈值监听，触发陷阱覆写决策
└── NPCDecisionResolver.gd (RefCounted)   # 整合三系统输出最终行动
```

**NPCInstance 生命周期**：
- **创建**：NPC 进入赌场时（CASINO 阶段），`NPCManager` 实例化对应 `NPCInstance`
- **持续**：`NPCInstance` 跨 CASINO 和 POKER 阶段全程存活，赌场阶段积累的生理状态（如酒吧被动效果）在进入牌局时保留
- **销毁**：SETTLEMENT 阶段结算完成后，`NPCManager` 释放本局所有 `NPCInstance`

**三系统优先级**：
```
NPCDecisionResolver 决策流程：
  1. NPCTrapSys.check_triggers() → 若陷阱激活，直接返回陷阱决策（覆写一切）
  2. NPCRationalSys.evaluate_ev() → 正常状态下按 EV 决策
  3. NPCPhysiologicalSys 的状态作为 EV 计算的权重修正输入
```

**NPC 分层**（对应 NPCData 的 `npc_tier` 字段）：
- `COMMON`：随机生成，自动进场，稳定流水
- `ELITE`：固定设计，需满足设施条件才出现，携带稀有能力卡
- `SPECIAL`：叙事事件触发，解锁剧情分支
- `BOSS`：章节推进自动触发，章节结局奖励

---

### 3.5 牌局引擎模块（Poker Engine Module）
**职责**：梭哈（五张种马）完整牌局逻辑。

```
autoloads/PokerSessionMgr.gd          # 牌局生命周期（开始/暂停/结束）

gameplay/poker/
├── CardData.gd (Resource)            # 单张牌定义（花色: Suit, 点数: Rank）
├── Deck.gd (RefCounted)              # 牌堆：洗牌、发牌、出千换牌操作
├── HandEvaluator.gd (RefCounted)     # 纯手牌比较逻辑（完整 TDD 覆盖）
├── PokerSessionState.gd (RefCounted) # 当前牌局状态：手牌、底池、当前轮次、行动窗口状态
├── BettingRoundCtrl.gd (RefCounted)  # 回合推进：行动窗口开关、NPC 决策调用时序
└── ShowdownResolver.gd (RefCounted)  # 摊牌胜负判定与筹码分配
```

**行动窗口（Action Window）机制**：
```
每轮下注前触发 ability_window_opened 信号
  → PlayerBuild 检查可用能力卡
  → 玩家消耗 AP 使用能力（AbilityEffectResolver 执行效果）
  → 行动窗口关闭，NPC 依次由 NPCDecisionResolver 输出决策
  → 进入下注阶段
```

**AP 规则**：
- 每局开始获得 **4 AP**，不跨局累计
- 情报类：2 AP，生理攻击类：1 AP，出千类：2 AP，环境联动类：1 AP

---

### 3.6 玩家能力模块（Player Ability Module）
**职责**：能力卡池管理、局内 Build 构建、AP 系统、能力效果执行。

```
autoloads/AbilityPoolManager.gd       # 根据设施等级维护当前可用能力卡池（有限集合）

gameplay/ability/
├── AbilityCardData.gd (Resource)     # 能力卡定义：AP消耗、效果类型、所需设施ID、流派标签
├── PlayerBuild.gd (RefCounted)       # 局内 Build：已选卡列表、剩余AP、冷却状态
├── AbilityDraftSystem.gd (RefCounted)# 开局抽卡逻辑（从池中抽5-7张，玩家选3张）
└── AbilityEffectResolver.gd (RefCounted) # 将能力效果应用到游戏状态（注入NPC系统/Deck操作）
```

**能力池边界**：池子大小由游戏内全部设施的升级层级总数决定，是有限集合，不会无界膨胀。

**效果执行路径**（AbilityEffectResolver）：

`AbilityEffectResolver` 不直接调用其他模块的 RefCounted 类。执行路径通过两种方式实现：

| 能力类型 | 执行方式 |
|---------|---------|
| 情报类 | 发射 `ability_used` 信号（EventBus）→ `NPCManager` 响应并返回情报数据 |
| 生理攻击类 | 发射 `ability_used` 信号（EventBus）→ `NPCManager` 内部调用 `NPCPhysiologicalSys.apply_modifier()` |
| 出千类 | 发射 `ability_used` 信号（EventBus）→ `PokerSessionMgr` 内部调用 `Deck.swap_card()` |
| 环境联动类 | 发射 `ability_used` 信号（EventBus）→ `NPCManager` 批量对当前桌 NPC 调用生理系统 |

`AbilityEffectResolver` 只负责判断能力类型并发射对应信号，具体执行由各模块的 Manager 完成，严格遵守跨模块通信规则。

**局内追加购买**：牌局中击败 NPC 后，`PokerSessionMgr` 发射 `poker_sub_round_won` 信号；`AbilityPoolManager` 响应后触发 `AbilityDraftSystem.offer_mid_session_draft(count: int)` 提供1-2张追加选卡机会。

---

### 3.7 叙事与进度模块（Narrative & Progression Module）
**职责**：主线剧情状态机、NPC 档案管理、对话触发、哈迪斯式碎片叙事。

```
autoloads/NarrativeManager.gd         # 叙事状态机，触发剧情节点

gameplay/narrative/
├── StoryState.gd (RefCounted)        # 已解锁剧情碎片 ID 集合、章节对话进度
├── NPCArchive.gd (Resource)          # NPC 档案：背景故事段落、弱点提示、解锁条件
├── DialogueData.gd (Resource)        # 对话树数据（支持条件分支、变量插值）
└── StoryNodeData.gd (Resource)       # 剧情节点定义：触发条件、效果（解锁档案/改变赌场状态）
```

**哈迪斯式叙事规则**：
- 每次击败精英/特殊 NPC → 解锁其 `NPCArchive` 的下一段故事
- 已触发的剧情碎片在破产重置后仍保留，玩家不会重复看到相同内容
- `NarrativeManager` 订阅 `poker_session_ended` 和 `npc_archive_unlocked` 自动推进

---

## 四、模块通信规则

```
原则：
  同模块内部     → 直接方法调用
  跨模块事件     → 统一通过 EventBus 广播
  Scene → 逻辑  → 调用 Autoload Manager 的公开方法
  逻辑 → Scene  → Manager 发射信号，Scene 监听后自行更新
```

**禁止的通信模式**：
- ❌ Scene 直接修改 RefCounted 状态
- ❌ RefCounted 持有 Node 引用
- ❌ 模块 A 的 Manager 直接调用模块 B 的内部 RefCounted 类

---

## 五、目录结构

```
src/
├── autoloads/                  # 所有 Autoload 单例（在 project.godot 注册）
│   ├── EventBus.gd
│   ├── GameManager.gd
│   ├── EconomyManager.gd
│   ├── CasinoManager.gd
│   ├── NPCManager.gd
│   ├── PokerSessionMgr.gd
│   ├── AbilityPoolManager.gd
│   ├── NarrativeManager.gd
│   ├── AudioManager.gd
│   ├── FeedbackSystem.gd
│   ├── UIManager.gd
│   ├── SaveManager.gd
│   ├── AchievementSystem.gd
│   ├── ResourceCache.gd
│   └── InputManager.gd
│
├── universal/                  # 通用模块数据类
│   ├── audio/
│   ├── feedback/
│   ├── ui/
│   ├── save/
│   └── achievement/
│
├── gameplay/                   # 核心玩法模块
│   ├── game_flow/
│   ├── economy/
│   ├── casino/
│   ├── npc/
│   ├── poker/
│   ├── ability/
│   └── narrative/
│
├── scenes/                     # 场景文件（纯表现层，不含业务逻辑）
│   ├── Main.tscn
│   ├── casino_dashboard/
│   ├── poker_table/
│   ├── chapter_map/
│   ├── build_selection/
│   └── hud/
│
└── tests/                      # GUT 测试，镜像 gameplay/ 目录结构
    ├── test_hand_evaluator.gd
    ├── test_npc_physiological_sys.gd
    ├── test_npc_trap_sys.gd
    ├── test_ability_effect_resolver.gd
    ├── test_bankruptcy_handler.gd
    └── test_chapter_objective_checker.gd
```

---

## 六、Godot 4 关键规范

```gdscript
# ✅ 正确：静态类型 + 新式信号连接
var stress_level: float = 0.0
func apply_modifier(delta: float) -> void:
    stress_level = clampf(stress_level + delta, 0.0, 100.0)
    EventBus.npc_physiological_changed.emit(npc_id, excitement, stress_level)

EventBus.npc_trap_triggered.connect(_on_trap_triggered)

# ✅ 正确：属性导出
@export var facility_level: int = 1

# ❌ 禁止：Godot 3 字符串连接语法
connect("signal_name", self, "_on_signal")

# ❌ 禁止：在 RefCounted 中持有 Node 引用
var _label: Label  # 绝对禁止出现在逻辑类中
```
