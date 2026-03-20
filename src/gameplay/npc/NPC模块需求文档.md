# NPC模块需求文档

**模块名称**：NPC Module  
**更新日期**：2026-03-20  
**版本**：1.0  
**状态**：草案  
**依赖架构**：技术架构设计文档 v1.2

---

## 一、模块定位

NPC模块负责管理游戏中所有NPC的**静态定义**、**三位一体心理引擎**和**决策输出**。该模块是实现"把对手的大脑当棋盘"核心体验的关键系统，通过生理系统、理性系统、陷阱系统三者的协同，构建可解释、可操控的对手行为模型。

### 核心职责

1. **NPC数据管理**：维护NPC静态定义（类型、阈值、弱点、战利品）
2. **三位一体心理引擎**：
   - 生理系统：兴奋度/压力的实时计算与波动
   - 理性系统：EV（期望值）决策逻辑
   - 陷阱系统：阈值触发的非理性行为覆写
3. **决策整合**：将三系统输出整合为最终行动
4. **运行时实例管理**：管理当前局内NPC的生命周期

---

## 二、数据结构定义

### 2.1 NPCData 静态定义资源

```gdscript
# gameplay/npc/NPCData.gd
class_name NPCData
extends Resource

## NPC层级枚举
enum NPCTier {
    COMMON,     # 普通：随机生成，自动进场
    ELITE,      # 精英：固定设计，需设施条件
    SPECIAL,    # 特殊：叙事事件触发
    BOSS        # Boss：章节推进触发
}

## NPC唯一标识
@export var npc_id: String

## NPC显示名称
@export var npc_name: String

## NPC层级
@export var npc_tier: NPCTier

## NPC描述
@export var description: String

## 头像资源
@export var portrait: Texture2D

## ── 心理系统配置 ──

## 生理系统：基础兴奋度
@export var base_excitement: float = 0.0

## 生理系统：基础压力值
@export var base_stress: float = 0.0

## 生理系统：兴奋度衰减率（每轮）
@export var excitement_decay: float = 5.0

## 生理系统：压力衰减率（每轮）
@export var stress_decay: float = 3.0

## 理性系统：EV判断阈值（低于此值倾向弃牌）
@export var ev_fold_threshold: float = 0.3

## 理性系统：EV加注阈值（高于此值倾向加注）
@export var ev_raise_threshold: float = 0.7

## ── 陷阱系统配置 ──

## 陷阱类型
@export var trap_type: TrapType

## 陷阱触发阈值
@export var trap_thresholds: Dictionary  # {threshold_type: value}

## 陷阱触发后的行为覆写
@export var trap_behavior: TrapBehavior

## ── 出现条件（精英/特殊NPC）──

## 最低赌场评级要求
@export var required_rating: int = 0

## 需要的设施及等级
@export var required_facilities: Dictionary  # {facility_id: min_level}

## 出现概率权重
@export var appearance_weight: float = 1.0

## ── 战利品 ──

## 击败奖励金额范围
@export var reward_range: Vector2i  # (min, max)

## 掉落的能力卡ID（精英/Boss）
@export var dropped_ability_ids: Array[String]

## 解锁的档案ID
@export var archive_id: String
```

### 2.2 TrapType 陷阱类型枚举

```gdscript
# gameplay/npc/TrapType.gd
class_name TrapType
extends RefCounted

enum Type {
    OVERCONFIDENCE,     # 过度自信：赢多时变得鲁莽
    LOSS_AVERSION,      # 损失厌恶：输掉部分资金后强制跟注
    TILT,               # 情绪失控：压力过高时全押
    GREED,              # 贪婪：看到大底池时强制跟注
    FEAR,               # 恐惧：对手表现强势时过早弃牌
    GAMBLER_FALLACY     # 赌徒谬误：连续输后认为必赢
}
```

### 2.3 TrapBehavior 陷阱行为定义

```gdscript
# gameplay/npc/TrapBehavior.gd
class_name TrapBehavior
extends Resource

## 陷阱触发后强制的行动类型
enum ForcedAction {
    ALL_IN,         # 强制全押
    MUST_CALL,      # 强制跟注
    MUST_RAISE,     # 强制加注
    MUST_FOLD       # 强制弃牌
}

## 强制行动
@export var forced_action: ForcedAction

## 加注倍率（MUST_RAISE时使用）
@export var raise_multiplier: float = 2.0

## 持续轮数（0表示仅当轮）
@export var duration_rounds: int = 0

## 触发后的生理状态变化
@export var physiological_effect: Dictionary  # {excitement: delta, stress: delta}
```

