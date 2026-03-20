## HandEvaluator.gd
## 手牌评估器 - 判定梭哈牌型和比较大小
class_name HandEvaluator
extends RefCounted

## 牌型枚举（从小到大）
enum HandRank {
	HIGH_CARD = 0,          ## 高牌
	ONE_PAIR = 1,           ## 一对
	TWO_PAIR = 2,           ## 两对
	THREE_OF_KIND = 3,      ## 三条
	STRAIGHT = 4,           ## 顺子
	FLUSH = 5,              ## 同花
	FULL_HOUSE = 6,         ## 葫芦
	FOUR_OF_KIND = 7,       ## 四条
	STRAIGHT_FLUSH = 8,     ## 同花顺
	ROYAL_FLUSH = 9         ## 皇家同花顺
}

## 评估结果类
class HandResult:
	var rank: HandRank              ## 牌型
	var primary_value: int = 0      ## 主要比较值（如对子的点数）
	var secondary_value: int = 0    ## 次要比较值（如两对的小对点数）
	var kickers: Array[int] = []    ## 踢脚牌点数（用于同牌型比较）
	var description: String = ""    ## 牌型描述
	
	func _init() -> void:
		kickers = []


## 评估五张手牌
func evaluate(hand: Array[CardData]) -> HandResult:
	if hand.size() != 5:
		push_error("Hand must contain exactly 5 cards")
		return null
	
	var result := HandResult.new()
	
	# 排序手牌（按点数降序）
	var sorted_hand := hand.duplicate()
	sorted_hand.sort_custom(_compare_by_rank_desc)
	
	# 检查各牌型（从高到低）
	if _is_royal_flush(sorted_hand):
		result.rank = HandRank.ROYAL_FLUSH
		result.description = "皇家同花顺"
	elif _is_straight_flush(sorted_hand):
		result.rank = HandRank.STRAIGHT_FLUSH
		result.primary_value = _get_straight_high(sorted_hand)
		result.description = "同花顺"
	elif _is_four_of_kind(sorted_hand):
		result.rank = HandRank.FOUR_OF_KIND
		result.primary_value = _get_four_of_kind_value(sorted_hand)
		result.kickers = _get_kickers_excluding(sorted_hand, [result.primary_value], 1)
		result.description = "四条"
	elif _is_full_house(sorted_hand):
		result.rank = HandRank.FULL_HOUSE
		var values := _get_full_house_values(sorted_hand)
		result.primary_value = values[0]
		result.secondary_value = values[1]
		result.description = "葫芦"
	elif _is_flush(sorted_hand):
		result.rank = HandRank.FLUSH
		result.kickers = _get_all_ranks(sorted_hand)
		result.description = "同花"
	elif _is_straight(sorted_hand):
		result.rank = HandRank.STRAIGHT
		result.primary_value = _get_straight_high(sorted_hand)
		result.description = "顺子"
	elif _is_three_of_kind(sorted_hand):
		result.rank = HandRank.THREE_OF_KIND
		result.primary_value = _get_three_of_kind_value(sorted_hand)
		result.kickers = _get_kickers_excluding(sorted_hand, [result.primary_value], 2)
		result.description = "三条"
	elif _is_two_pair(sorted_hand):
		result.rank = HandRank.TWO_PAIR
		var pairs := _get_pairs(sorted_hand)
		result.primary_value = pairs[0]
		result.secondary_value = pairs[1]
		result.kickers = _get_kickers_excluding(sorted_hand, pairs, 1)
		result.description = "两对"
	elif _is_one_pair(sorted_hand):
		result.rank = HandRank.ONE_PAIR
		result.primary_value = _get_pair_value(sorted_hand)
		result.kickers = _get_kickers_excluding(sorted_hand, [result.primary_value], 3)
		result.description = "一对"
	else:
		result.rank = HandRank.HIGH_CARD
		result.kickers = _get_all_ranks(sorted_hand)
		result.description = "高牌"
	
	return result


## 比较两手牌
## @return: 正数表示hand1赢，负数表示hand2赢，0表示平局
func compare(hand1: Array[CardData], hand2: Array[CardData]) -> int:
	var result1 := evaluate(hand1)
	var result2 := evaluate(hand2)
	return compare_results(result1, result2)


## 比较两个评估结果
func compare_results(result1: HandResult, result2: HandResult) -> int:
	# 先比较牌型
	if result1.rank != result2.rank:
		return result1.rank - result2.rank
	
	# 同牌型比较主要值
	if result1.primary_value != result2.primary_value:
		return result1.primary_value - result2.primary_value
	
	# 比较次要值
	if result1.secondary_value != result2.secondary_value:
		return result1.secondary_value - result2.secondary_value
	
	# 比较踢脚牌
	for i in range(mini(result1.kickers.size(), result2.kickers.size())):
		if result1.kickers[i] != result2.kickers[i]:
			return result1.kickers[i] - result2.kickers[i]
	
	return 0  # 完全相同


