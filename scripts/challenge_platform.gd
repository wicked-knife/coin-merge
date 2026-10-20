extends RefCounted
## Optional YouTube host integration. A true return means requested, not displayed.
## The host supplies its SDK; standalone desktop/web builds continue without ads.

# tests/challenge_platform_test.cjs executes this exact JavaScript with mock SDKs.
const INTERSTITIAL_SCRIPT := """
(function (placement) {
	if (typeof window === "undefined") return false;
	const sdk = window.ytgame;
	if (!sdk || !sdk.IN_PLAYABLES_ENV || !sdk.ads ||
		typeof sdk.ads.requestInterstitialAd !== "function") return false;
	const state = window.__coinMergeChallengePlatform ||
		(window.__coinMergeChallengePlatform = {});
	if (state.interstitial) return true;
	const pending = (async function () {
		try {
			await sdk.ads.requestInterstitialAd();
		} catch (error) {
			const message = "[InterstitialAd] " + placement + " failed: " +
				(error && error.message ? error.message : "unknown");
			try {
				if (sdk.health && typeof sdk.health.logError === "function")
					sdk.health.logError(message);
			} catch (_) {}
			try { console.warn("[YouTube]", message); } catch (_) {}
		}
	})();
	state.interstitial = pending;
	pending.then(function () {
		if (state.interstitial === pending) state.interstitial = null;
	});
	return true;
})(%s)
"""


static func request_interstitial(placement: String) -> bool:
	if not OS.has_feature("web"):
		return false
	return JavaScriptBridge.eval(INTERSTITIAL_SCRIPT % JSON.stringify(placement)) == true