### 2.4 NPCInstance 运行时实例

```gdscript
# gameplay/npc/NPCInstance.gd
class_name NPCInstance
extends RefCounted

## 引用的静态数据
var npc_data: NPCData

## 实例唯一ID（区分同类型多个NPC）
var instance_id: String

## ── 三大子系统实例 ──
var physiological_sys: NPCPhysiologicalSys
var rational_sys: NPCRationalSys
var trap_sys: NPCTrapSys
var decision_resolver: NPCDecisionResolver

## ── 运行时状态 ──

## 当前资金
var current_funds: int = 0

## 本局已下注金额
var total_bet: int = 0

## 本局胜负记录
var win_count: int = 0
var loss_count: int = 0

## 是否已弃牌
var has_folded: bool = false

## 是否已全押
var is_all_in: bool = false

## ── 初始化 ──

func _init(data: NPCData, funds: int) -> void:
    npc_data = data
    instance_id = "%s_%d" % [data.npc_id, randi()]
    current_funds = funds
    
    # 初始化三大系统
    physiological_sys = NPCPhysiologicalSys.new(data)
    rational_sys = NPCRationalSys.new(data)
    trap_sys = NPCTrapSys.new(data)
    decision_resolver = NPCDecisionResolver.new(self)

## ── 轮次处理 ──

## 回合开始时更新状态
func on_round_start() -> void:
    physiological_sys.decay_values()

## 获取本轮决策
func get_decision(game_state: PokerSessionState) -> NPCDecision:
    return decision_resolver.resolve(game_state)

## 应用生理修正（来自玩家能力）
func apply_physiological_modifier(excitement_delta: float, stress_delta: float) -> void:
    physiological_sys.apply_modifier(excitement_delta, stress_delta)

## 记录胜负
func record_win() -> void:
    win_count += 1

func record_loss() -> void:
    loss_count += 1
```

### 2.5 NPCPhysiologicalSys 生理系统

```gdscript
# gameplay/npc/NPCPhysiologicalSys.gd
class_name NPCPhysiologicalSys
extends RefCounted

## 引用静态配置
var _config: NPCData

## ── 当前状态 ──

## 当前兴奋度（0-100）
var excitement: float = 0.0

## 当前压力值（0-100）
var stress: float = 0.0

## 基础修正器（来自设施被动效果）
var base_excitement_modifier: float = 0.0
var base_stress_modifier: float = 0.0

## ── 初始化 ──

func _init(config: NPCData) -> void:
    _config = config
    excitement = config.base_excitement
    stress = config.base_stress

## ── 状态操作 ──

## 应用修正器（来自玩家能力或牌局事件）
func apply_modifier(excitement_delta: float, stress_delta: float) -> void:
    excitement = clampf(excitement + excitement_delta, 0.0, 100.0)
    stress = clampf(stress + stress_delta, 0.0, 100.0)
    
    # 通过 EventBus 广播状态变化
    EventBus.npc_physiological_changed.emit(
        _config.npc_id,
        excitement,
        stress
    )

## 每轮衰减
func decay_values() -> void:
    excitement = maxf(0.0, excitement - _config.excitement_decay)
    stress = maxf(0.0, stress - _config.stress_decay)

## 设置基础修正器（进场时设施效果）
func set_base_modifiers(excitement_mod: float, stress_mod: float) -> void:
    base_excitement_modifier = excitement_mod
    base_stress_modifier = stress_mod
    apply_modifier(excitement_mod, stress_mod)

## ── 状态查询 ──

## 获取当前有效兴奋度
func get_effective_excitement() -> float:
    return excitement

## 获取当前有效压力值
func get_effective_stress() -> float:
    return stress

## 获取生理状态对EV的修正系数
## 高兴奋度 → 更激进（EV阈值降低）
## 高压力 → 更保守或更冲动（取决于陷阱类型）
func get_ev_modifier() -> float:
    var excitement_factor := (excitement - 50.0) / 100.0  # -0.5 到 0.5
    var stress_factor := (stress - 50.0) / 100.0
    
    # 兴奋度高时倾向加注，压力高时决策更极端
    return 1.0 + excitement_factor * 0.3 + stress_factor * 0.2
```

