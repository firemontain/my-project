## SimplePokerSession.gd
## 简化的牌局控制器 - 用于demo演示
class_name SimplePokerSession
extends RefCounted

## 信号定义
signal round_started(round_num: int)
signal player_turn()
signal npc_turn(npc_name: String)
signal npc_decision_made(npc_name: String, action: String, amount: int)
signal round_ended(round_num: int)
signal session_ended(winner: String, pot: int)
signal hand_dealt(player_hand: Array[CardData], npc_hand: Array[CardData])

## 牌局阶段
enum Phase {
	NOT_STARTED,
	DEALING,
	PLAYER_ACTION,
	NPC_ACTION,
	SHOWDOWN,
	ENDED
}

## 当前阶段
var current_phase: Phase = Phase.NOT_STARTED

## 当前下注轮（1-4）
var current_round: int = 0

## 底池
var pot: int = 0

## 当前需跟注金额
var to_call: int = 0

## 最低加注金额
var min_raise: int = 100

## 盲注
var big_blind: int = 100

## 牌堆
var deck: Deck

## 手牌评估器
var evaluator: HandEvaluator

## 玩家手牌
var player_hand: Array[CardData] = []

## 玩家资金
var player_funds: int = 0

## 玩家本轮已下注
var player_bet: int = 0

## 玩家是否已弃牌
var player_folded: bool = false

## NPC系统引用
var npc_physio: NPCPhysiologicalSys
var npc_rational: NPCRationalSys
var npc_trap: NPCTrapSys
var npc_resolver: NPCDecisionResolver

## NPC名称
var npc_name: String = "神秘赌客"

## NPC手牌
var npc_hand: Array[CardData] = []

## NPC资金
var npc_funds: int = 0

## NPC本轮已下注
var npc_bet: int = 0

## NPC是否已弃牌
var npc_folded: bool = false

## NPC是否全押
var npc_all_in: bool = false

## NPC胜场数（用于陷阱系统）
var npc_win_streak: int = 0
var npc_loss_streak: int = 0


## 初始化牌局
func _init(p_player_funds: int = 10000, p_npc_funds: int = 10000, 
		   npc_trap_type: NPCTrapSys.TrapType = NPCTrapSys.TrapType.OVERCONFIDENCE) -> void:
	player_funds = p_player_funds
	npc_funds = p_npc_funds
	
	deck = Deck.new()
	evaluator = HandEvaluator.new()
	
	# 初始化NPC系统
	npc_physio = NPCPhysiologicalSys.new(20.0, 10.0)  # 基础兴奋度20，压力10
	npc_rational = NPCRationalSys.new(0.3, 0.65)  # 较低的加注阈值
	npc_trap = NPCTrapSys.new(npc_trap_type)
	npc_resolver = NPCDecisionResolver.new(npc_physio, npc_rational, npc_trap)
	npc_resolver.current_funds = npc_funds


## 开始新牌局
func start_session() -> void:
	current_phase = Phase.DEALING
	current_round = 0
	pot = 0
	to_call = 0
	player_bet = 0
	npc_bet = 0
	player_folded = false
	npc_folded = false
	npc_all_in = false
	player_hand.clear()
	npc_hand.clear()
	
	# 重置牌堆
	deck.reset()
	
	# 重置NPC系统
	npc_physio.reset()
	npc_trap.reset()
	npc_resolver.current_funds = npc_funds
	
	# 发初始牌（1暗 + 1明）
	_deal_initial_cards()
	
	# 发射信号
	hand_dealt.emit(player_hand, npc_hand)
	
	# 开始第一轮
	_start_round()


## 发初始牌
func _deal_initial_cards() -> void:
	# 玩家：1暗 + 1明
	var p_hole := deck.deal_card()
	p_hole.is_face_down = true
	var p_up := deck.deal_card()
	player_hand = [p_hole, p_up]
	
	# NPC：1暗 + 1明
	var n_hole := deck.deal_card()
	n_hole.is_face_down = true
	var n_up := deck.deal_card()
	npc_hand = [n_hole, n_up]


