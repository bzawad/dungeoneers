extends Node

## Client-only Explorer `priv/static/audio/*.mp3` playback (Phase 7.5). Safe no-ops when files are absent.
##
## Phase 9 / AUD-02 / AUD-05 — `play_audio` parity and drift control (audit **2026-04-19**).
## Re-audit Explorer when sounds change: `rg 'push_event\\(.*\"play_audio\"' dungeon_explorer/lib`
## — then sync EXPLORER_PLAY_AUDIO_SOUND_IDS and combat_sfx_basename_for_sound_id if needed.
##
## Web client map: `dungeon_explorer/assets/js/app.js` — `Hooks.AudioPlayer.soundEffects` keys consumed via
## `handleEvent("play_audio", …)` → `playSound(soundName)`. Background music uses separate LiveView events
## (`play_background_music`, `play_combat_music`, …), not `play_audio`.
## Explorer may log `Sound not found` or skip playback before user gesture; Godot skips SFX when headless or
## _is_display_client is false (no dedicated footstep in web — see play_move_step / wood_click.mp3).
##
## Explorer `sound` → Explorer module(s) → Dungeoneers (dungeon_session.gd wires these ExplorerAudio methods):
## - **banging** — door_system.ex → play_banging()
## - **chest_open** — movement.ex, dungeon_live.ex → play_chest_open()
## - **click** — door_system.ex, dungeon_live.ex → play_click()
## - **coins** — combat_system.ex, treasure_system.ex, dungeon_live.ex → play_coins()
## - **death** — combat_system.ex → play_death_sting()
## - **door_open** — door_system.ex → play_door_open()
## - **fight** — dungeon_live.ex, wandering_monster_system.ex, combat → play_combat_sfx("fight", …)
## - **monster_hit** — trap_system.ex, combat_system.ex → play_combat_sfx("monster_hit", …) → monster_hit.mp3
## - **monster_miss** — combat_system.ex → play_combat_sfx("monster_miss", …)
## - **orch_hit** — dungeon_live.ex, combat_system.ex level-up, quest_item_system.ex → play_quest_completion_fanfare / play_level_up_hit
## - **pickup** — dungeon_live.ex, food_system.ex, healing_potion_system.ex → play_pickup()
## - **player_hit** / **player_miss** — combat_system.ex → play_combat_sfx(...)
## - **stairs** — dungeon_live.ex → play_stairs()

const AUDIO_DIR := "res://assets/explorer/audio/"
const USER_AUDIO_CFG := "user://explorer_audio_settings.cfg"

## Canonical `%{sound: …}` literals from Explorer `push_event("play_audio", …)` plus combat-only dynamic IDs.
## Keep sorted; update after Explorer grep when new cues ship (CI asserts assets + combat mapping).
const EXPLORER_PLAY_AUDIO_SOUND_IDS: Array[String] = [
	"banging",
	"chest_open",
	"click",
	"coins",
	"death",
	"door_open",
	"fight",
	"monster_hit",
	"monster_miss",
	"orch_hit",
	"pickup",
	"player_hit",
	"player_miss",
	"stairs",
]

var _sfx_bus := "Master"
var _music_bus := "Master"
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_i: int = 0
var _music_wander: AudioStreamPlayer
var _music_combat: AudioStreamPlayer
var _music_death: AudioStreamPlayer
var _music_state: String = "none"
## Active wanderer track index 1–5 while wander music is the intended background (AUD-03).
var _current_wander_idx: int = 0
## Snapshot taken when entering combat (Explorer Howler `seek` before fight track).
var _resume_wander_idx: int = 0
var _resume_wander_seconds: float = 0.0


## Headless-safe clamp for resume seek (AUD-03); used by CI in `check_parse.gd`.
static func clamp_wander_resume_seconds(stream: AudioStream, pos_sec: float) -> float:
	var pos := maxf(pos_sec, 0.0)
	if stream == null:
		return pos
	var ln := stream.get_length()
	if ln <= 0.0:
		return pos
	var cap := maxf(ln - 0.05, 0.0)
	return minf(pos, cap)