### 2.6 NPCRationalSys 理性系统

```gdscript
# gameplay/npc/NPCRationalSys.gd
class_name NPCRationalSys
extends RefCounted

## 引用静态配置
var _config: NPCData

## ── 决策枚举 ──
enum RationalDecision {
    FOLD,       # 弃牌
    CHECK,      # 过牌
    CALL,       # 跟注
    RAISE,      # 加注
    ALL_IN      # 全押
}

## ── 初始化 ──

func _init(config: NPCData) -> void:
    _config = config

## ── EV计算 ──

## 计算当前手牌的期望值
## @param hand: 当前手牌
## @param visible_cards: 所有可见的牌
## @param pot: 当前底池
## @param to_call: 需要跟注的金额
## @return: 期望值（0.0 - 1.0）
func evaluate_ev(
    hand: Array[CardData],
    visible_cards: Array[CardData],
    pot: int,
    to_call: int
) -> float:
    # 计算手牌强度
    var hand_strength := _calculate_hand_strength(hand, visible_cards)
    
    # 计算赔率
    var pot_odds := float(to_call) / float(pot + to_call) if pot + to_call > 0 else 0.0
    
    # EV = 手牌强度 - 需要投入的比例
    var ev := hand_strength - pot_odds
    
    return clampf(ev, 0.0, 1.0)

## 基于EV做出理性决策
func make_rational_decision(
    ev: float,
    ev_modifier: float,
    to_call: int,
    current_funds: int
) -> RationalDecision:
    var adjusted_ev := ev * ev_modifier
    
    # 无需跟注时
    if to_call == 0:
        if adjusted_ev >= _config.ev_raise_threshold:
            return RationalDecision.RAISE
        return RationalDecision.CHECK
    
    # 需要跟注时
    if adjusted_ev < _config.ev_fold_threshold:
        return RationalDecision.FOLD
    elif adjusted_ev >= _config.ev_raise_threshold:
        if current_funds > to_call * 3:
            return RationalDecision.RAISE
        return RationalDecision.CALL
    else:
        return RationalDecision.CALL

## ── 私有方法 ──

## 计算手牌强度（考虑完成牌和潜在牌）
func _calculate_hand_strength(
    hand: Array[CardData],
    visible_cards: Array[CardData]
) -> float:
    # 使用 HandEvaluator 进行评估
    # 返回 0.0-1.0 的强度值
    pass
```

### 2.7 NPCTrapSys 陷阱系统

```gdscript
# gameplay/npc/NPCTrapSys.gd
class_name NPCTrapSys
extends RefCounted

## 引用静态配置
var _config: NPCData

## 陷阱是否已触发（部分陷阱只能触发一次）
var _trap_triggered: bool = false

## 陷阱剩余持续轮数
var _trap_remaining_rounds: int = 0

## ── 初始化 ──

func _init(config: NPCData) -> void:
    _config = config

## ── 阈值检查 ──

## 检查陷阱是否触发
## @param physiological_state: 生理系统状态
## @param game_context: 游戏上下文（资金变化、底池大小等）
## @return: 是否触发陷阱
func check_triggers(
    physiological_state: NPCPhysiologicalSys,
    game_context: Dictionary
) -> bool:
    if _trap_remaining_rounds > 0:
        return true  # 陷阱效果仍在持续
    
    var triggered := false
    
    match _config.trap_type:
        TrapType.Type.OVERCONFIDENCE:
            triggered = _check_overconfidence(physiological_state, game_context)
        TrapType.Type.LOSS_AVERSION:
            triggered = _check_loss_aversion(game_context)
        TrapType.Type.TILT:
            triggered = _check_tilt(physiological_state)
        TrapType.Type.GREED:
            triggered = _check_greed(game_context)
        TrapType.Type.FEAR:
            triggered = _check_fear(physiological_state, game_context)
        TrapType.Type.GAMBLER_FALLACY:
            triggered = _check_gambler_fallacy(game_context)
    
    if triggered and not _trap_triggered:
        _trap_triggered = true
        _trap_remaining_rounds = _config.trap_behavior.duration_rounds
        
        # 通过 EventBus 广播陷阱触发
        EventBus.npc_trap_triggered.emit(_config.npc_id, _config.trap_type)
    
    return triggered

## 获取陷阱强制行为
func get_forced_action() -> TrapBehavior:
    if _trap_remaining_rounds > 0 or _trap_triggered:
        return _config.trap_behavior
    return null

## 轮次结束时更新
func on_round_end() -> void:
    if _trap_remaining_rounds > 0:
        _trap_remaining_rounds -= 1

## ── 各类陷阱检查实现 ──

func _check_overconfidence(state: NPCPhysiologicalSys, context: Dictionary) -> bool:
    var excitement_threshold: float = _config.trap_thresholds.get("excitement", 80.0)
    var win_streak: int = context.get("win_streak", 0)
    var win_threshold: int = _config.trap_thresholds.get("win_count", 2)
    
    return state.excitement >= excitement_threshold or win_streak >= win_threshold

func _check_loss_aversion(context: Dictionary) -> bool:
    var loss_ratio: float = context.get("loss_ratio", 0.0)  # 已输掉的资金比例
    var threshold: float = _config.trap_thresholds.get("loss_ratio", 0.3)
    
    return loss_ratio >= threshold

func _check_tilt(state: NPCPhysiologicalSys) -> bool:
    var stress_threshold: float = _config.trap_thresholds.get("stress", 85.0)
    return state.stress >= stress_threshold

func _check_greed(context: Dictionary) -> bool:
    var pot: int = context.get("pot", 0)
    var pot_threshold: int = _config.trap_thresholds.get("pot_threshold", 10000)
    
    return pot >= pot_threshold

func _check_fear(state: NPCPhysiologicalSys, context: Dictionary) -> bool:
    var stress_threshold: float = _config.trap_thresholds.get("stress", 70.0)
    var opponent_aggression: float = context.get("opponent_aggression", 0.0)
    
    return state.stress >= stress_threshold and opponent_aggression > 0.7

func _check_gambler_fallacy(context: Dictionary) -> bool:
    var loss_streak: int = context.get("loss_streak", 0)
    var threshold: int = _config.trap_thresholds.get("loss_streak", 3)
    
    return loss_streak >= threshold
```

