## NPCRationalSys.gd
## NPC理性系统 - 基于期望值(EV)进行决策
class_name NPCRationalSys
extends RefCounted

## 决策枚举
enum RationalDecision {
	FOLD,       ## 弃牌
	CHECK,      ## 过牌
	CALL,       ## 跟注
	RAISE,      ## 加注
	ALL_IN      ## 全押
}

## EV弃牌阈值（低于此值倾向弃牌）
var ev_fold_threshold: float = 0.3

## EV加注阈值（高于此值倾向加注）
var ev_raise_threshold: float = 0.7

## 手牌评估器引用
var _evaluator: HandEvaluator


## 初始化
func _init(p_fold_threshold: float = 0.3, p_raise_threshold: float = 0.7) -> void:
	ev_fold_threshold = p_fold_threshold
	ev_raise_threshold = p_raise_threshold
	_evaluator = HandEvaluator.new()


## 计算当前手牌的期望值
## @param hand: 当前手牌（可能不足5张）
## @param visible_cards: 所有可见的牌
## @param pot: 当前底池
## @param to_call: 需要跟注的金额
## @return: 期望值（0.0 - 1.0）
func evaluate_ev(hand: Array[CardData], visible_cards: Array[CardData], 
				 pot: int, to_call: int) -> float:
	# 简化的EV计算
	# 实际游戏中需要更复杂的概率计算
	
	# 计算手牌强度（基于当前可见牌）
	var hand_strength := _calculate_hand_strength(hand)
	
	# 计算赔率
	var pot_odds := float(to_call) / float(pot + to_call) if pot + to_call > 0 else 0.0
	
	# EV = 手牌强度 - 需要投入的比例
	var ev := hand_strength - pot_odds * 0.5
	
	return clampf(ev, 0.0, 1.0)


## 基于EV做出理性决策
func make_rational_decision(ev: float, ev_modifier: float, to_call: int, current_funds: int) -> RationalDecision:
	var adjusted_ev := ev * ev_modifier
	
	# 无需跟注时
	if to_call == 0:
		if adjusted_ev >= ev_raise_threshold:
			return RationalDecision.RAISE
		return RationalDecision.CHECK
	
	# 需要跟注时
	if adjusted_ev < ev_fold_threshold:
		return RationalDecision.FOLD
	elif adjusted_ev >= ev_raise_threshold:
		if current_funds > to_call * 3:
			return RationalDecision.RAISE
		return RationalDecision.CALL
	else:
		return RationalDecision.CALL


## 计算加注金额（理性决策）
func calculate_raise_amount(ev: float, pot: int, to_call: int, current_funds: int) -> int:
	# 基于EV决定加注倍率
	var raise_ratio := 0.5 + ev * 0.5  # 0.5x - 1.0x底池
	var raise_amount := int(pot * raise_ratio)
	
	# 至少是跟注金额的2倍
	raise_amount = maxi(raise_amount, to_call * 2)
	
	# 不超过当前资金
	raise_amount = mini(raise_amount, current_funds)
	
	return raise_amount


## 计算手牌强度（简化版）
func _calculate_hand_strength(hand: Array[CardData]) -> float:
	if hand.size() < 2:
		return 0.3
	
	var strength := 0.0
	
	# 检查是否有对子
	var ranks: Dictionary = {}
	for card in hand:
		var r: int = card.rank
		if not ranks.has(r):
			ranks[r] = 0
		ranks[r] += 1
	
	var max_count := 1
	var max_rank := 0
	for r in ranks:
		if ranks[r] > max_count:
			max_count = ranks[r]
			max_rank = r
		elif ranks[r] == max_count and r > max_rank:
			max_rank = r
	
	# 基础强度来自最高牌
	var highest_rank := 0
	for card in hand:
		highest_rank = maxi(highest_rank, card.rank)
	
	strength = float(highest_rank - 2) / 12.0 * 0.3  # 2-A映射到0-0.3
	
	# 加成来自组合
	match max_count:
		4:
			strength += 0.7  # 四条
		3:
			strength += 0.5  # 三条
		2:
			# 检查是否两对
			var pair_count := 0
			for r in ranks:
				if ranks[r] == 2:
					pair_count += 1
			if pair_count == 2:
				strength += 0.35  # 两对
			else:
				strength += 0.25  # 一对
	
	# 检查同花潜力
	var suits: Dictionary = {}
	for card in hand:
		var s: int = card.suit
		if not suits.has(s):
			suits[s] = 0
		suits[s] += 1
	
	var max_suit_count := 1
	for s in suits:
		max_suit_count = maxi(max_suit_count, suits[s])
	
	if max_suit_count >= 4:
		strength += 0.15  # 同花潜力
	elif max_suit_count == 3:
		strength += 0.05
	
	return clampf(strength, 0.0, 1.0)
