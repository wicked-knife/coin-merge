extends RefCounted
## The host supplies ytgame. No SDK is injected and standalone runs use English.

const LANGUAGE_SCRIPT := """
(function () {
	if (typeof window === "undefined") return false;
	const sdk = window.ytgame;
	if (!sdk || !sdk.IN_PLAYABLES_ENV || !sdk.system ||
		typeof sdk.system.getLanguage !== "function") return false;
	const state = { done: false, language: "" };
	window.__coinMergeLanguage = state;
	(async function () {
		try {
			const language = await sdk.system.getLanguage();
			if (typeof language === "string") state.language = language;
		} catch (_) {}
		state.done = true;
	})();
	return true;
})()
"""

const RESULT_SCRIPT := """
JSON.stringify(window.__coinMergeLanguage || { done: true, language: "" })
"""


static func get_language(tree: SceneTree, timeout: float = 2.0) -> String:
	if not OS.has_feature("web"):
		return ""
	return await wait_for_language(tree,
		func(): return bool(JavaScriptBridge.eval(LANGUAGE_SCRIPT)),
		func(): return JavaScriptBridge.eval(RESULT_SCRIPT), timeout)


static func wait_for_language(tree: SceneTree, begin: Callable, poll: Callable, timeout: float = 2.0) -> String:
	if begin.call() != true:
		return ""
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		var result = JSON.parse_string(str(poll.call()))
		if result is Dictionary and result.get("done", false):
			return str(result.get("language", ""))
		await tree.create_timer(0.05).timeout
	return ""