### 2.8 NPCDecisionResolver 决策整合器

```gdscript
# gameplay/npc/NPCDecisionResolver.gd
class_name NPCDecisionResolver
extends RefCounted

## NPC实例引用
var _npc: NPCInstance

## ── 决策结果 ──
class NPCDecision:
    extends RefCounted
    
    enum Action {
        FOLD,
        CHECK,
        CALL,
        RAISE,
        ALL_IN
    }
    
    var action: Action
    var amount: int = 0
    var is_trap_forced: bool = false
    var reasoning: String = ""  # 调试用

## ── 初始化 ──

func _init(npc: NPCInstance) -> void:
    _npc = npc

## ── 决策流程 ──

## 整合三系统输出最终决策
## 优先级：陷阱系统 > 理性系统（受生理系统修正）
func resolve(game_state: PokerSessionState) -> NPCDecision:
    var decision := NPCDecision.new()
    
    # 构建游戏上下文
    var context := _build_game_context(game_state)
    
    # 1. 检查陷阱系统
    if _npc.trap_sys.check_triggers(_npc.physiological_sys, context):
        var forced := _npc.trap_sys.get_forced_action()
        if forced:
            decision = _apply_trap_behavior(forced, game_state)
            decision.is_trap_forced = true
            decision.reasoning = "陷阱触发: %s" % TrapType.Type.keys()[_npc.npc_data.trap_type]
            
            # 广播决策
            EventBus.npc_decision_made.emit(
                _npc.npc_data.npc_id,
                NPCDecision.Action.keys()[decision.action],
                decision.amount
            )
            return decision
    
    # 2. 正常流程：理性系统决策（受生理修正）
    var ev := _npc.rational_sys.evaluate_ev(
        game_state.get_npc_hand(_npc.instance_id),
        game_state.get_visible_cards(),
        game_state.pot,
        game_state.to_call
    )
    
    var ev_modifier := _npc.physiological_sys.get_ev_modifier()
    var rational_decision := _npc.rational_sys.make_rational_decision(
        ev,
        ev_modifier,
        game_state.to_call,
        _npc.current_funds
    )
    
    decision = _convert_rational_decision(rational_decision, game_state)
    decision.reasoning = "EV=%.2f, modifier=%.2f" % [ev, ev_modifier]
    
    # 广播决策
    EventBus.npc_decision_made.emit(
        _npc.npc_data.npc_id,
        NPCDecision.Action.keys()[decision.action],
        decision.amount
    )
    
    return decision

## ── 私有方法 ──

func _build_game_context(game_state: PokerSessionState) -> Dictionary:
    return {
        "pot": game_state.pot,
        "win_streak": _npc.win_count,
        "loss_streak": _npc.loss_count,
        "loss_ratio": 1.0 - float(_npc.current_funds) / float(_npc.npc_data.reward_range.y),
        "opponent_aggression": game_state.get_player_aggression_level()
    }

func _apply_trap_behavior(behavior: TrapBehavior, game_state: PokerSessionState) -> NPCDecision:
    var decision := NPCDecision.new()
    
    match behavior.forced_action:
        TrapBehavior.ForcedAction.ALL_IN:
            decision.action = NPCDecision.Action.ALL_IN
            decision.amount = _npc.current_funds
        TrapBehavior.ForcedAction.MUST_CALL:
            decision.action = NPCDecision.Action.CALL
            decision.amount = mini(game_state.to_call, _npc.current_funds)
        TrapBehavior.ForcedAction.MUST_RAISE:
            decision.action = NPCDecision.Action.RAISE
            decision.amount = mini(
                int(game_state.to_call * behavior.raise_multiplier),
                _npc.current_funds
            )
        TrapBehavior.ForcedAction.MUST_FOLD:
            decision.action = NPCDecision.Action.FOLD
            decision.amount = 0
    
    return decision

func _convert_rational_decision(
    rational: NPCRationalSys.RationalDecision,
    game_state: PokerSessionState
) -> NPCDecision:
    var decision := NPCDecision.new()
    
    match rational:
        NPCRationalSys.RationalDecision.FOLD:
            decision.action = NPCDecision.Action.FOLD
        NPCRationalSys.RationalDecision.CHECK:
            decision.action = NPCDecision.Action.CHECK
        NPCRationalSys.RationalDecision.CALL:
            decision.action = NPCDecision.Action.CALL
            decision.amount = mini(game_state.to_call, _npc.current_funds)
        NPCRationalSys.RationalDecision.RAISE:
            decision.action = NPCDecision.Action.RAISE
            decision.amount = mini(game_state.to_call * 2, _npc.current_funds)
        NPCRationalSys.RationalDecision.ALL_IN:
            decision.action = NPCDecision.Action.ALL_IN
            decision.amount = _npc.current_funds
    
    return decision
```

