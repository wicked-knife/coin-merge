extends RefCounted
## Shared ceramic art, licensed type and colors. Sounds keep their own root.
const ROOT := "res://assets/reskin/ceramic/"
const SPRITES := ROOT + "sprites/"
const UI := SPRITES + "ui/"
const FONT_PATH := ROOT + "fonts/CoinMergeUI.tres"
const FONT = preload(FONT_PATH)
const INK := Color("394b4d")
const CREAM := Color("f5f0e5")
const CHALLENGE_COLORS := [Color.WHITE, Color("e3be68"), Color("d98a78"),
	Color("e8b8ac"), Color("8eb4d1"), Color("88c8c5"), Color("b1a0cf"),
	Color("c0cd86"), Color("e4ad79"), Color("b99882"), Color("8fb798"), Color("889fca")]
const PANEL_MARGIN := 24
const BUTTON_MARGIN := 24
