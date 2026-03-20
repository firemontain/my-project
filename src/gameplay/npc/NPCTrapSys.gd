## NPCTrapSys.gd
## NPC陷阱系统 - 当生理指标达到阈值时触发非理性行为
class_name NPCTrapSys
extends RefCounted

## 陷阱类型枚举
enum TrapType {
	OVERCONFIDENCE,     ## 过度自信：赢多时变得鲁莽
	LOSS_AVERSION,      ## 损失厌恶：输掉部分资金后强制跟注
	TILT,               ## 情绪失控：压力过高时全押
	GREED,              ## 贪婪：看到大底池时强制跟注
	FEAR,               ## 恐惧：对手表现强势时过早弃牌
	GAMBLER_FALLACY     ## 赌徒谬误：连续输后认为必赢
}

## 强制行动类型
enum ForcedAction {
	NONE,           ## 无强制行动
	ALL_IN,         ## 强制全押
	MUST_CALL,      ## 强制跟注
	MUST_RAISE,     ## 强制加注
	MUST_FOLD       ## 强制弃牌
}

## 信号：陷阱触发
signal trap_triggered(trap_type: TrapType, forced_action: ForcedAction)

## 当前陷阱类型
var trap_type: TrapType

## 陷阱触发阈值
var excitement_threshold: float = 80.0
var stress_threshold: float = 85.0
var loss_ratio_threshold: float = 0.3
var pot_threshold: int = 10000
var loss_streak_threshold: int = 3

## 陷阱是否已触发
var _trap_triggered: bool = false

## 陷阱剩余持续轮数
var _trap_remaining_rounds: int = 0

## 触发后的强制行动
var _forced_action: ForcedAction = ForcedAction.NONE

## 加注倍率（MUST_RAISE时使用）
var raise_multiplier: float = 2.0


## 初始化
func _init(p_trap_type: TrapType = TrapType.OVERCONFIDENCE) -> void:
	trap_type = p_trap_type
	_setup_default_thresholds()


## 根据陷阱类型设置默认阈值
func _setup_default_thresholds() -> void:
	match trap_type:
		TrapType.OVERCONFIDENCE:
			excitement_threshold = 80.0
			_forced_action = ForcedAction.ALL_IN
		TrapType.LOSS_AVERSION:
			loss_ratio_threshold = 0.3
			_forced_action = ForcedAction.MUST_CALL
		TrapType.TILT:
			stress_threshold = 85.0
			_forced_action = ForcedAction.ALL_IN
		TrapType.GREED:
			pot_threshold = 10000
			_forced_action = ForcedAction.MUST_CALL
		TrapType.FEAR:
			stress_threshold = 70.0
			_forced_action = ForcedAction.MUST_FOLD
		TrapType.GAMBLER_FALLACY:
			loss_streak_threshold = 3
			_forced_action = ForcedAction.ALL_IN


## 检查陷阱是否触发
## @param physio_state: 生理系统状态
## @param game_context: 游戏上下文（资金变化、底池大小等）
## @return: 是否触发陷阱
func check_triggers(physio_state: NPCPhysiologicalSys, game_context: Dictionary) -> bool:
	if _trap_remaining_rounds > 0:
		return true  # 陷阱效果仍在持续
	
	var triggered := false
	
	match trap_type:
		TrapType.OVERCONFIDENCE:
			triggered = _check_overconfidence(physio_state, game_context)
		TrapType.LOSS_AVERSION:
			triggered = _check_loss_aversion(game_context)
		TrapType.TILT:
			triggered = _check_tilt(physio_state)
		TrapType.GREED:
			triggered = _check_greed(game_context)
		TrapType.FEAR:
			triggered = _check_fear(physio_state, game_context)
		TrapType.GAMBLER_FALLACY:
			triggered = _check_gambler_fallacy(game_context)
	
	if triggered and not _trap_triggered:
		_trap_triggered = true
		_trap_remaining_rounds = 1  # 持续1轮
		trap_triggered.emit(trap_type, _forced_action)
	
	return triggered


## 获取陷阱强制行动
func get_forced_action() -> ForcedAction:
	if _trap_remaining_rounds > 0 or _trap_triggered:
		return _forced_action
	return ForcedAction.NONE


## 轮次结束时更新
func on_round_end() -> void:
	if _trap_remaining_rounds > 0:
		_trap_remaining_rounds -= 1
		if _trap_remaining_rounds == 0:
			_trap_triggered = false


## 重置陷阱状态
func reset() -> void:
	_trap_triggered = false
	_trap_remaining_rounds = 0


## 获取陷阱类型描述
func get_trap_description() -> String:
	match trap_type:
		TrapType.OVERCONFIDENCE:
			return "过度自信 - 高兴奋度时全押"
		TrapType.LOSS_AVERSION:
			return "损失厌恶 - 输钱后强制跟注"
		TrapType.TILT:
			return "情绪失控 - 高压力时全押"
		TrapType.GREED:
			return "贪婪 - 大底池时强制跟注"
		TrapType.FEAR:
			return "恐惧 - 受压时弃牌"
		TrapType.GAMBLER_FALLACY:
			return "赌徒谬误 - 连输后全押"
	return "未知陷阱"


# ── 各类陷阱检查实现 ──

func _check_overconfidence(state: NPCPhysiologicalSys, context: Dictionary) -> bool:
	var win_streak: int = context.get("win_streak", 0)
	var win_count_threshold: int = context.get("win_count_threshold", 2)
	return state.excitement >= excitement_threshold or win_streak >= win_count_threshold


func _check_loss_aversion(context: Dictionary) -> bool:
	var loss_ratio: float = context.get("loss_ratio", 0.0)  # 已输掉的资金比例
	return loss_ratio >= loss_ratio_threshold


func _check_tilt(state: NPCPhysiologicalSys) -> bool:
	return state.stress >= stress_threshold


func _check_greed(context: Dictionary) -> bool:
	var pot: int = context.get("pot", 0)
	return pot >= pot_threshold


func _check_fear(state: NPCPhysiologicalSys, context: Dictionary) -> bool:
	var opponent_aggression: float = context.get("opponent_aggression", 0.0)
	return state.stress >= stress_threshold and opponent_aggression > 0.7


func _check_gambler_fallacy(context: Dictionary) -> bool:
	var loss_streak: int = context.get("loss_streak", 0)
	return loss_streak >= loss_streak_threshold
