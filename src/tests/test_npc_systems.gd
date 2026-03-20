## test_npc_systems.gd
## NPC心理系统单元测试
extends GutTest


## 测试生理系统 - 修正器应用
func test_physiological_apply_modifier() -> void:
	var sys := NPCPhysiologicalSys.new(0.0, 0.0)
	sys.apply_modifier(25.0, 15.0)
	assert_eq(sys.excitement, 25.0, "Excitement should be 25")
	assert_eq(sys.stress, 15.0, "Stress should be 15")


## 测试生理系统 - 值域边界
func test_physiological_clamp_values() -> void:
	var sys := NPCPhysiologicalSys.new(50.0, 50.0)
	
	# 测试上限
	sys.apply_modifier(100.0, 100.0)
	assert_eq(sys.excitement, 100.0, "Excitement should clamp at 100")
	assert_eq(sys.stress, 100.0, "Stress should clamp at 100")
	
	# 测试下限
	sys.apply_modifier(-200.0, -200.0)
	assert_eq(sys.excitement, 0.0, "Excitement should clamp at 0")
	assert_eq(sys.stress, 0.0, "Stress should clamp at 0")


## 测试生理系统 - 衰减
func test_physiological_decay() -> void:
	var sys := NPCPhysiologicalSys.new(0.0, 0.0, 10.0, 5.0)  # decay: 10, 5
	sys.apply_modifier(50.0, 30.0)
	
	sys.decay_values()
	
	assert_eq(sys.excitement, 40.0, "Excitement should decay by 10")
	assert_eq(sys.stress, 25.0, "Stress should decay by 5")


## 测试生理系统 - EV修正
func test_physiological_ev_modifier() -> void:
	var sys := NPCPhysiologicalSys.new(50.0, 50.0)  # 中性状态
	var modifier := sys.get_ev_modifier()
	assert_almost_eq(modifier, 1.0, 0.01, "Neutral state should have ~1.0 modifier")
	
	# 高兴奋度
	sys.apply_modifier(30.0, 0.0)  # 80
	modifier = sys.get_ev_modifier()
	assert_gt(modifier, 1.0, "High excitement should increase modifier")


## 测试陷阱系统 - 过度自信触发
func test_trap_overconfidence() -> void:
	var trap := NPCTrapSys.new(NPCTrapSys.TrapType.OVERCONFIDENCE)
	var physio := NPCPhysiologicalSys.new(85.0, 0.0)  # 高兴奋度
	
	var triggered := trap.check_triggers(physio, {"win_streak": 0})
	
	assert_true(triggered, "Should trigger overconfidence trap")
	assert_eq(trap.get_forced_action(), NPCTrapSys.ForcedAction.ALL_IN)


## 测试陷阱系统 - 情绪失控触发
func test_trap_tilt() -> void:
	var trap := NPCTrapSys.new(NPCTrapSys.TrapType.TILT)
	var physio := NPCPhysiologicalSys.new(0.0, 90.0)  # 高压力
	
	var triggered := trap.check_triggers(physio, {})
	
	assert_true(triggered, "Should trigger tilt trap")
	assert_eq(trap.get_forced_action(), NPCTrapSys.ForcedAction.ALL_IN)


## 测试陷阱系统 - 贪婪触发
func test_trap_greed() -> void:
	var trap := NPCTrapSys.new(NPCTrapSys.TrapType.GREED)
	var physio := NPCPhysiologicalSys.new(0.0, 0.0)
	
	var triggered := trap.check_triggers(physio, {"pot": 15000})  # 大底池
	
	assert_true(triggered, "Should trigger greed trap")
	assert_eq(trap.get_forced_action(), NPCTrapSys.ForcedAction.MUST_CALL)


## 测试陷阱系统 - 未触发
func test_trap_no_trigger() -> void:
	var trap := NPCTrapSys.new(NPCTrapSys.TrapType.OVERCONFIDENCE)
	var physio := NPCPhysiologicalSys.new(30.0, 20.0)  # 低兴奋度
	
	var triggered := trap.check_triggers(physio, {"win_streak": 0})
	
	assert_false(triggered, "Should not trigger trap")
	assert_eq(trap.get_forced_action(), NPCTrapSys.ForcedAction.NONE)


## 测试理性系统 - 低EV弃牌
func test_rational_fold_low_ev() -> void:
	var rational := NPCRationalSys.new(0.3, 0.7)
	
	var decision := rational.make_rational_decision(0.2, 1.0, 100, 1000)
	
	assert_eq(decision, NPCRationalSys.RationalDecision.FOLD, "Should fold with low EV")


## 测试理性系统 - 高EV加注
func test_rational_raise_high_ev() -> void:
	var rational := NPCRationalSys.new(0.3, 0.7)
	
	var decision := rational.make_rational_decision(0.8, 1.0, 100, 1000)
	
	assert_eq(decision, NPCRationalSys.RationalDecision.RAISE, "Should raise with high EV")


## 测试理性系统 - 中等EV跟注
func test_rational_call_medium_ev() -> void:
	var rational := NPCRationalSys.new(0.3, 0.7)
	
	var decision := rational.make_rational_decision(0.5, 1.0, 100, 1000)
	
	assert_eq(decision, NPCRationalSys.RationalDecision.CALL, "Should call with medium EV")


## 测试理性系统 - 无需跟注时过牌
func test_rational_check_no_bet() -> void:
	var rational := NPCRationalSys.new(0.3, 0.7)
	
	var decision := rational.make_rational_decision(0.5, 1.0, 0, 1000)  # to_call = 0
	
	assert_eq(decision, NPCRationalSys.RationalDecision.CHECK, "Should check when no bet needed")


## 测试决策整合 - 陷阱覆写理性决策
func test_resolver_trap_overrides_rational() -> void:
	var physio := NPCPhysiologicalSys.new(90.0, 0.0)  # 高兴奋度触发陷阱
	var rational := NPCRationalSys.new(0.3, 0.7)
	var trap := NPCTrapSys.new(NPCTrapSys.TrapType.OVERCONFIDENCE)
	
	var resolver := NPCDecisionResolver.new(physio, rational, trap)
	resolver.current_funds = 5000
	
	# 创建一个很弱的手牌（正常应该弃牌）
	var hand: Array[CardData] = [
		CardData.new(CardData.Suit.SPADE, CardData.Rank.TWO),
		CardData.new(CardData.Suit.HEART, CardData.Rank.THREE)
	]
	var visible: Array[CardData] = []
	var context := {"win_streak": 0}
	
	var decision := resolver.resolve(hand, visible, 1000, 500, context)
	
	assert_true(decision.is_trap_forced, "Should be trap forced")
	assert_eq(decision.action, NPCDecisionResolver.Action.ALL_IN, "Should all-in due to trap")
