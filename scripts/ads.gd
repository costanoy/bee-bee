extends Node

# Ads: one full-screen interstitial between runs, every few runs. No
# banners, nothing during play, no purchases.
#
# Uses the AdMob plugin in addons/admob (Android only; everywhere else, and
# in a build exported without the plugin, every call here does nothing).
#
# BEFORE PUBLISHING: the ids below are Google's public TEST ids, which only
# ever show test ads and pay nothing. Replace both with the real ones from
# the AdMob account:
#   - the ad unit id: INTERSTITIAL_ID here;
#   - the app id: Project Settings > admob/general/android/app_id.
# Never tap real ads on your own device; keep the test ids while developing.
const INTERSTITIAL_ID := "ca-app-pub-3940256099942544/1033173712"

# An ad is offered on "Play Again" once this many runs have ended since the
# last one, and never sooner than MIN_SECONDS_BETWEEN_ADS after it.
const RUNS_BETWEEN_ADS := 3
const MIN_SECONDS_BETWEEN_ADS := 90.0
# Ads carry a content rating; PG keeps out anything a cartoon bee game
# shouldn't sit next to.
const MAX_CONTENT_RATING := "PG"
const RETRY_SECONDS := 45.0

# The ad covers the screen and plays its own sound.
signal ad_opened
# Closed, or it failed to open — either way the game carries on.
signal ad_closed

var _available := false
var _initialized := false
var _ad: InterstitialAd
var _loader: InterstitialAdLoader
var _loading := false
var _runs_since_ad := 0
var _last_ad_msec := -1000000


func start() -> void:
	_available = OS.get_name() == "Android" and Engine.has_singleton("PoingGodotAdMob")
	if not _available:
		return
	_request_consent()


# ------------------------------------------------------------------ consent
# Where the law asks for it (EEA, UK, ...), Google's own consent form is
# shown once, before any ad is requested. Everywhere else this goes straight
# through.
func _request_consent() -> void:
	UserMessagingPlatform.consent_information.update(
		ConsentRequestParameters.new(), _on_consent_info_ready, func(_error): _initialize())


func _on_consent_info_ready() -> void:
	var info := UserMessagingPlatform.consent_information
	if info.get_is_consent_form_available() and info.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
		UserMessagingPlatform.load_consent_form(
			func(form: ConsentForm): form.show(func(_error): _initialize()),
			func(_error): _initialize())
	else:
		_initialize()


# True where the player must be able to reopen the privacy choices (the
# pause menu shows a button for it then).
func privacy_options_required() -> bool:
	if not _available:
		return false
	return (UserMessagingPlatform.consent_information.get_privacy_options_requirement_status()
		== ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED)


func show_privacy_options() -> void:
	if _available:
		UserMessagingPlatform.show_privacy_options_form()


# ------------------------------------------------------------------ loading
func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	var config := RequestConfiguration.new()
	config.max_ad_content_rating = MAX_CONTENT_RATING
	MobileAds.set_request_configuration(config)
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status): _load()
	MobileAds.initialize(listener)


func _load() -> void:
	if _loading or _ad != null:
		return
	_loading = true
	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = _on_loaded
	callback.on_ad_failed_to_load = func(_error):
		_loading = false
		# no connection, or nothing to show right now: try again later
		get_tree().create_timer(RETRY_SECONDS).timeout.connect(_load)
	_loader = InterstitialAdLoader.new()
	_loader.load(INTERSTITIAL_ID, AdRequest.new(), callback)


func _on_loaded(ad: InterstitialAd) -> void:
	_loading = false
	_ad = ad
	var events := FullScreenContentCallback.new()
	events.on_ad_showed_full_screen_content = func(): ad_opened.emit()
	events.on_ad_dismissed_full_screen_content = _finish
	events.on_ad_failed_to_show_full_screen_content = func(_error): _finish()
	_ad.full_screen_content_callback = events


func _finish() -> void:
	if _ad:
		_ad.destroy()
		_ad = null
	_last_ad_msec = Time.get_ticks_msec()
	ad_closed.emit()
	_load()


# ------------------------------------------------------------------ showing
func run_finished() -> void:
	_runs_since_ad += 1


# Called when the player asks for another run. Shows an ad if one is due and
# ready, and returns true: the caller then waits for ad_closed before
# starting the run. Returns false when the run should just start.
func show_between_runs() -> bool:
	if _ad == null or _runs_since_ad < RUNS_BETWEEN_ADS:
		return false
	if (Time.get_ticks_msec() - _last_ad_msec) / 1000.0 < MIN_SECONDS_BETWEEN_ADS:
		return false
	_runs_since_ad = 0
	_ad.show()
	return true
