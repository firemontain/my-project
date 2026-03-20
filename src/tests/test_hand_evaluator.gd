## test_hand_evaluator.gd
## HandEvaluator 单元测试
extends GutTest


var evaluator: HandEvaluator


func before_each() -> void:
	evaluator = HandEvaluator.new()


## 辅助方法：创建指定花色和点数的牌
func _make_card(suit: CardData.Suit, rank: CardData.Rank) -> CardData:
	return CardData.new(suit, rank)


## 辅助方法：创建手牌
func _make_hand(cards: Array) -> Array[CardData]:
	var hand: Array[CardData] = []
	for c in cards:
		hand.append(_make_card(c[0], c[1]))
	return hand


## 测试皇家同花顺
func test_royal_flush() -> void:
	var hand := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.ACE],
		[CardData.Suit.SPADE, CardData.Rank.KING],
		[CardData.Suit.SPADE, CardData.Rank.QUEEN],
		[CardData.Suit.SPADE, CardData.Rank.JACK],
		[CardData.Suit.SPADE, CardData.Rank.TEN]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.ROYAL_FLUSH, "Should be Royal Flush")
	assert_eq(result.description, "皇家同花顺")


## 测试同花顺
func test_straight_flush() -> void:
	var hand := _make_hand([
		[CardData.Suit.HEART, CardData.Rank.NINE],
		[CardData.Suit.HEART, CardData.Rank.EIGHT],
		[CardData.Suit.HEART, CardData.Rank.SEVEN],
		[CardData.Suit.HEART, CardData.Rank.SIX],
		[CardData.Suit.HEART, CardData.Rank.FIVE]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.STRAIGHT_FLUSH, "Should be Straight Flush")
	assert_eq(result.primary_value, 9, "High card should be 9")


## 测试四条
func test_four_of_kind() -> void:
	var hand := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.KING],
		[CardData.Suit.HEART, CardData.Rank.KING],
		[CardData.Suit.DIAMOND, CardData.Rank.KING],
		[CardData.Suit.CLUB, CardData.Rank.KING],
		[CardData.Suit.SPADE, CardData.Rank.TWO]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.FOUR_OF_KIND, "Should be Four of a Kind")
	assert_eq(result.primary_value, CardData.Rank.KING, "Should be Kings")


## 测试葫芦
func test_full_house() -> void:
	var hand := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.ACE],
		[CardData.Suit.HEART, CardData.Rank.ACE],
		[CardData.Suit.DIAMOND, CardData.Rank.ACE],
		[CardData.Suit.CLUB, CardData.Rank.KING],
		[CardData.Suit.SPADE, CardData.Rank.KING]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.FULL_HOUSE, "Should be Full House")
	assert_eq(result.primary_value, CardData.Rank.ACE, "Three of a kind should be Aces")
	assert_eq(result.secondary_value, CardData.Rank.KING, "Pair should be Kings")


## 测试同花
func test_flush() -> void:
	var hand := _make_hand([
		[CardData.Suit.DIAMOND, CardData.Rank.ACE],
		[CardData.Suit.DIAMOND, CardData.Rank.TEN],
		[CardData.Suit.DIAMOND, CardData.Rank.SEVEN],
		[CardData.Suit.DIAMOND, CardData.Rank.FOUR],
		[CardData.Suit.DIAMOND, CardData.Rank.TWO]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.FLUSH, "Should be Flush")


## 测试顺子
func test_straight() -> void:
	var hand := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.NINE],
		[CardData.Suit.HEART, CardData.Rank.EIGHT],
		[CardData.Suit.DIAMOND, CardData.Rank.SEVEN],
		[CardData.Suit.CLUB, CardData.Rank.SIX],
		[CardData.Suit.SPADE, CardData.Rank.FIVE]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.STRAIGHT, "Should be Straight")
	assert_eq(result.primary_value, 9, "High card should be 9")


## 测试 A-2-3-4-5 小顺子（轮子）
func test_wheel_straight() -> void:
	var hand := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.ACE],
		[CardData.Suit.HEART, CardData.Rank.TWO],
		[CardData.Suit.DIAMOND, CardData.Rank.THREE],
		[CardData.Suit.CLUB, CardData.Rank.FOUR],
		[CardData.Suit.SPADE, CardData.Rank.FIVE]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.STRAIGHT, "Should be Straight (wheel)")
	assert_eq(result.primary_value, 5, "High card should be 5 for wheel")


## 测试三条
func test_three_of_kind() -> void:
	var hand := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.QUEEN],
		[CardData.Suit.HEART, CardData.Rank.QUEEN],
		[CardData.Suit.DIAMOND, CardData.Rank.QUEEN],
		[CardData.Suit.CLUB, CardData.Rank.SEVEN],
		[CardData.Suit.SPADE, CardData.Rank.TWO]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.THREE_OF_KIND, "Should be Three of a Kind")
	assert_eq(result.primary_value, CardData.Rank.QUEEN, "Should be Queens")