---

## 三、Autoload 接口设计

### 3.1 NPCManager 单例

```gdscript
# autoloads/NPCManager.gd
extends Node

## ── 信号定义 ──
signal npc_instance_created(instance_id: String, npc_data: NPCData)
signal npc_instance_destroyed(instance_id: String)
signal npc_physiological_changed(npc_id: String, excitement: float, stress: float)
signal npc_trap_triggered(npc_id: String, trap_type: int)
signal npc_decision_made(npc_id: String, action: StringName, amount: int)

## ── 状态持有 ──
var _active_instances: Dictionary = {}  # {instance_id: NPCInstance}
var _npc_data_cache: Dictionary = {}    # {npc_id: NPCData}

## ── 实例生命周期 ──

## 创建NPC实例（NPC进入赌场时调用）
func create_instance(npc_id: String, initial_funds: int) -> NPCInstance:
    var data := get_npc_data(npc_id)
    if not data:
        push_error("NPC data not found: %s" % npc_id)
        return null
    
    var instance := NPCInstance.new(data, initial_funds)
    _active_instances[instance.instance_id] = instance
    
    npc_instance_created.emit(instance.instance_id, data)
    return instance

## 销毁NPC实例（结算阶段调用）
func destroy_instance(instance_id: String) -> void:
    if _active_instances.has(instance_id):
        _active_instances.erase(instance_id)
        npc_instance_destroyed.emit(instance_id)

## 销毁所有实例
func destroy_all_instances() -> void:
    for instance_id in _active_instances.keys():
        destroy_instance(instance_id)

## ── 获取实例 ──

func get_instance(instance_id: String) -> NPCInstance:
    return _active_instances.get(instance_id)

func get_all_active_instances() -> Array[NPCInstance]:
    var result: Array[NPCInstance] = []
    for instance in _active_instances.values():
        result.append(instance)
    return result

## ── 数据访问 ──

func get_npc_data(npc_id: String) -> NPCData:
    if not _npc_data_cache.has(npc_id):
        var data := ResourceCache.load_npc_data(npc_id)
        if data:
            _npc_data_cache[npc_id] = data
    return _npc_data_cache.get(npc_id)

## ── 生理系统操作（响应能力效果）──

## 应用生理修正（来自玩家能力）
func apply_physiological_effect(instance_id: String, excitement: float, stress: float) -> void:
    var instance := get_instance(instance_id)
    if instance:
        instance.apply_physiological_modifier(excitement, stress)

## 批量应用生理修正（环境联动类能力）
func apply_physiological_effect_all(excitement: float, stress: float) -> void:
    for instance in _active_instances.values():
        instance.apply_physiological_modifier(excitement, stress)

## ── 情报查询（响应能力效果）──

## 获取NPC档案信息（情报类能力）
func get_npc_archive_info(npc_id: String) -> Dictionary:
    var data := get_npc_data(npc_id)
    if not data:
        return {}
    
    return {
        "trap_type": data.trap_type,
        "trap_thresholds": data.trap_thresholds,
        "ev_fold_threshold": data.ev_fold_threshold,
        "ev_raise_threshold": data.ev_raise_threshold
    }

## ── EventBus 订阅 ──

func _ready() -> void:
    EventBus.ability_used.connect(_on_ability_used)
    EventBus.game_phase_changed.connect(_on_game_phase_changed)

func _on_ability_used(card_id: String, ability_type: StringName, target_npc_id: String) -> void:
    # 响应能力使用
    var ability_data := ResourceCache.load_ability_data(card_id)
    if not ability_data:
        return
    
    match ability_type:
        &"physiological_attack":
            if target_npc_id.is_empty():
                # 全体效果
                apply_physiological_effect_all(
                    ability_data.excitement_delta,
                    ability_data.stress_delta
                )
            else:
                # 单体效果
                apply_physiological_effect(
                    target_npc_id,
                    ability_data.excitement_delta,
                    ability_data.stress_delta
                )
        &"intel":
            # 情报类能力由 UI 层处理展示
            pass

func _on_game_phase_changed(old_phase: int, new_phase: int) -> void:
    if new_phase == GamePhase.Phase.SETTLEMENT:
        # 结算阶段销毁所有实例
        destroy_all_instances()
```