# ── 私有辅助方法 ──

func _compare_by_rank_desc(a: CardData, b: CardData) -> bool:
	return a.rank > b.rank  # 降序排列


func _is_royal_flush(hand: Array[CardData]) -> bool:
	if not _is_flush(hand):
		return false
	var ranks := _get_all_ranks(hand)
	ranks.sort()
	return ranks == [10, 11, 12, 13, 14]


func _is_straight_flush(hand: Array[CardData]) -> bool:
	return _is_flush(hand) and _is_straight(hand)


func _is_four_of_kind(hand: Array[CardData]) -> bool:
	var counts := _get_rank_counts(hand)
	return 4 in counts.values()


func _is_full_house(hand: Array[CardData]) -> bool:
	var counts := _get_rank_counts(hand)
	var values := counts.values()
	return 3 in values and 2 in values


func _is_flush(hand: Array[CardData]) -> bool:
	var first_suit := hand[0].suit
	for card in hand:
		if card.suit != first_suit:
			return false
	return true


func _is_straight(hand: Array[CardData]) -> bool:
	var ranks: Array[int] = []
	for card in hand:
		ranks.append(card.rank)
	ranks.sort()
	
	# 检查普通顺子
	var is_normal := true
	for i in range(1, ranks.size()):
		if ranks[i] - ranks[i-1] != 1:
			is_normal = false
			break
	
	if is_normal:
		return true
	
	# 检查 A-2-3-4-5 小顺子（轮子）
	if ranks == [2, 3, 4, 5, 14]:
		return true
	
	return false


func _is_three_of_kind(hand: Array[CardData]) -> bool:
	var counts := _get_rank_counts(hand)
	var values := counts.values()
	return 3 in values and not (2 in values)


func _is_two_pair(hand: Array[CardData]) -> bool:
	var counts := _get_rank_counts(hand)
	var pair_count := 0
	for count in counts.values():
		if count == 2:
			pair_count += 1
	return pair_count == 2


func _is_one_pair(hand: Array[CardData]) -> bool:
	var counts := _get_rank_counts(hand)
	var pair_count := 0
	for count in counts.values():
		if count == 2:
			pair_count += 1
	return pair_count == 1


func _get_rank_counts(hand: Array[CardData]) -> Dictionary:
	var counts: Dictionary = {}
	for card in hand:
		var r: int = card.rank
		if not counts.has(r):
			counts[r] = 0
		counts[r] += 1
	return counts


func _get_straight_high(hand: Array[CardData]) -> int:
	var ranks: Array[int] = []
	for card in hand:
		ranks.append(card.rank)
	ranks.sort()
	
	# A-2-3-4-5 小顺子的最高牌是5
	if ranks == [2, 3, 4, 5, 14]:
		return 5
	
	return ranks[4]


func _get_four_of_kind_value(hand: Array[CardData]) -> int:
	var counts := _get_rank_counts(hand)
	for r in counts:
		if counts[r] == 4:
			return r
	return 0


func _get_full_house_values(hand: Array[CardData]) -> Array[int]:
	var counts := _get_rank_counts(hand)
	var three_val := 0
	var two_val := 0
	for r in counts:
		if counts[r] == 3:
			three_val = r
		elif counts[r] == 2:
			two_val = r
	return [three_val, two_val]


func _get_three_of_kind_value(hand: Array[CardData]) -> int:
	var counts := _get_rank_counts(hand)
	for r in counts:
		if counts[r] == 3:
			return r
	return 0


func _get_pairs(hand: Array[CardData]) -> Array[int]:
	var counts := _get_rank_counts(hand)
	var pairs: Array[int] = []
	for r in counts:
		if counts[r] == 2:
			pairs.append(r)
	pairs.sort()
	pairs.reverse()  # 降序
	return pairs


func _get_pair_value(hand: Array[CardData]) -> int:
	var counts := _get_rank_counts(hand)
	for r in counts:
		if counts[r] == 2:
			return r
	return 0


func _get_all_ranks(hand: Array[CardData]) -> Array[int]:
	var ranks: Array[int] = []
	for card in hand:
		ranks.append(card.rank)
	ranks.sort()
	ranks.reverse()  # 降序
	return ranks


func _get_kickers_excluding(hand: Array[CardData], exclude: Array[int], count: int) -> Array[int]:
	var result: Array[int] = []
	for card in hand:
		if not (card.rank in exclude):
			result.append(card.rank)
	result.sort()
	result.reverse()  # 降序
	return result.slice(0, count)
