## NPCDecisionResolver.gd
## NPC决策整合器 - 整合三系统输出最终行动
class_name NPCDecisionResolver
extends RefCounted

## 行动类型枚举
enum Action {
	FOLD,       ## 弃牌
	CHECK,      ## 过牌
	CALL,       ## 跟注
	RAISE,      ## 加注
	ALL_IN      ## 全押
}

## 决策结果类
class NPCDecision:
	var action: Action
	var amount: int = 0
	var is_trap_forced: bool = false
	var reasoning: String = ""
	
	func _init() -> void:
		action = Action.FOLD


## 引用各子系统
var physiological_sys: NPCPhysiologicalSys
var rational_sys: NPCRationalSys
var trap_sys: NPCTrapSys

## NPC当前资金
var current_funds: int = 0


## 初始化
func _init(p_physio: NPCPhysiologicalSys, p_rational: NPCRationalSys, p_trap: NPCTrapSys) -> void:
	physiological_sys = p_physio
	rational_sys = p_rational
	trap_sys = p_trap


## 整合三系统输出最终决策
## 优先级：陷阱系统 > 理性系统（受生理系统修正）
func resolve(hand: Array[CardData], visible_cards: Array[CardData], 
			 pot: int, to_call: int, game_context: Dictionary) -> NPCDecision:
	var decision := NPCDecision.new()
	
	# 1. 检查陷阱系统
	if trap_sys.check_triggers(physiological_sys, game_context):
		var forced := trap_sys.get_forced_action()
		if forced != NPCTrapSys.ForcedAction.NONE:
			decision = _apply_trap_behavior(forced, pot, to_call)
			decision.is_trap_forced = true
			decision.reasoning = "陷阱触发: %s" % trap_sys.get_trap_description()
			return decision
	
	# 2. 正常流程：理性系统决策（受生理修正）
	var ev := rational_sys.evaluate_ev(hand, visible_cards, pot, to_call)
	var ev_modifier := physiological_sys.get_ev_modifier()
	var rational_decision := rational_sys.make_rational_decision(ev, ev_modifier, to_call, current_funds)
	
	decision = _convert_rational_decision(rational_decision, ev, pot, to_call)
	decision.reasoning = "EV=%.2f, modifier=%.2f" % [ev, ev_modifier]
	
	return decision


## 应用陷阱行为
func _apply_trap_behavior(forced: NPCTrapSys.ForcedAction, pot: int, to_call: int) -> NPCDecision:
	var decision := NPCDecision.new()
	
	match forced:
		NPCTrapSys.ForcedAction.ALL_IN:
			decision.action = Action.ALL_IN
			decision.amount = current_funds
		NPCTrapSys.ForcedAction.MUST_CALL:
			decision.action = Action.CALL
			decision.amount = mini(to_call, current_funds)
		NPCTrapSys.ForcedAction.MUST_RAISE:
			decision.action = Action.RAISE
			var raise_amount := int(to_call * trap_sys.raise_multiplier)
			decision.amount = mini(raise_amount, current_funds)
		NPCTrapSys.ForcedAction.MUST_FOLD:
			decision.action = Action.FOLD
			decision.amount = 0
	
	return decision


## 转换理性决策
func _convert_rational_decision(rational: NPCRationalSys.RationalDecision, 
								 ev: float, pot: int, to_call: int) -> NPCDecision:
	var decision := NPCDecision.new()
	
	match rational:
		NPCRationalSys.RationalDecision.FOLD:
			decision.action = Action.FOLD
		NPCRationalSys.RationalDecision.CHECK:
			decision.action = Action.CHECK
		NPCRationalSys.RationalDecision.CALL:
			decision.action = Action.CALL
			decision.amount = mini(to_call, current_funds)
		NPCRationalSys.RationalDecision.RAISE:
			decision.action = Action.RAISE
			decision.amount = rational_sys.calculate_raise_amount(ev, pot, to_call, current_funds)
		NPCRationalSys.RationalDecision.ALL_IN:
			decision.action = Action.ALL_IN
			decision.amount = current_funds
	
	return decision


## 获取行动描述
static func get_action_description(action: Action, amount: int = 0) -> String:
	match action:
		Action.FOLD:
			return "弃牌"
		Action.CHECK:
			return "过牌"
		Action.CALL:
			return "跟注 %d" % amount
		Action.RAISE:
			return "加注到 %d" % amount
		Action.ALL_IN:
			return "全押 %d" % amount
	return "未知行动"