func _ready() -> void:
	var b_sfx := AudioServer.get_bus_index("SFX")
	if b_sfx >= 0:
		_sfx_bus = "SFX"
	var b_mu := AudioServer.get_bus_index("Music")
	if b_mu >= 0:
		_music_bus = "Music"
	_music_wander = _make_stream_player("ExplorerMusicWander")
	_music_combat = _make_stream_player("ExplorerMusicCombat")
	_music_death = _make_stream_player("ExplorerMusicDeath")
	for j in 8:
		var p := AudioStreamPlayer.new()
		p.name = "ExplorerSfx%d" % j
		p.bus = _sfx_bus
		add_child(p)
		_sfx_pool.append(p)
	_load_and_apply_saved_bus_volumes()


func _make_stream_player(node_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.bus = _music_bus
	add_child(p)
	return p


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var st: Variant = load(path)
	return st as AudioStream


func play_file(file: String, volume_db: float = 0.0) -> void:
	var path := AUDIO_DIR.path_join(file)
	var stream := _load_stream(path)
	if stream == null:
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_i]
	_sfx_i = (_sfx_i + 1) % _sfx_pool.size()
	if p.playing:
		p.stop()
	p.stream = stream
	p.volume_db = volume_db
	p.play()


func play_click() -> void:
	play_file("click.mp3", -2.0)


func play_door_open() -> void:
	play_file("door_open.mp3", -6.0)


func play_banging() -> void:
	play_file("banging.mp3")


func play_stairs() -> void:
	play_file("stairs.mp3")


func play_coins() -> void:
	play_file("coins.mp3")


func play_pickup() -> void:
	play_file("pickup.mp3", -2.0)


## Explorer `movement.ex` / `dungeon_live.ex` `play_audio` `chest_open` when treasure dialog is shown.
func play_chest_open() -> void:
	if not _is_display_client():
		return
	play_file("chest_open.mp3", -4.0)


## Explorer `do_level_up` → `push_event(..., %{sound: "orch_hit"})`.
func _play_orch_hit_if_display_client() -> void:
	if not _is_display_client():
		return
	play_file("orch_hit.mp3", -2.0)


## Explorer `quest_item_system.ex` `complete_quest_discovery` — `orch_hit` when quest-complete dialog opens.
func play_quest_completion_fanfare() -> void:
	_play_orch_hit_if_display_client()


## Explorer `dungeon_live.ex` / `combat_system.ex` level-up — same `orch_hit` asset as quest completion.
func play_level_up_hit() -> void:
	_play_orch_hit_if_display_client()


## AUD-01: subtle step on local move (Explorer web has no dedicated footstep in `app.js` sound map).
func play_move_step() -> void:
	if not _is_display_client():
		return
	play_file("wood_click.mp3", -10.0)


func play_death_sting() -> void:
	play_file("death.mp3")


func play_combat_sfx(sound_id: String, _monster_display: String = "") -> void:
	var file := _sfx_file_for_id(sound_id)
	if file.is_empty():
		return
	var vol := -3.0 if sound_id.begins_with("player") else -2.0
	play_file(file, vol)


## AUD-05: deterministic basename for Explorer combat `sound` ids (CI in `check_parse.gd`).
static func combat_sfx_basename_for_sound_id(sound_id: String) -> String:
	match sound_id:
		"player_hit":
			return "player_hit.mp3"
		"player_miss":
			return "player_miss.mp3"
		"monster_hit":
			return "monster_hit.mp3"
		"monster_miss":
			return "monster_miss.mp3"
		"fight":
			return "fight.mp3"
		_:
			return ""


func _sfx_file_for_id(sound_id: String) -> String:
	return combat_sfx_basename_for_sound_id(sound_id)


func _stop_all_music() -> void:
	for p: AudioStreamPlayer in [_music_wander, _music_combat, _music_death]:
		if p.playing:
			p.stop()
		p.stream = null


func _clear_wander_resume_snapshot() -> void:
	_resume_wander_idx = 0
	_resume_wander_seconds = 0.0


func _snapshot_wander_resume_if_playing() -> void:
	if not _music_wander.playing:
		return
	if _current_wander_idx < 1 or _current_wander_idx > 5:
		return
	var st: AudioStream = _music_wander.stream
	if st == null:
		return
	_resume_wander_idx = _current_wander_idx
	_resume_wander_seconds = clamp_wander_resume_seconds(st, _music_wander.get_playback_position())


func start_wander_music_from_seed(wander_seed: int) -> void:
	if not _is_display_client():
		return
	_clear_wander_resume_snapshot()
	var idx := 1 + int(absi(wander_seed)) % 5
	var path := AUDIO_DIR.path_join("dungeon_wanderer%d.mp3" % idx)
	var stream := _load_stream(path)
	if stream == null:
		return
	_stop_all_music()
	_set_loop(stream, true)
	_music_wander.stream = stream
	_music_wander.volume_db = -12.0
	_music_wander.play()
	_music_state = "wander"
	_current_wander_idx = idx