## 测试两对
func test_two_pair() -> void:
	var hand := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.JACK],
		[CardData.Suit.HEART, CardData.Rank.JACK],
		[CardData.Suit.DIAMOND, CardData.Rank.FOUR],
		[CardData.Suit.CLUB, CardData.Rank.FOUR],
		[CardData.Suit.SPADE, CardData.Rank.TWO]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.TWO_PAIR, "Should be Two Pair")
	assert_eq(result.primary_value, CardData.Rank.JACK, "High pair should be Jacks")
	assert_eq(result.secondary_value, CardData.Rank.FOUR, "Low pair should be Fours")


## 测试一对
func test_one_pair() -> void:
	var hand := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.TEN],
		[CardData.Suit.HEART, CardData.Rank.TEN],
		[CardData.Suit.DIAMOND, CardData.Rank.EIGHT],
		[CardData.Suit.CLUB, CardData.Rank.FIVE],
		[CardData.Suit.SPADE, CardData.Rank.TWO]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.ONE_PAIR, "Should be One Pair")
	assert_eq(result.primary_value, CardData.Rank.TEN, "Pair should be Tens")


## 测试高牌
func test_high_card() -> void:
	var hand := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.ACE],
		[CardData.Suit.HEART, CardData.Rank.KING],
		[CardData.Suit.DIAMOND, CardData.Rank.SEVEN],
		[CardData.Suit.CLUB, CardData.Rank.FOUR],
		[CardData.Suit.SPADE, CardData.Rank.TWO]
	])
	var result := evaluator.evaluate(hand)
	assert_eq(result.rank, HandEvaluator.HandRank.HIGH_CARD, "Should be High Card")
	assert_eq(result.kickers[0], CardData.Rank.ACE, "Highest kicker should be Ace")


## 测试手牌比较 - 葫芦 > 同花
func test_compare_full_house_beats_flush() -> void:
	var full_house := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.SEVEN],
		[CardData.Suit.HEART, CardData.Rank.SEVEN],
		[CardData.Suit.DIAMOND, CardData.Rank.SEVEN],
		[CardData.Suit.CLUB, CardData.Rank.TWO],
		[CardData.Suit.SPADE, CardData.Rank.TWO]
	])
	
	var flush := _make_hand([
		[CardData.Suit.HEART, CardData.Rank.ACE],
		[CardData.Suit.HEART, CardData.Rank.KING],
		[CardData.Suit.HEART, CardData.Rank.TEN],
		[CardData.Suit.HEART, CardData.Rank.FIVE],
		[CardData.Suit.HEART, CardData.Rank.TWO]
	])
	
	var result := evaluator.compare(full_house, flush)
	assert_gt(result, 0, "Full house should beat flush")


## 测试同牌型比较 - 对A > 对K
func test_compare_same_hand_type() -> void:
	var pair_aces := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.ACE],
		[CardData.Suit.HEART, CardData.Rank.ACE],
		[CardData.Suit.DIAMOND, CardData.Rank.SEVEN],
		[CardData.Suit.CLUB, CardData.Rank.FOUR],
		[CardData.Suit.SPADE, CardData.Rank.TWO]
	])
	
	var pair_kings := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.KING],
		[CardData.Suit.HEART, CardData.Rank.KING],
		[CardData.Suit.DIAMOND, CardData.Rank.QUEEN],
		[CardData.Suit.CLUB, CardData.Rank.JACK],
		[CardData.Suit.SPADE, CardData.Rank.TEN]
	])
	
	var result := evaluator.compare(pair_aces, pair_kings)
	assert_gt(result, 0, "Pair of Aces should beat Pair of Kings")


## 测试踢脚牌比较
func test_compare_kickers() -> void:
	var pair_with_ace_kicker := _make_hand([
		[CardData.Suit.SPADE, CardData.Rank.TEN],
		[CardData.Suit.HEART, CardData.Rank.TEN],
		[CardData.Suit.DIAMOND, CardData.Rank.ACE],
		[CardData.Suit.CLUB, CardData.Rank.FOUR],
		[CardData.Suit.SPADE, CardData.Rank.TWO]
	])
	
	var pair_with_king_kicker := _make_hand([
		[CardData.Suit.DIAMOND, CardData.Rank.TEN],
		[CardData.Suit.CLUB, CardData.Rank.TEN],
		[CardData.Suit.HEART, CardData.Rank.KING],
		[CardData.Suit.SPADE, CardData.Rank.FOUR],
		[CardData.Suit.DIAMOND, CardData.Rank.TWO]
	])
	
	var result := evaluator.compare(pair_with_ace_kicker, pair_with_king_kicker)
	assert_gt(result, 0, "Pair with Ace kicker should beat pair with King kicker")
