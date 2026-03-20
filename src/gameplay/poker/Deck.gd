## Deck.gd
## 牌堆管理类 - 负责洗牌、发牌
class_name Deck
extends RefCounted

## 剩余牌堆
var _cards: Array[CardData] = []

## 已发出的牌
var _dealt_cards: Array[CardData] = []


## 初始化 - 构建并洗牌
func _init() -> void:
	_build_standard_deck()
	shuffle()


## 构建标准52张牌
func _build_standard_deck() -> void:
	_cards.clear()
	_dealt_cards.clear()
	for suit_val in CardData.Suit.values():
		for rank_val in range(CardData.Rank.TWO, CardData.Rank.ACE + 1):
			var card := CardData.new(suit_val as CardData.Suit, rank_val as CardData.Rank)
			_cards.append(card)


## 洗牌
func shuffle() -> void:
	_cards.shuffle()


## 发一张牌
func deal_card() -> CardData:
	if _cards.is_empty():
		return null
	var card := _cards.pop_front()
	_dealt_cards.append(card)
	return card


## 发多张牌
func deal_cards(count: int) -> Array[CardData]:
	var result: Array[CardData] = []
	for i in range(count):
		var card := deal_card()
		if card:
			result.append(card)
	return result


## 获取剩余牌数
func get_remaining_count() -> int:
	return _cards.size()


## 重置牌堆（重新构建并洗牌）
func reset() -> void:
	_build_standard_deck()
	shuffle()


## 偷看牌堆顶部若干张牌（不取出）
func peek_top_cards(count: int) -> Array[CardData]:
	var result: Array[CardData] = []
	for i in range(mini(count, _cards.size())):
		result.append(_cards[i])
	return result