---

## 四、三系统协作流程

### 4.1 决策流程图

```
NPC轮到行动
    ↓
NPCDecisionResolver.resolve(game_state)
    ↓
┌─────────────────────────────────────────────┐
│ 1. NPCTrapSys.check_triggers()              │
│    检查生理阈值、游戏上下文是否触发陷阱     │
└─────────────────────────────────────────────┘
    ↓
陷阱触发?
    ├── 是 → 返回陷阱强制行为（覆写一切）
    │         └── 发射 npc_trap_triggered 信号
    └── 否 ↓
┌─────────────────────────────────────────────┐
│ 2. NPCRationalSys.evaluate_ev()             │
│    计算手牌期望值                            │
│    ↓                                        │
│ 3. NPCPhysiologicalSys.get_ev_modifier()    │
│    获取生理状态对EV的修正                    │
│    ↓                                        │
│ 4. NPCRationalSys.make_rational_decision()  │
│    基于修正后的EV做理性决策                  │
└─────────────────────────────────────────────┘
    ↓
返回最终决策
    └── 发射 npc_decision_made 信号
```

### 4.2 玩家能力影响路径

```
玩家使用能力
    ↓
AbilityEffectResolver 发射 ability_used 信号
    ↓
NPCManager 订阅信号
    ├── 生理攻击类 → apply_physiological_effect()
    │                └── NPCPhysiologicalSys.apply_modifier()
    │                      └── 发射 npc_physiological_changed
    └── 情报类 → 返回档案信息供 UI 展示
```

---

## 五、EventBus 信号交互

### 5.1 发射的信号

| 信号名称 | 参数 | 触发时机 |
|----------|------|----------|
| npc_physiological_changed | npc_id, excitement, stress | 生理状态变化时 |
| npc_trap_triggered | npc_id, trap_type | 陷阱触发时 |
| npc_decision_made | npc_id, action, amount | NPC做出决策时 |

### 5.2 监听的信号

| 信号名称 | 来源模块 | 响应行为 |
|----------|----------|----------|
| ability_used | AbilityEffectResolver | 执行能力效果 |
| game_phase_changed | GameManager | SETTLEMENT阶段销毁实例 |
| npc_entered_casino | CasinoManager | 应用设施被动效果 |