func start_combat_music() -> void:
	if not _is_display_client():
		return
	if _music_state == "combat":
		return
	_snapshot_wander_resume_if_playing()
	var stream := _load_stream(AUDIO_DIR.path_join("dungeon_fight1.mp3"))
	if stream == null:
		return
	_stop_all_music()
	_set_loop(stream, true)
	_music_combat.stream = stream
	_music_combat.volume_db = -12.0
	_music_combat.play()
	_music_state = "combat"


func start_death_music() -> void:
	if not _is_display_client():
		return
	var stream := _load_stream(AUDIO_DIR.path_join("dungeon_death.mp3"))
	if stream == null:
		return
	_stop_all_music()
	_set_loop(stream, false)
	_music_death.stream = stream
	_music_death.volume_db = -12.0
	_music_death.play()
	_music_state = "death"


func resume_wander_after_combat(wander_seed: int) -> void:
	if not _is_display_client():
		return
	if _resume_wander_idx >= 1 and _resume_wander_idx <= 5:
		var path_r := AUDIO_DIR.path_join("dungeon_wanderer%d.mp3" % _resume_wander_idx)
		var stream_r := _load_stream(path_r)
		if stream_r != null:
			var start_at := clamp_wander_resume_seconds(stream_r, _resume_wander_seconds)
			_stop_all_music()
			_set_loop(stream_r, true)
			_music_wander.stream = stream_r
			_music_wander.volume_db = -12.0
			_music_wander.play(start_at)
			_music_state = "wander"
			_current_wander_idx = _resume_wander_idx
			_clear_wander_resume_snapshot()
			return
	start_wander_music_from_seed(wander_seed)


func stop_death_music() -> void:
	if _music_death.playing:
		_music_death.stop()
	_music_death.stream = null
	if _music_state == "death":
		_music_state = "none"


func _set_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop


func _is_display_client() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return true


func _bus_index_or_neg(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	return i


func _set_bus_volume_from_linear(bus_name: String, linear_0_1: float) -> void:
	var bi := _bus_index_or_neg(bus_name)
	if bi < 0:
		return
	var t := clampf(linear_0_1, 0.0, 1.0)
	if t <= 0.0001:
		AudioServer.set_bus_mute(bi, true)
		AudioServer.set_bus_volume_db(bi, -80.0)
	else:
		AudioServer.set_bus_mute(bi, false)
		AudioServer.set_bus_volume_db(bi, linear_to_db(t))


func _load_and_apply_saved_bus_volumes() -> void:
	var sfx_lin := 1.0
	var music_lin := 1.0
	var cf := ConfigFile.new()
	var err := cf.load(USER_AUDIO_CFG)
	if err == OK:
		sfx_lin = float(cf.get_value("audio", "sfx_linear", 1.0))
		music_lin = float(cf.get_value("audio", "music_linear", 1.0))
	_set_bus_volume_from_linear(_sfx_bus, sfx_lin)
	_set_bus_volume_from_linear(_music_bus, music_lin)


func save_bus_volumes_linear(sfx_linear: float, music_linear: float) -> void:
	var cf2 := ConfigFile.new()
	cf2.set_value("audio", "sfx_linear", clampf(sfx_linear, 0.0, 1.0))
	cf2.set_value("audio", "music_linear", clampf(music_linear, 0.0, 1.0))
	cf2.save(USER_AUDIO_CFG)
	_set_bus_volume_from_linear(_sfx_bus, float(cf2.get_value("audio", "sfx_linear")))
	_set_bus_volume_from_linear(_music_bus, float(cf2.get_value("audio", "music_linear")))


func get_saved_sfx_linear() -> float:
	var cf3 := ConfigFile.new()
	if cf3.load(USER_AUDIO_CFG) != OK:
		return 1.0
	return clampf(float(cf3.get_value("audio", "sfx_linear", 1.0)), 0.0, 1.0)


func get_saved_music_linear() -> float:
	var cf4 := ConfigFile.new()
	if cf4.load(USER_AUDIO_CFG) != OK:
		return 1.0
	return clampf(float(cf4.get_value("audio", "music_linear", 1.0)), 0.0, 1.0)