## 开始新轮次
func _start_round() -> void:
	current_round += 1
	to_call = 0
	player_bet = 0
	npc_bet = 0
	
	# 第1轮需要盲注
	if current_round == 1:
		_post_blinds()
	
	# 第2-4轮发新牌
	if current_round > 1:
		_deal_round_cards()
	
	round_started.emit(current_round)
	
	# 更新NPC生理状态
	npc_physio.decay_values()
	
	# 玩家先行动
	current_phase = Phase.PLAYER_ACTION
	player_turn.emit()


## 发盲注
func _post_blinds() -> void:
	# 简化：玩家下小盲，NPC下大盲
	var small_blind := big_blind / 2
	
	# 玩家下小盲
	player_funds -= small_blind
	player_bet = small_blind
	pot += small_blind
	
	# NPC下大盲
	npc_funds -= big_blind
	npc_bet = big_blind
	pot += big_blind
	
	to_call = big_blind - small_blind  # 玩家需补齐差额


## 发本轮牌
func _deal_round_cards() -> void:
	if not player_folded:
		var p_card := deck.deal_card()
		player_hand.append(p_card)
	
	if not npc_folded:
		var n_card := deck.deal_card()
		npc_hand.append(n_card)


## 玩家行动
func player_action(action: String, amount: int = 0) -> bool:
	if current_phase != Phase.PLAYER_ACTION:
		return false
	
	match action:
		"fold":
			player_folded = true
			_end_session_winner("npc")
			return true
		"check":
			if to_call > 0:
				return false  # 有注不能过牌
			_advance_to_npc()
			return true
		"call":
			var call_amount := mini(to_call, player_funds)
			player_funds -= call_amount
			player_bet += call_amount
			pot += call_amount
			to_call = 0
			_advance_to_npc()
			return true
		"raise":
			if amount < to_call + min_raise:
				amount = to_call + min_raise
			amount = mini(amount, player_funds)
			player_funds -= amount
			player_bet += amount
			pot += amount
			to_call = amount - npc_bet  # NPC需要跟的金额
			_advance_to_npc()
			return true
		"all_in":
			var all_in_amount := player_funds
			player_funds = 0
			player_bet += all_in_amount
			pot += all_in_amount
			if all_in_amount > npc_bet:
				to_call = all_in_amount - npc_bet
			_advance_to_npc()
			return true
	
	return false


## 进入NPC行动
func _advance_to_npc() -> void:
	if npc_folded or npc_all_in:
		_check_round_end()
		return
	
	current_phase = Phase.NPC_ACTION
	npc_turn.emit(npc_name)
	
	# NPC做决策
	_npc_make_decision()


## NPC做决策
func _npc_make_decision() -> void:
	# 构建游戏上下文
	var context := {
		"pot": pot,
		"win_streak": npc_win_streak,
		"loss_streak": npc_loss_streak,
		"loss_ratio": 1.0 - float(npc_funds) / 10000.0,  # 假设初始资金10000
		"opponent_aggression": 0.5  # 简化
	}
	
	# 获取可见牌（所有非暗牌）
	var visible_cards: Array[CardData] = []
	for card in player_hand:
		if not card.is_face_down:
			visible_cards.append(card)
	for card in npc_hand:
		if not card.is_face_down:
			visible_cards.append(card)
	
	# 获取NPC决策
	var decision := npc_resolver.resolve(npc_hand, visible_cards, pot, to_call, context)
	
	# 执行决策
	_execute_npc_decision(decision)