---

## 六、测试要点

### 6.1 生理系统测试

```gdscript
# tests/test_npc/test_npc_physiological_sys.gd

## 测试修正器应用
func test_apply_modifier():
    var config := _create_test_npc_data()
    var sys := NPCPhysiologicalSys.new(config)
    sys.apply_modifier(25.0, 15.0)
    assert_eq(sys.excitement, 25.0)
    assert_eq(sys.stress, 15.0)

## 测试值域边界
func test_clamp_values():
    var sys := NPCPhysiologicalSys.new(_create_test_npc_data())
    sys.apply_modifier(150.0, 200.0)
    assert_eq(sys.excitement, 100.0)
    assert_eq(sys.stress, 100.0)
    
    sys.apply_modifier(-300.0, -300.0)
    assert_eq(sys.excitement, 0.0)
    assert_eq(sys.stress, 0.0)

## 测试衰减
func test_decay_values():
    var config := _create_test_npc_data()
    config.excitement_decay = 10.0
    config.stress_decay = 5.0
    
    var sys := NPCPhysiologicalSys.new(config)
    sys.apply_modifier(50.0, 30.0)
    sys.decay_values()
    
    assert_eq(sys.excitement, 40.0)
    assert_eq(sys.stress, 25.0)
```

### 6.2 陷阱系统测试

```gdscript
# tests/test_npc/test_npc_trap_sys.gd

## 测试过度自信陷阱触发
func test_overconfidence_trigger():
    var config := _create_overconfidence_npc()
    var trap_sys := NPCTrapSys.new(config)
    var physio_sys := NPCPhysiologicalSys.new(config)
    
    physio_sys.apply_modifier(85.0, 0.0)  # 高兴奋度
    
    var triggered := trap_sys.check_triggers(physio_sys, {"win_streak": 0})
    assert_true(triggered)

## 测试损失厌恶陷阱触发
func test_loss_aversion_trigger():
    var config := _create_loss_aversion_npc()
    var trap_sys := NPCTrapSys.new(config)
    var physio_sys := NPCPhysiologicalSys.new(config)
    
    var triggered := trap_sys.check_triggers(physio_sys, {"loss_ratio": 0.35})
    assert_true(triggered)

## 测试陷阱强制行为
func test_trap_forced_action():
    var config := _create_overconfidence_npc()
    config.trap_behavior.forced_action = TrapBehavior.ForcedAction.ALL_IN
    
    var trap_sys := NPCTrapSys.new(config)
    trap_sys._trap_triggered = true
    
    var behavior := trap_sys.get_forced_action()
    assert_eq(behavior.forced_action, TrapBehavior.ForcedAction.ALL_IN)
```

### 6.3 决策整合测试

```gdscript
# tests/test_npc/test_npc_decision_resolver.gd

## 测试陷阱优先级
func test_trap_overrides_rational():
    # 即使EV很低，陷阱触发时仍执行陷阱行为
    pass

## 测试生理修正影响决策
func test_physiological_modifier_affects_decision():
    # 高兴奋度使NPC更激进
    pass

## 测试正常理性决策
func test_normal_rational_decision():
    # 无陷阱时按EV决策
    pass
```

---

## 七、扩展预留

### 7.1 NPC对话系统

```gdscript
## NPC牌局中的对话/表情反馈
var dialogue_triggers: Dictionary = {
    "high_excitement": ["哈哈，今天手气不错！", "再来！"],
    "high_stress": ["...冷静，冷静...", "该死..."],
    "trap_triggered": ["我不会输的！", "全押！"]
}
```

### 7.2 NPC记忆系统

```gdscript
## 跨牌局的玩家行为记忆
## 影响NPC对玩家的判断
var player_memory: Dictionary = {
    "bluff_frequency": 0.0,
    "aggression_level": 0.0
}
```

---

## 八、依赖关系

### 8.1 本模块依赖

- **ResourceCache**：加载NPC数据
- **PokerSessionMgr**：获取牌局状态（通过 PokerSessionState）

### 8.2 依赖本模块的模块

- **PokerSessionMgr**：获取NPC决策
- **AbilityEffectResolver**：通过信号触发生理效果
- **NarrativeManager**：获取NPC档案信息

---

## 九、文档版本历史

| 版本 | 日期 | 修改内容 | 作者 |
|------|------|----------|------|
| 1.0 | 2026-03-20 | 初始版本 | - |
