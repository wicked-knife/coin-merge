extends RefCounted
## One ordered registry for persistence, host mapping and the language picker.

const DEFAULT := "en_US"
const LANGUAGES := [
	{"locale": "en_US", "name": "English"},
	{"locale": "ru", "name": "Русский"},
	{"locale": "ko_KR", "name": "한국어"},
	{"locale": "ja", "name": "日本語"},
	{"locale": "id", "name": "Indonesia"},
	{"locale": "fr", "name": "Français"},
	{"locale": "es", "name": "Español"},
	{"locale": "pt", "name": "Português"},
	{"locale": "ar", "name": "العربية"},
	{"locale": "zh_CN", "name": "简体中文"},
	{"locale": "zh_TW", "name": "繁體中文"},
]


static func normalize(value: String) -> String:
	var tag := value.strip_edges().replace("_", "-").to_lower()
	var base := tag.get_slice("-", 0)
	if base == "zh":
		return "zh_TW" if "tw" in tag.split("-") or "hant" in tag.split("-") else "zh_CN"
	if base == "en":
		return "en_US"
	if base == "ko":
		return "ko_KR"
	if base in ["in", "ms"]:
		return "id"
	for item in LANGUAGES:
		if item.locale == base:
			return base
	return ""


static func available(value: String) -> String:
	var locale := normalize(value)
	return locale if locale in TranslationServer.get_loaded_locales() else DEFAULT


static func native_name(value: String) -> String:
	var locale := normalize(value)
	for item in LANGUAGES:
		if item.locale == locale:
			return item.name
	return "English"


static func is_chinese(value: String) -> bool:
	return normalize(value).begins_with("zh_")


static func text_direction() -> int:
	return Control.TEXT_DIRECTION_RTL if TranslationServer.get_locale() == "ar" else Control.TEXT_DIRECTION_LTR