## 执行NPC决策
func _execute_npc_decision(decision: NPCDecisionResolver.NPCDecision) -> void:
	var action_str := ""
	
	match decision.action:
		NPCDecisionResolver.Action.FOLD:
			npc_folded = true
			action_str = "弃牌"
			npc_decision_made.emit(npc_name, action_str, 0)
			_end_session_winner("player")
			return
		NPCDecisionResolver.Action.CHECK:
			action_str = "过牌"
			npc_decision_made.emit(npc_name, action_str, 0)
		NPCDecisionResolver.Action.CALL:
			var call_amount := mini(to_call, npc_funds)
			npc_funds -= call_amount
			npc_bet += call_amount
			pot += call_amount
			npc_resolver.current_funds = npc_funds
			action_str = "跟注"
			npc_decision_made.emit(npc_name, action_str, call_amount)
			to_call = 0
		NPCDecisionResolver.Action.RAISE:
			var raise_amount := mini(decision.amount, npc_funds)
			npc_funds -= raise_amount
			npc_bet += raise_amount
			pot += raise_amount
			npc_resolver.current_funds = npc_funds
			to_call = raise_amount - player_bet
			action_str = "加注"
			npc_decision_made.emit(npc_name, action_str, raise_amount)
			# 加注后需要玩家响应
			_player_respond_to_raise()
			return
		NPCDecisionResolver.Action.ALL_IN:
			var all_in_amount := npc_funds
			npc_funds = 0
			npc_bet += all_in_amount
			pot += all_in_amount
			npc_all_in = true
			npc_resolver.current_funds = 0
			if all_in_amount > player_bet:
				to_call = all_in_amount - player_bet
			action_str = "全押"
			npc_decision_made.emit(npc_name, action_str, all_in_amount)
			# 全押后需要玩家响应
			if to_call > 0:
				_player_respond_to_raise()
				return
	
	# 如果有陷阱触发，增加NPC兴奋度
	if decision.is_trap_forced:
		npc_physio.apply_modifier(15.0, 10.0)
	
	_check_round_end()


## 玩家响应加注
func _player_respond_to_raise() -> void:
	current_phase = Phase.PLAYER_ACTION
	player_turn.emit()


## 检查轮次是否结束
func _check_round_end() -> void:
	# 如果只剩一人，结束牌局
	if player_folded:
		_end_session_winner("npc")
		return
	if npc_folded:
		_end_session_winner("player")
		return
	
	# 如果到达第4轮且双方都行动完，进入摊牌
	if current_round >= 4:
		round_ended.emit(current_round)
		_do_showdown()
		return
	
	# 否则进入下一轮
	round_ended.emit(current_round)
	_start_round()


## 执行摊牌
func _do_showdown() -> void:
	current_phase = Phase.SHOWDOWN
	
	# 确保双方都有5张牌
	while player_hand.size() < 5:
		player_hand.append(deck.deal_card())
	while npc_hand.size() < 5:
		npc_hand.append(deck.deal_card())
	
	# 评估手牌
	var player_result := evaluator.evaluate(player_hand)
	var npc_result := evaluator.evaluate(npc_hand)
	
	# 比较胜负
	var compare := evaluator.compare_results(player_result, npc_result)
	
	if compare > 0:
		_end_session_winner("player")
	elif compare < 0:
		_end_session_winner("npc")
	else:
		_end_session_winner("tie")


## 结束牌局
func _end_session_winner(winner: String) -> void:
	current_phase = Phase.ENDED
	
	if winner == "player":
		player_funds += pot
		npc_loss_streak += 1
		npc_win_streak = 0
	elif winner == "npc":
		npc_funds += pot
		npc_win_streak += 1
		npc_loss_streak = 0
		npc_resolver.current_funds = npc_funds
	else:  # tie
		player_funds += pot / 2
		npc_funds += pot / 2
		npc_resolver.current_funds = npc_funds
	
	session_ended.emit(winner, pot)


## 获取玩家手牌描述
func get_player_hand_description() -> String:
	if player_hand.size() < 5:
		var cards_str := ""
		for card in player_hand:
			cards_str += card.get_display_name() + " "
		return cards_str.strip_edges()
	
	var result := evaluator.evaluate(player_hand)
	return result.description


## 获取NPC手牌描述（明牌部分）
func get_npc_visible_hand_description() -> String:
	var cards_str := ""
	for card in npc_hand:
		if card.is_face_down:
			cards_str += "🂠 "
		else:
			cards_str += card.get_display_name() + " "
	return cards_str.strip_edges()


## 获取NPC心理状态
func get_npc_psychological_state() -> String:
	return npc_physio.get_state_description()


## 手动增加NPC压力（模拟玩家能力）
func apply_pressure_to_npc(amount: float) -> void:
	npc_physio.apply_modifier(0, amount)


## 手动增加NPC兴奋度（模拟玩家能力）
func apply_excitement_to_npc(amount: float) -> void:
	npc_physio.apply_modifier(amount, 0)
