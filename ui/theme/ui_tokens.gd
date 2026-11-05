class_name UiTokens
extends RefCounted
## Design tokens for every Lane D screen. Owner: Lane D (D-01).
## Values come from ui/UI_RULES.md §2-§3 (ARC Raiders base rule, Duckov accents in menus only).
## Never write a colour literal in a scene or script - read it from here.

# --- colours (§2) ---
const INK := Color("0b0d12")
const SLATE := Color(0.165, 0.180, 0.231, 0.86)
const SLATE_MENU := Color(0.165, 0.180, 0.231, 0.78)  # menu skin: lighter, scene shows through
const SLATE_2 := Color(0.212, 0.227, 0.286, 0.9)
const LINE := Color(0.863, 0.855, 0.824, 0.32)
const LINE_STRONG := Color(0.914, 0.906, 0.878, 0.75)
const TEXT := Color("f1f0ea")
const TEXT_DIM := Color("b9b7af")
const CREAM := Color("efeadf")
const CREAM_2 := Color("ddd7c9")
const TEXT_ON_CREAM := Color("26262b")
const TEXT_ON_CREAM_DIM := Color("6b6a70")
const ACCENT := Color("f6c744")
const ACCENT_TEXT := Color("26262b")
const GREY_BTN := Color("8b8e98")
const INFO := Color("57c2c9")
const DANGER := Color("d9453b")
const WARN := Color("e8a23a")
const GOOD := Color("5fc46b")
const PING := Color("c77dff")  # map ping only (FieldState.ping)
const SHADOW := Color(0, 0, 0, 0.7)
const BACKDROP := Color(0, 0, 0, 0.35)  # menu dim over the blurred scene
# Duckov accents (menu skin only)
const PILL_SOFT := Color("e6f4ff")
const PILL_SOFT_TEXT := Color("1d3d55")
const TAB_GLOW := Color("6cc8ff")

# --- shapes ---
const PANEL_RADIUS := 14
const BAND_RADIUS := 10
const SLOT_RADIUS := 10
const CARD_RADIUS := 4
const HUD_MARGIN := 40
const LINE_WIDTH := 2

# --- rarity: colour + shape (design 05). Index = Enums.Rarity ---
enum Shape { CIRCLE, SQUARE, TRIANGLE, DIAMOND, STAR, PETAL, DROP, BOLT }
const RARITY_COLORS: Array[Color] = [
	Color("a4abb1"), Color("5fc46b"), Color("3fb0e6"), Color("b072e8"), Color("f29a3a"),
]
const RARITY_SHAPES: Array[Shape] = [Shape.CIRCLE, Shape.SQUARE, Shape.TRIANGLE, Shape.DIAMOND, Shape.STAR]
const RARITY_NAMES: Array[String] = ["일반", "고급", "희귀", "영웅", "전설"]

# --- element: colour + shape (design 06). Index = Enums.Element (NONE first) ---
const ELEMENT_COLORS: Array[Color] = [
	Color("a4abb1"), Color("7bd86a"), Color("b9a27a"), Color("5fc2ff"), Color("ffd84a"),
]
const ELEMENT_SHAPES: Array[Shape] = [Shape.CIRCLE, Shape.PETAL, Shape.SQUARE, Shape.DROP, Shape.BOLT]
const ELEMENT_NAMES: Array[String] = ["없음", "초록", "돌", "물", "빛"]

# --- type scale (§3), 1920x1080 at text size "보통" ---
const SIZE_TITLE := 32
const SIZE_SECTION := 22
const SIZE_BODY := 18
const SIZE_SMALL := 15
const SIZE_TAB := 21
const SIZE_HUD_NUMBER := 22
const SIZE_HUD_AMMO := 44
const SIZE_SUBTITLE := 25
## Settings.text_size 0 / 1 / 2
const TEXT_SCALES: Array[float] = [0.875, 1.0, 1.25]
## Settings.subtitle_size 0 / 1 / 2
const SUBTITLE_SCALES: Array[float] = [0.85, 1.0, 1.3]

const FONT_KR := "res://ui/theme/fonts/PretendardVariable.woff2"
const FONT_NUM := "res://ui/theme/fonts/Barlow-SemiBold.ttf"


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


static func rarity_shape(rarity: int) -> Shape:
	return RARITY_SHAPES[clampi(rarity, 0, RARITY_SHAPES.size() - 1)]


static func element_color(element: int) -> Color:
	return ELEMENT_COLORS[clampi(element, 0, ELEMENT_COLORS.size() - 1)]


static func element_shape(element: int) -> Shape:
	return ELEMENT_SHAPES[clampi(element, 0, ELEMENT_SHAPES.size() - 1)]


static func text_scale(text_size: int) -> float:
	return TEXT_SCALES[clampi(text_size, 0, TEXT_SCALES.size() - 1)]


## High-contrast variant (Settings.high_contrast): stronger panels and lines, no dim text.
static func slate(high_contrast: bool) -> Color:
	return Color(SLATE, 0.96) if high_contrast else SLATE


static func slate_menu(high_contrast: bool) -> Color:
	return Color(SLATE_MENU, 0.96) if high_contrast else SLATE_MENU


static func line(high_contrast: bool) -> Color:
	return Color(LINE, 0.6) if high_contrast else LINE


static func text_dim(high_contrast: bool) -> Color:
	return TEXT if high_contrast else TEXT_DIM
