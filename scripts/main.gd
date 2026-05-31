extends Node3D

# ============================================================
# STERNENFLUCHT — 3D Side-View Twin-Stick Roguelike
# Uses Kenney Space Kit (CC0) ship models for the base craft +
# upgrade attachments (turrets, sensors, fins, etc.).
# ============================================================

# Bumped on every release; the self-updater compares this against the
# latest GitHub release tag (tags are "v" + this string, e.g. "v0.1.0").
const GAME_VERSION := "0.3.4"


# Arena (in world units)
const ARENA_W := 36.0
const ARENA_H := 20.0
const ARENA_PAD := 1.2

# Player base
const P_SPEED := 11.0
const P_HP := 100
const P_RADIUS := 0.55
const P_FIRE_RATE := 0.55
const P_RANGE := 18.0
const P_PICKUP_RANGE := 4.0
const P_INVULN := 0.6

# Projectile
const PROJ_SPEED := 28.0
const PROJ_LIFETIME := 0.65  # tuned so PROJ_SPEED * PROJ_LIFETIME ≈ P_RANGE (≤ on-screen distance)
const PROJ_RADIUS := 0.18

# XP
const XP_BASE := 4
const XP_INC := 3

# Spawn
const SPAWN_RING := 22.0
const SHIP_SCALE_BASE := 1.9
const CAM_OFFSET_BASE := Vector3(0, -10.0, 13.0)
const FIRE_CONE_DEG := 36.0  # half-angle of the cone in front of the ship within which auto-fire works
const MAX_ENEMIES := 60

# Wave
const WAVE_DURATION := 28.0
const BOSS_EVERY := 5
# Enemy composition is gated by player level (party-max in co-op), not just elapsed
# waves — a low-level player never faces shooters/tanks/bosses they can't handle.
const SHOOTER_MIN_LEVEL := 2
const TANK_MIN_LEVEL := 4
const BOSS_MIN_LEVEL := 5

# States
const STATE_PLAYING := 0
const STATE_LEVELUP := 1
const STATE_GAMEOVER := 2
const STATE_HOME := 3      # start / home screen, shown before any run begins
const STATE_SHIPYARD := 4  # modular ship-builder / hangar, opened from the home screen

# Colors
const COL_TEXT := Color(0.95, 0.97, 1.0)
const COL_DIM := Color(0.6, 0.7, 0.85)
const COL_PLAYER := Color(0.55, 0.95, 1.0)
const COL_PLAYER_EMIT := Color(0.25, 0.7, 1.0)
const COL_DRONE := Color(0.92, 0.42, 0.32)
const COL_SHOOTER := Color(1.0, 0.7, 0.25)
const COL_TANK := Color(0.85, 0.35, 0.7)
const COL_BOSS := Color(1.0, 0.4, 0.95)
const COL_PROJ := Color(0.7, 1.0, 0.95)
const COL_LASER_CORE := Color(1.0, 0.85, 0.78)
const COL_LASER := Color(1.0, 0.22, 0.15)
const COL_E_BULLET := Color(1.0, 0.55, 0.35)
const COL_XP := Color(0.55, 1.0, 0.55)

# ============================================================
# Entity
# ============================================================

class Entity:
	var pos: Vector3 = Vector3.ZERO
	var vel: Vector3 = Vector3.ZERO
	var radius: float = 0.5
	var hp: int = 1
	var max_hp: int = 1
	var dead: bool = false
	var type: String = ""
	var color: Color = Color.WHITE
	var damage: int = 0
	var lifetime: float = 0.0
	var shoot_cd: float = 2.0
	var shoot_timer: float = 0.0
	var value: int = 0
	var pulse: float = 0.0
	var pierce: int = 0
	var hit_flash: float = 0.0
	var node: Node3D = null   # the visual MeshInstance3D / Node3D in the scene
	# Multiplayer fields
	var net_id: int = 0       # server-assigned network id (0 = local/single-player)
	var is_mega: bool = false # enemy: special hidden mega-boss world event (radar marker + big reward)
	var marked: bool = false  # enemy: part of an escort event — targets the rescued bot, not the player
	var dna: Dictionary = {}  # enemy: procedural recipe, sent to clients so they rebuild the mesh
	var owner_id: int = 0     # player bullet: peer id of the player who fired it
	var tpos: Vector3 = Vector3.ZERO  # client: target position from the latest snapshot (lerp toward)

# Radar mini-map — bottom-right HUD overlay. Sci-fi style with a rotating
# sweep beam that brightens contacts as it passes over them, soft glow halos
# on every blip, rim ticks every 45°, and off-screen contacts pinned to the
# rim. Holds a back-reference to the main script to sample game state.
# Radial emote menu shown while ALT is held. The segment under the mouse is
# highlighted; releasing ALT fires it (the centre deadzone = cancel). Selection
# logic lives in the main script's _update_emote_wheel.
class EmoteWheel extends Control:
	var hovered: int = -1
	var labels: Array = []
	var wheel_center: Vector2 = Vector2(640, 360)
	var wheel_radius: float = 150.0
	var seg_count: int = 8

	func setup(emotes: Array, font: FontFile) -> void:
		wheel_center = size * 0.5
		seg_count = emotes.size()
		for i in seg_count:
			var lbl := Label.new()
			lbl.text = str(emotes[i])
			lbl.size = Vector2(74, 74)
			lbl.pivot_offset = lbl.size * 0.5
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lbl.add_theme_font_size_override("font_size", 40)
			if font != null:
				lbl.add_theme_font_override("font", font)
			var ang: float = -PI / 2.0 + float(i) / float(seg_count) * TAU
			lbl.position = wheel_center + Vector2(cos(ang), sin(ang)) * wheel_radius - lbl.size * 0.5
			add_child(lbl)
			labels.append(lbl)
		_apply_hover()

	func set_hovered(h: int) -> void:
		if h == hovered:
			return
		hovered = h
		_apply_hover()
		queue_redraw()

	func _apply_hover() -> void:
		for i in labels.size():
			var on: bool = (i == hovered)
			labels[i].scale = Vector2(1.4, 1.4) if on else Vector2.ONE
			labels[i].modulate = Color(1, 1, 1, 1) if on else Color(0.78, 0.84, 0.95, 0.9)

	func _draw() -> void:
		draw_circle(wheel_center, wheel_radius + 52.0, Color(0.02, 0.04, 0.08, 0.72))
		draw_arc(wheel_center, wheel_radius + 52.0, 0.0, TAU, 80, Color(0.4, 0.7, 0.95, 0.5), 2.0)
		draw_circle(wheel_center, 42.0, Color(0.05, 0.08, 0.13, 0.6))
		if hovered >= 0 and seg_count > 0:
			var ang: float = -PI / 2.0 + float(hovered) / float(seg_count) * TAU
			var p: Vector2 = wheel_center + Vector2(cos(ang), sin(ang)) * wheel_radius
			draw_circle(p, 46.0, Color(0.35, 0.75, 1.0, 0.35))

class RadarPanel extends Control:
	var main: Node = null
	var radius_pixels: float = 62.0
	var world_range: float = 80.0
	var sweep_angle: float = 0.0
	var sweep_speed: float = TAU / 3.2  # one revolution per ~3.2s
	var t_accum: float = 0.0            # free-running clock for the mega-event pulse

	func _process(delta: float) -> void:
		sweep_angle = fmod(sweep_angle + delta * sweep_speed, TAU)
		t_accum += delta
		queue_redraw()

	# Soft round glow — three stacked circles of decreasing radius / increasing alpha
	func _draw_blip(at: Vector2, base_col: Color, size: float, intensity: float) -> void:
		var glow: Color = Color(base_col.r, base_col.g, base_col.b, 0.18 * intensity)
		draw_circle(at, size * 2.6, glow)
		glow.a = 0.35 * intensity
		draw_circle(at, size * 1.6, glow)
		var core: Color = base_col
		core.a = clamp(0.85 + intensity * 0.15, 0.0, 1.0)
		draw_circle(at, size, core)

	# Sweep brightness for a contact at the given radar-space angle. Peaks when
	# the sweep beam aligns, fades quickly behind it.
	func _sweep_intensity(blip_angle: float) -> float:
		# Difference modded into [-PI, PI]
		var diff: float = fmod(blip_angle - sweep_angle + PI, TAU)
		if diff < 0.0:
			diff += TAU
		diff -= PI
		# Positive diff = the beam already passed this blip (trail)
		# Negative diff = beam still approaches (no glow yet)
		if diff < 0.0 or diff > 0.6:
			return 0.0
		return 1.0 - diff / 0.6  # linear fade across ~34°

	# Rim arrow for a fellow player — green-cyan chevron pointing outward,
	# distinct from the warm enemy blips so allies read at a glance.
	func _draw_player_arrow(at: Vector2, dir: Vector2) -> void:
		var ally: Color = Color(0.4, 1.0, 0.7)
		# Soft halo
		draw_circle(at, 5.5, Color(ally.r, ally.g, ally.b, 0.22))
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var tip: Vector2 = at + dir * 5.0
		var base_l: Vector2 = at - dir * 3.0 + perp * 4.0
		var base_r: Vector2 = at - dir * 3.0 - perp * 4.0
		draw_polygon(PackedVector2Array([tip, base_l, base_r]),
			PackedColorArray([ally]))

	func _draw() -> void:
		if main == null:
			return
		var c := Vector2(radius_pixels, radius_pixels)
		var r: float = radius_pixels

		# Outer glow ring (2 layers)
		draw_circle(c, r + 6.0, Color(0.25, 0.7, 1.0, 0.08))
		draw_circle(c, r + 3.0, Color(0.25, 0.7, 1.0, 0.18))
		# Disc body with subtle vignette via inner darker disc
		draw_circle(c, r, Color(0.03, 0.06, 0.10, 0.92))
		draw_circle(c, r * 0.5, Color(0.04, 0.08, 0.14, 0.4))
		# Bezel ring (sharp outline)
		draw_arc(c, r, 0.0, TAU, 96, Color(0.35, 0.75, 1.0, 0.85), 1.6, true)

		# Concentric guide rings
		for r_frac in [0.25, 0.5, 0.75]:
			draw_arc(c, r * r_frac, 0.0, TAU, 64,
				Color(0.3, 0.7, 0.95, 0.14), 1.0, true)

		# Radial spokes every 45°
		for i in 8:
			var a: float = float(i) * (TAU / 8.0)
			draw_line(c, c + Vector2(cos(a), sin(a)) * r,
				Color(0.3, 0.7, 0.95, 0.10), 1.0)
		# Rim tick marks every 30° — slightly brighter at cardinals
		for i in 12:
			var a2: float = float(i) * (TAU / 12.0)
			var inner: Vector2 = c + Vector2(cos(a2), sin(a2)) * (r - 4.0)
			var outer: Vector2 = c + Vector2(cos(a2), sin(a2)) * r
			var col: Color = Color(0.4, 0.85, 1.0, 0.45 if i % 3 == 0 else 0.22)
			draw_line(inner, outer, col, 1.0 if i % 3 == 0 else 0.8)

		# Rotating sweep wedge — bright leading line + fading trail
		var lead: Vector2 = c + Vector2(cos(sweep_angle), sin(sweep_angle)) * r
		draw_line(c, lead, Color(0.55, 0.95, 1.0, 0.85), 1.4)
		var trail_arc: float = 0.6
		var n_pts: int = 14
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		pts.append(c)
		cols.append(Color(0.3, 0.85, 1.0, 0.25))
		for i in n_pts:
			var t: float = float(i) / float(n_pts - 1)
			var ang: float = sweep_angle - t * trail_arc
			pts.append(c + Vector2(cos(ang), sin(ang)) * r)
			cols.append(Color(0.4, 0.85, 1.0, 0.32 * (1.0 - t)))
		draw_polygon(pts, cols)

		var p_pos: Vector3 = main.p_pos
		var scale_factor: float = r / world_range

		# Gems — small gold dots with subtle halo
		for g in main.gems:
			if g.dead:
				continue
			var dxy: Vector3 = g.pos - p_pos
			if dxy.length() > world_range:
				continue
			var px: float = r + dxy.x * scale_factor
			var py: float = r - dxy.y * scale_factor
			var ang_g: float = atan2(py - r, px - r)
			var sw_g: float = _sweep_intensity(ang_g)
			_draw_blip(Vector2(px, py), Color(1.0, 0.85, 0.25), 1.6, 0.6 + sw_g * 0.8)

		# Enemies — color + size by strength tier, sweep-modulated brightness
		for e in main.enemies:
			if e.dead:
				continue
			var dxy2: Vector3 = e.pos - p_pos
			var d: float = dxy2.length()
			if e.is_mega:
				# Hidden mega-boss event: shown only within ~MEGA_DETECT (220 units).
				if d <= 220.0:
					var puls: float = 0.55 + 0.45 * sin(t_accum * 5.0)
					var mcol := Color(1.0, 0.35, 0.18)
					if d <= world_range:
						var mp := Vector2(r + dxy2.x * scale_factor, r - dxy2.y * scale_factor)
						draw_arc(mp, 8.0 + puls * 4.0, 0.0, TAU, 28, Color(1.0, 0.45, 0.2, 0.9), 2.0)
						_draw_blip(mp, mcol, 5.0, 0.85 + puls)
					else:
						var dir_m := Vector2(dxy2.x, -dxy2.y).normalized()
						var at_m := c + dir_m * (r - 5.0)
						_draw_blip(at_m, mcol, 4.2, 0.5 + puls)
						var perp := Vector2(-dir_m.y, dir_m.x)
						draw_polygon(PackedVector2Array([at_m + dir_m * 7.0, at_m - dir_m * 3.0 + perp * 4.0, at_m - dir_m * 3.0 - perp * 4.0]), PackedColorArray([Color(1.0, 0.55, 0.25, 0.95)]))
				continue
			var col: Color
			var sz: float = 3.0
			match e.type:
				"drone":
					col = Color(0.55, 1.0, 0.45); sz = 2.0
				"shooter":
					col = Color(1.0, 0.75, 0.35); sz = 2.6
				"tank":
					col = Color(1.0, 0.35, 0.35); sz = 3.3
				"boss":
					col = Color(1.0, 0.3, 0.95); sz = 4.4
				_:
					col = Color(0.85, 0.85, 0.85); sz = 2.5
			var pt: Vector2
			var ang_e: float
			if d <= world_range:
				pt = Vector2(r + dxy2.x * scale_factor, r - dxy2.y * scale_factor)
				ang_e = atan2(pt.y - r, pt.x - r)
				_draw_blip(pt, col, sz, 0.7 + _sweep_intensity(ang_e) * 1.1)
			else:
				# Off-radar contacts pinned to the rim — faint but visible
				var dir2: Vector2 = Vector2(dxy2.x, -dxy2.y).normalized()
				pt = c + dir2 * (r - 3.0)
				ang_e = atan2(dir2.y, dir2.x)
				var fade_col: Color = Color(col.r, col.g, col.b, 0.55)
				_draw_blip(pt, fade_col, sz * 0.75, 0.4 + _sweep_intensity(ang_e) * 0.6)

		# Rescued bot (escort event) — green marker / rim arrow, like the mega cue.
		for f in main.friendlies:
			if f.dead:
				continue
			var dxyf: Vector3 = f.pos - p_pos
			var df: float = dxyf.length()
			if df > 220.0:
				continue
			var pulsf: float = 0.5 + 0.5 * sin(t_accum * 4.0)
			var fcol := Color(0.4, 1.0, 0.55)
			if df <= world_range:
				var fp := Vector2(r + dxyf.x * scale_factor, r - dxyf.y * scale_factor)
				draw_arc(fp, 7.0 + pulsf * 3.0, 0.0, TAU, 24, Color(0.5, 1.0, 0.6, 0.85), 2.0)
				_draw_blip(fp, fcol, 4.0, 0.8 + pulsf)
			else:
				var dirf := Vector2(dxyf.x, -dxyf.y).normalized()
				var atf := c + dirf * (r - 5.0)
				_draw_blip(atf, fcol, 3.6, 0.5 + pulsf)
				var perpf := Vector2(-dirf.y, dirf.x)
				draw_polygon(PackedVector2Array([atf + dirf * 6.0, atf - dirf * 3.0 + perpf * 3.5, atf - dirf * 3.0 - perpf * 3.5]), PackedColorArray([Color(0.5, 1.0, 0.6, 0.9)]))

		# Other players — always pinned to the rim with a directional arrow,
		# regardless of distance, so the party can find each other.
		for id in main.remote_players:
			var rp: Dictionary = main.remote_players[id]
			var rpos: Vector3 = rp["tpos"]
			var dxy_p: Vector3 = rpos - p_pos
			var dir_p: Vector2 = Vector2(dxy_p.x, -dxy_p.y)
			if dir_p.length() < 0.001:
				continue
			dir_p = dir_p.normalized()
			var at_p: Vector2 = c + dir_p * (r - 6.0)
			_draw_player_arrow(at_p, dir_p)

		# Player at the centre — bright glowing triangle pointing in p_facing
		var f: Vector3 = main.p_facing
		var fv: Vector2 = Vector2(f.x, -f.y).normalized()
		var rv: Vector2 = Vector2(-fv.y, fv.x)
		var nose: Vector2 = c + fv * 6.5
		var lwing: Vector2 = c - fv * 3.5 + rv * 3.5
		var rwing: Vector2 = c - fv * 3.5 - rv * 3.5
		# Glow halo
		draw_circle(c, 6.0, Color(0.4, 0.95, 1.0, 0.25))
		draw_polygon(PackedVector2Array([nose, lwing, rwing]),
			PackedColorArray([Color(0.75, 0.97, 1.0)]))

# ============================================================
# Player state
# ============================================================

var p_pos := Vector3.ZERO
var p_vel := Vector3.ZERO
var p_hp: int = P_HP
var p_max_hp: int = P_HP
var p_level: int = 1
var p_xp: int = 0
var p_facing: Vector3 = Vector3(1, 0, 0)
var p_invuln_timer: float = 0.0
var p_node: Node3D            # yaw root (rotates around world Z)
var ship_render: Node3D       # tilted -90° around X so airplane frame becomes top-down
var p_engine_glow: MeshInstance3D
var p_engine_glow_mat: StandardMaterial3D    # legacy primary reference (starboard)
var p_engine_mat_port: StandardMaterial3D = null      # port (left) engine material
var p_engine_mat_starboard: StandardMaterial3D = null # starboard (right) engine material
var p_pulse_lights: Array = []  # entries: {mat: StandardMaterial3D, base: float, amp: float, freq: float, phase: float}
var p_boost_flame: Node3D = null            # twin-flame container; scaled/brightened while boosting
var p_boost_flame_mat: StandardMaterial3D   # shared material for both flames
var p_cam_fov_base: float = 58.0
var p_cam_fov_target: float = 58.0
var p_muzzle_lights: Array = []  # entries: {light: OmniLight3D, flash: MeshInstance3D, mat: StandardMaterial3D, life: float}
var speedlines_layer: CanvasLayer = null
var speedlines: Array = []   # entries: {rect: ColorRect, base_x: float, base_y: float, dir: Vector2, speed: float}
var speedlines_alpha: float = 0.0  # smoothed 0..1 based on whether boost is active

# Upgrade visuals
var visual_guns: Array = []
var visual_engines: Array = []
var visual_armor: Array = []
var visual_sensors: Array = []
var visual_pierce: Node3D = null
var visual_pickup_ring: Node3D = null
var visual_speed_fins: Array = []   # legacy (speed now uses engine pods); kept for safe reset
var visual_damage_core: Node3D = null
var visual_damage_lvl: int = 0
var visual_rate_coils: Array = []    # fire-rate: weapon cooling / overclock coils near the guns
var visual_boost_tanks: Array = []   # boost capacity: fuel canisters on the rear spine
var visual_boost_nozzle: Node3D = null  # boost strength: afterburner nozzles (rebuilt, grows)

# Player upgrades
var u_speed_mult: float = 1.0
var u_fire_rate_mult: float = 1.0
var u_damage: int = 12
var u_projectiles: int = 1
var u_range_mult: float = 1.0
var u_pickup_mult: float = 1.0
var u_spread_deg: float = 14.0
var u_pierce: int = 0

# Boost (Shift): drains current charge; refills empty→full in BOOST_RECHARGE_TIME.
# Tank upgrade grows max capacity; Stärke upgrade grows speed multiplier.
const BOOST_RECHARGE_TIME := 10.0
const BOOST_DRAIN_RATE := 1.0           # charge units drained per second while boosting
var u_boost_max: float = 1.0            # max charge — base allows ~1 sec of boost
var u_boost_strength: float = 1.8       # speed multiplier while boosting
var boost_charge: float = 1.0           # current charge, starts full
var boosting: bool = false
var boost_depleted: bool = false        # latched true when drained to 0, cleared on Shift release

# Entities
var enemies: Array = []
var p_bullets: Array = []
var e_bullets: Array = []
var gems: Array = []

# Wave / spawn
var wave: int = 1
var wave_timer: float = WAVE_DURATION
var spawn_timer: float = 1.5
var spawn_interval: float = 1.5
var fire_timer: float = 0.0

# Camera / shake
var cam: Camera3D
var cam_base_pos: Vector3
var shake_amount: float = 0.0
var shake_timer: float = 0.0

# Run
var kills: int = 0
var run_time: float = 0.0
var state: int = STATE_PLAYING
var pause: bool = false

# Containers
var world: Node3D
var bg_root: Node3D
var stars: Array = []   # Node3D references for parallax stars
var distant_objects: Array = []   # array of dicts: {node, wrap_radius, rot_axis, rot_speed}
var storm_nebulae: Array = []     # subset of nebulae with lightning that can hit the player
									# entries: {node, radius, damage, strike_timer, interval_min, interval_max}
var active_bolts: Array = []      # currently visible lightning bolts: {root, age, lifetime}
var laser_sfx: AudioStreamPlayer       # primary laser shot sound
var laser_sfx_echo: AudioStreamPlayer  # quieter slightly-detuned layer for multi-projectile salvos
var enemy_shot_sfx: AudioStreamPlayer  # deeper / slower thump for enemy projectiles
var damage_sfx: AudioStreamPlayer      # ship-takes-damage impact + metallic ring
var engine_sfx: AudioStreamPlayer      # looping engine whoosh, modulated by speed
var engine_db_smoothed: float = -80.0  # smoothed volume for the engine loop
var thunder_stream: AudioStream        # shared loop for storm-nebula thunder ambience
var enemy_hum_stream: AudioStream      # shared loop for tank/boss enemy hum
var lightning_strike_sfx: AudioStreamPlayer  # sharp crack + boom when a bolt hits
var radar: Control = null  # mini-map control bottom-right of the HUD
var boost_sfx: AudioStreamPlayer       # loop while Shift; volume + pitch drop with charge
var boost_db_smoothed: float = -80.0

# Materials (cached)
var mat_player: StandardMaterial3D
var mat_drone: StandardMaterial3D
var mat_shooter: StandardMaterial3D
var mat_tank: StandardMaterial3D
var mat_boss: StandardMaterial3D
var mat_proj: StandardMaterial3D
var mat_e_bullet: StandardMaterial3D
var mat_gem: StandardMaterial3D

# UI
var hud: CanvasLayer
var hud_game: Control = null   # container for all gameplay HUD; hidden on the home screen
var lbl_hp: Label
var lbl_xp: Label
var lbl_wave: Label
var lbl_time: Label
var lbl_stats: Label
var bar_hp_fill: ColorRect
var bar_xp_fill: ColorRect
var bar_boost_bg: ColorRect
var bar_boost_fill: ColorRect
var lbl_boost: Label
var levelup_panel: Control
var levelup_buttons: Array = []
var go_panel: Control
var go_title: Label
var go_detail: Label

# Self-updater (GitHub Releases). Only active in exported builds, never in
# the editor or on a dedicated server.
const UPDATE_REPO := "BlugDeg/Sternenflucht"
var http_check: HTTPRequest = null
var http_download: HTTPRequest = null
var updater_layer: CanvasLayer = null
var updater_label: Label = null
var updater_btn_yes: Button = null
var updater_btn_no: Button = null
var update_asset_url: String = ""   # browser_download_url of the new Sternenflucht.exe
var update_new_version: String = ""

# ============================================================
# Multiplayer (co-op) — the SAME build runs as single-player (default,
# double-click), a dedicated headless server ("-- --server"), or a client
# joining a server ("-- --connect <ip>"). Server is authoritative; clients
# render. Plain ENet + RPC (no MultiplayerSpawner/Synchronizer).
# ============================================================
enum NetMode { SINGLE, SERVER, CLIENT }
const NET_PORT := 7777
const DEFAULT_SERVER := "sternenflucht.it-en.ch"   # public co-op server (home-screen probe + join)
const NET_MAX_CLIENTS := 32
const NET_TICK := 1.0 / 20.0          # network snapshot rate (20 Hz)
const HS_MAX := 50                    # max highscore entries kept
const HS_FILE := "user://highscores.json"        # server: shared list / single-player: local list
const SETTINGS_FILE := "user://settings.cfg"     # client: name + audio + fullscreen
var net_mode: int = NetMode.SINGLE
var net_server_ip: String = ""   # empty → home screen uses DEFAULT_SERVER; --connect overrides (incl. localhost/LAN)
var net_connected: bool = false
var net_send_accum: float = 0.0
var remote_players := {}              # client: id -> { node: Node3D, tpos: Vector3, tyaw: float }
var net_states := {}                  # server: id -> { pos: Vector3, yaw: float, invuln: float }
var net_next_id: int = 1              # server: incrementing id pool for enemies/bullets/gems
# Client render maps (net_id -> Entity). Kept in lock-step with the enemies/p_bullets/
# e_bullets/gems arrays so radar + auto-aim keep working unchanged on clients.
var cl_enemies := {}
var cl_pbullets := {}
var cl_ebullets := {}
var cl_gems := {}
var cl_designs := {}                  # client: id -> ship_design of each remote player (built into their mesh)

# Player identity + social
var player_name: String = ""          # this client's chosen name (roster + highscore)
var net_roster := {}                  # client: id -> {name, level} (server-reported online list)
var highscores: Array = []            # entries {name, level, wave, kills, time}; server-global or local

# ESC self-pause menu + settings
var menu_open: bool = false           # ESC screen visible (self-pause)
var esc_panel: Control = null
var esc_roster_label: Label = null
var esc_board_label: Label = null
var settings_panel: Control = null
var name_edit: LineEdit = null
var vol_slider: HSlider = null
var fullscreen_check: CheckBox = null
var master_vol_db: float = 0.0        # persisted master bus volume
var fullscreen_on: bool = false       # persisted fullscreen preference

# Game-over highscore UI
var go_name_edit: LineEdit = null
var go_save_btn: Button = null
var go_board_label: Label = null
var score_submitted: bool = false

# --- Home / start screen ---
var home_panel: Control = null
var home_status_label: Label = null
var home_board_label: Label = null
var home_best_label: Label = null
var home_name_edit: LineEdit = null
var home_coop_btn: Button = null
var home_preferred_coop: bool = false   # launched via the co-op .bat → pre-highlight Co-op

# --- Ship builder / hangar (STATE_SHIPYARD) ---
var ship_design: Dictionary = {}          # cosmetic design; filled by _load_settings (default if no file)
var shipyard_panel: Control = null
var shipyard_val_labels: Dictionary = {}  # category key -> Label showing the current option
var _shipyard_backup: Dictionary = {}     # design snapshot on open, restored by "Verwerfen"

# --- Social: emotes + chat ---
var emoji_font: FontFile = null            # Windows Segoe UI Emoji, loaded at boot (client only)
var emote_wheel: EmoteWheel = null         # radial menu, visible while ALT is held
var emote_wheel_open: bool = false
var active_emotes: Array = []              # entries: {label: Label3D, follow: int, timer: float}
var chat_root: Control = null              # holds the chat log + input
var chat_log_label: Label = null
var chat_input: LineEdit = null
var chat_typing: bool = false              # input focused → movement/fire/wheel suppressed
var chat_messages: Array = []              # formatted "Name: text" history

# --- World events (server + single-player authority) ---
var active_event: String = ""              # "", "mega", "escort" — one at a time
var event_timer: float = 45.0              # countdown to the next world event
var mega_active = null                     # Entity ref of the live mega-boss
var escort_bot = null                      # Entity (friendly) of the rescued pilot
var escort_markers: Array = []             # Entity refs of the marked attacker enemies
var escort_timer: float = 0.0              # rescue time limit countdown
var escort_pos: Vector3 = Vector3.ZERO     # bot location (markers target this)
var escort_obj_accum: float = 0.0          # throttle for the objective broadcast
var friendlies: Array = []                 # Entity refs of friendly bots (server logic + render)
var cl_friendlies: Dictionary = {}         # client: net_id -> friendly Entity
var announce_label: Label = null           # transient centre-top HUD banner
var announce_timer: float = 0.0
var objective_label: Label = null          # persistent objective line during an event
var home_probing: bool = false          # a lightweight reachability probe is in flight
var probe_timer: float = 0.0            # connection timeout, shrinks once connected
var home_ship_spin: float = 0.0         # turntable angle for the showcased ship
# Personal best run, persisted locally in settings.cfg (separate from the leaderboard).
var best_level: int = 0
var best_wave: int = 0
var best_kills: int = 0
var best_time: int = 0

# ============================================================
# Lifecycle
# ============================================================

func _ready() -> void:
	_parse_net_mode()
	# Dedicated server: headless authority only — no rendering, no audio, no UI.
	if net_mode == NetMode.SERVER:
		_start_dedicated_server()
		return
	randomize()
	_load_settings()
	_build_environment()
	_build_camera()
	_build_lights()
	_build_materials()
	_build_world()
	_build_starfield()
	_build_audio()
	_build_distant_objects()
	_build_player()
	_build_hud()
	_build_speedlines()
	_build_levelup_panel()
	_build_go_panel()
	_build_esc_panel()
	_apply_settings()
	p_hp = p_max_hp
	_build_updater_ui()
	# Only check for updates from a real exported build (skip editor & server).
	if not OS.has_feature("editor") and not OS.has_feature("dedicated_server"):
		_check_for_updates()
	# Both the double-click launch and the co-op .bat now land on the start screen
	# first. A --connect launch just pre-selects co-op and remembers the address.
	_setup_net_signals()
	_build_home_panel()
	_build_shipyard_panel()
	_load_emoji_font()
	_build_social_ui()
	home_preferred_coop = (net_mode == NetMode.CLIENT)   # co-op .bat → pre-highlight + keep its address
	net_mode = NetMode.SINGLE   # neutral until the player picks on the home screen
	_show_home()

# Reads launch args: dedicated_server feature or "--server" → SERVER,
# "--connect <ip>" / "--connect=<ip>" → CLIENT, otherwise SINGLE.
func _parse_net_mode() -> void:
	if OS.has_feature("dedicated_server"):
		net_mode = NetMode.SERVER
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a := args[i]
		if a == "--server":
			net_mode = NetMode.SERVER
		elif a == "--connect":
			net_mode = NetMode.CLIENT
			if i + 1 < args.size():
				net_server_ip = args[i + 1]
		elif a.begins_with("--connect="):
			net_mode = NetMode.CLIENT
			net_server_ip = a.substr("--connect=".length())

# ============================================================
# Networking — server (authoritative, headless)
# ============================================================

func _start_dedicated_server() -> void:
	randomize()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(NET_PORT, NET_MAX_CLIENTS)
	if err != OK:
		push_error("[MP] create_server fehlgeschlagen: %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_load_highscores_server()
	print("[MP] Dedizierter Server laeuft auf Port %d (max %d Spieler)" % [NET_PORT, NET_MAX_CLIENTS])

func _on_peer_connected(id: int) -> void:
	# Each player carries their OWN wave progression, spawn cadence and kill count —
	# waves are per-player, not a single global counter (which used to run away to
	# wave 100+ because the dedicated server simulates 24/7).
	net_states[id] = {"pos": Vector3.ZERO, "yaw": 0.0, "invuln": 0.0, "busy": false,
		"level": 1, "name": "Pilot", "wave": 1, "wave_timer": WAVE_DURATION,
		"spawn_timer": 1.5, "kills": 0, "design": DEFAULT_SHIP_DESIGN.duplicate()}
	print("[MP] Spieler verbunden: %d  (online: %d)" % [id, net_states.size()])
	_broadcast_roster()

func _on_peer_disconnected(id: int) -> void:
	net_states.erase(id)
	if net_states.is_empty():
		# Last player left — reset the shared world so the next session starts clean
		# (otherwise leftover enemies from a previous session linger on the 24/7 server).
		enemies.clear()
		p_bullets.clear()
		e_bullets.clear()
		gems.clear()
		_reset_events()
	print("[MP] Spieler getrennt: %d  (online: %d)" % [id, net_states.size()])
	_broadcast_roster()

func _next_net_id() -> int:
	net_next_id += 1
	return net_next_id

func _server_process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	# Run the authoritative world simulation every frame for smooth AI,
	_server_sim(delta)
	# but only broadcast a snapshot at the network tick rate.
	net_send_accum += delta
	if net_send_accum < NET_TICK:
		return
	net_send_accum = 0.0
	_server_broadcast()

# The whole shared world lives on the server: enemies, both bullet kinds, gems,
# wave timing and all collisions. Mesh/audio building is skipped (headless).
func _server_sim(delta: float) -> void:
	for id in net_states:
		net_states[id]["invuln"] = max(0.0, net_states[id]["invuln"] - delta)
	_server_update_enemies(delta)
	_server_update_bullets(p_bullets, delta)
	_server_update_bullets(e_bullets, delta)
	_server_update_gems(delta)
	_server_update_spawning(delta)
	_server_update_waves(delta)
	_update_events(delta)
	_server_resolve_collisions()
	_purge_dead()

# Closest connected player's position to a point (enemy AI target). Returns a far
# offset when nobody is connected so idle enemies just drift.
func _nearest_player_pos(from: Vector3) -> Vector3:
	var best: Vector3 = from + Vector3(0, 100, 0)
	var best_d: float = INF
	for id in net_states:
		var pp: Vector3 = net_states[id]["pos"]
		var d: float = pp.distance_to(from)
		if d < best_d:
			best_d = d
			best = pp
	return best

func _server_update_enemies(delta: float) -> void:
	for e in enemies:
		if e.dead:
			continue
		e.hit_flash = max(0.0, e.hit_flash - delta * 4.0)
		# Marked escort attackers target the rescued bot, not the player.
		var tgt: Vector3 = escort_pos if e.marked else _nearest_player_pos(e.pos)
		match e.type:
			"drone":
				_ai_chase(e, delta, 5.0, tgt)
			"shooter":
				_ai_keep_distance(e, delta, 4.2, 11.0, tgt)
				_ai_shoot(e, delta, 8, 9.5, tgt)
			"tank":
				_ai_chase(e, delta, 2.8, tgt)
			"boss":
				if e.is_mega and tgt.distance_to(e.pos) > MEGA_WAKE:
					e.vel = e.vel.lerp(Vector3.ZERO, clamp(delta * 2.0, 0.0, 1.0))   # lurk until found
				else:
					_ai_boss(e, delta, tgt)
		e.pos += e.vel * delta

# Move + expire only (no arena cull — that uses the local player's position which
# is meaningless on the server).
func _server_update_bullets(arr: Array, delta: float) -> void:
	for b in arr:
		if b.dead:
			continue
		b.pos += b.vel * delta
		b.lifetime -= delta
		if b.lifetime <= 0.0:
			b.dead = true

func _server_update_gems(delta: float) -> void:
	for g in gems:
		if g.dead:
			continue
		# Find the nearest player; magnet toward them and grant XP on pickup.
		var np_id: int = -1
		var nd: float = INF
		var npp: Vector3 = Vector3.ZERO
		for id in net_states:
			var pp: Vector3 = net_states[id]["pos"]
			var d: float = pp.distance_to(g.pos)
			if d < nd:
				nd = d
				np_id = id
				npp = pp
		if np_id == -1:
			continue
		if nd <= P_PICKUP_RANGE:
			g.vel = g.vel.lerp((npp - g.pos).normalized() * 20.0 * (1.5 - nd / P_PICKUP_RANGE), clamp(delta * 8.0, 0.0, 1.0))
		else:
			g.vel = g.vel.lerp(Vector3.ZERO, clamp(delta * 4.0, 0.0, 1.0))
		g.pos += g.vel * delta
		if nd <= P_RADIUS + g.radius:
			g.dead = true
			grant_xp.rpc_id(np_id, g.value)

# Per-player spawning: every non-busy player gets their OWN stream of enemies in
# their OWN area, scaled to THEIR wave + level. When two players are close their
# streams overlap, so both wave levels spawn around them at the same time. Busy
# players (level-up / ESC / death screen) get nothing — a safe breather.
func _server_update_spawning(delta: float) -> void:
	if net_states.is_empty():
		return
	for id in net_states:
		var st: Dictionary = net_states[id]
		if st.get("busy", false):
			continue
		st["spawn_timer"] = float(st.get("spawn_timer", 1.5)) - delta
		if st["spawn_timer"] > 0.0:
			continue
		var pw: int = int(st.get("wave", 1))
		st["spawn_timer"] = max(0.35, 1.5 - pw * 0.08)   # this player's wave drives their cadence
		if _alive_enemy_count() >= MAX_ENEMIES:
			continue
		var center: Vector3 = st["pos"]
		var ang: float = randf() * TAU
		var pos: Vector3 = center + Vector3(cos(ang), sin(ang), 0) * SPAWN_RING
		_spawn_enemy(_pick_enemy_kind(int(st.get("level", 1))), pos, pw)

# Per-player wave progression: each player's wave advances on its own timer, and
# their boss waves trigger in their own area — independent of every other player.
func _server_update_waves(delta: float) -> void:
	for id in net_states:
		var st: Dictionary = net_states[id]
		if st.get("busy", false):
			continue
		st["wave_timer"] = float(st.get("wave_timer", WAVE_DURATION)) - delta
		if st["wave_timer"] <= 0.0:
			st["wave"] = int(st.get("wave", 1)) + 1
			st["wave_timer"] = WAVE_DURATION
			var pw: int = int(st["wave"])
			var lvl: int = int(st.get("level", 1))
			if pw % BOSS_EVERY == 0 and lvl >= BOSS_MIN_LEVEL:
				_spawn_boss_for(id)

# Spawn a boss in one player's area, scaled to that player's wave.
func _spawn_boss_for(id: int) -> void:
	if not net_states.has(id) or _alive_enemy_count() >= MAX_ENEMIES:
		return
	var st: Dictionary = net_states[id]
	var center: Vector3 = st["pos"]
	var ang: float = randf() * TAU
	_spawn_enemy("boss", center + Vector3(cos(ang), sin(ang), 0) * (SPAWN_RING * 0.6), int(st.get("wave", 1)))

func _server_resolve_collisions() -> void:
	# Player bullets vs enemies.
	for b in p_bullets:
		if b.dead:
			continue
		for e in enemies:
			if e.dead:
				continue
			if b.pos.distance_to(e.pos) <= b.radius + e.radius:
				e.hp -= b.damage
				e.hit_flash = 1.0
				if b.pierce > 0:
					b.pierce -= 1
				else:
					b.dead = true
				if e.hp <= 0:
					_kill_enemy(e, b.owner_id)   # credit the kill to whoever fired this bullet
				if b.dead:
					break
	# Enemy bullets vs each player.
	for b in e_bullets:
		if b.dead:
			continue
		for id in net_states:
			if net_states[id]["invuln"] > 0.0 or net_states[id].get("busy", false):
				continue
			if b.pos.distance_to(net_states[id]["pos"]) <= P_RADIUS + b.radius:
				_server_hit_player(id, b.damage)
				b.dead = true
				break
	# Enemy bullets vs the rescued bot (escort event).
	if escort_bot != null and not escort_bot.dead:
		for b in e_bullets:
			if b.dead:
				continue
			if b.pos.distance_to(escort_bot.pos) <= escort_bot.radius + b.radius:
				escort_bot.hp -= b.damage
				b.dead = true
				if escort_bot.hp <= 0:
					escort_bot.dead = true
	# Enemy bodies vs each player.
	for e in enemies:
		if e.dead:
			continue
		for id in net_states:
			if net_states[id]["invuln"] > 0.0 or net_states[id].get("busy", false):
				continue
			var pp: Vector3 = net_states[id]["pos"]
			if e.pos.distance_to(pp) <= P_RADIUS + e.radius:
				_server_hit_player(id, e.damage)
				e.pos += (e.pos - pp).normalized() * 1.6

func _server_hit_player(id: int, dmg: int) -> void:
	net_states[id]["invuln"] = P_INVULN
	hit_player.rpc_id(id, dmg)

func _server_spawn_p_bullet(pos: Vector3, vel: Vector3, dmg: int, pierce: int, lifetime: float, by_owner: int) -> void:
	var b := Entity.new()
	b.type = "p_bullet"
	b.pos = pos
	b.vel = vel
	b.radius = PROJ_RADIUS
	b.damage = dmg
	b.pierce = pierce
	b.lifetime = lifetime
	b.owner_id = by_owner
	b.net_id = _next_net_id()
	p_bullets.append(b)

# Build and send the per-tick world snapshot. Enemies are spawned via a separate
# reliable RPC (their DNA), so here they only carry positions; bullets/gems are
# created client-side on first sight from this snapshot.
func _server_broadcast() -> void:
	# Everything lives on the z=0 play plane, so positions/velocities are sent as
	# Vector2. Bulk entity data goes into parallel typed packed arrays (ids +
	# positions [+ velocities]) instead of keyed Dictionaries: PackedInt32Array /
	# PackedVector2Array serialize as raw blocks with no per-entry Variant boxing,
	# which roughly halves the snapshot vs the old Dictionary form and keeps it under
	# the ~1392 B MTU for far more entities (the Dictionary form overflowed at ~24).
	var pid := PackedInt32Array()
	var ppos := PackedVector2Array()
	var pyaw := PackedFloat32Array()
	var pwave := PackedInt32Array()    # each player's own wave (per-player, not global)
	var pkills := PackedInt32Array()   # each player's own kill count
	for id in net_states:
		var st: Dictionary = net_states[id]
		var sp: Vector3 = st["pos"]
		pid.append(id)
		ppos.append(Vector2(sp.x, sp.y))
		pyaw.append(st["yaw"])
		pwave.append(int(st.get("wave", 1)))
		pkills.append(int(st.get("kills", 0)))
	var eid := PackedInt32Array()
	var epos := PackedVector2Array()
	for e in enemies:
		if not e.dead:
			eid.append(e.net_id)
			epos.append(Vector2(e.pos.x, e.pos.y))
	var gid := PackedInt32Array()
	var gpos := PackedVector2Array()
	for g in gems:
		if not g.dead:
			gid.append(g.net_id)
			gpos.append(Vector2(g.pos.x, g.pos.y))
	receive_world.rpc({
		"pid": pid, "ppos": ppos, "pyaw": pyaw, "pwave": pwave, "pkills": pkills,
		"eid": eid, "epos": epos,
		"gid": gid, "gpos": gpos,
	})
	# Bullets are by far the bulk of the snapshot (rapid fire + multi-projectile +
	# enemy fire), so they go in their own unreliable packet — they never share an
	# MTU budget with players/enemies/gems, which keeps both packets well under the
	# ~1392 B MTU. Clients dead-reckon bullet motion by velocity between packets, so a
	# dropped bullet packet is invisible.
	var pbid := PackedInt32Array()
	var pbpos := PackedVector2Array()
	var pbvel := PackedVector2Array()
	for b in p_bullets:
		if not b.dead:
			pbid.append(b.net_id)
			pbpos.append(Vector2(b.pos.x, b.pos.y))
			pbvel.append(Vector2(b.vel.x, b.vel.y))
	var ebid := PackedInt32Array()
	var ebpos := PackedVector2Array()
	var ebvel := PackedVector2Array()
	for b in e_bullets:
		if not b.dead:
			ebid.append(b.net_id)
			ebpos.append(Vector2(b.pos.x, b.pos.y))
			ebvel.append(Vector2(b.vel.x, b.vel.y))
	receive_bullets.rpc({
		"pbid": pbid, "pbpos": pbpos, "pbvel": pbvel,
		"ebid": ebid, "ebpos": ebpos, "ebvel": ebvel,
	})

# Clients push their own transform (and current level, for difficulty scaling)
# here; only the server records it.
@rpc("any_peer", "unreliable_ordered")
func submit_player_state(pos: Vector3, yaw: float, level: int) -> void:
	if net_mode != NetMode.SERVER:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not net_states.has(sender):
		net_states[sender] = {"pos": pos, "yaw": yaw, "invuln": 0.0, "busy": false, "level": level}
	else:
		net_states[sender]["pos"] = pos
		net_states[sender]["yaw"] = yaw
		net_states[sender]["level"] = level

# A client opens/closes its level-up menu. The shared world can't pause for one
# player, so instead the server marks them busy → immune to damage while choosing,
# plus a short grace on resume so they aren't instantly hit by enemies that closed
# in during the menu.
@rpc("any_peer", "call_remote", "reliable")
func notify_busy(b: bool) -> void:
	if net_mode != NetMode.SERVER:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not net_states.has(sender):
		return
	net_states[sender]["busy"] = b
	if not b:
		net_states[sender]["invuln"] = maxf(net_states[sender]["invuln"], 1.0)

# A client restarted its run after dying (co-op). Reset that player's per-player
# wave progression, spawn cadence and kill count so they truly start over —
# otherwise the next snapshot would push the old wave/kills straight back.
@rpc("any_peer", "call_remote", "reliable")
func reset_my_run() -> void:
	if net_mode != NetMode.SERVER:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not net_states.has(sender):
		return
	net_states[sender]["wave"] = 1
	net_states[sender]["wave_timer"] = WAVE_DURATION
	net_states[sender]["spawn_timer"] = 1.5
	net_states[sender]["kills"] = 0

# A client fired: the server creates the authoritative bullets (using the stats
# the client reported — trusting clients is fine for friendly co-op).
@rpc("any_peer", "call_remote", "reliable")
func fire_bullets(origin: Vector3, base_a: float, n: int, spread_deg: float, dmg: int, pierce: int, lifetime: float, speed: float) -> void:
	if net_mode != NetMode.SERVER:
		return
	var sender := multiplayer.get_remote_sender_id()
	n = clampi(n, 1, 32)
	var spread: float = deg_to_rad(spread_deg)
	for i in n:
		var t: float = 0.5 if n == 1 else float(i) / float(n - 1)
		var off: float = (t - 0.5) * spread * (1.0 if n > 1 else 0.0)
		var a: float = base_a + off
		var muzzle_pos: Vector3 = origin + Vector3(cos(a), sin(a), 0) * 0.8
		var bullet_vel: Vector3 = Vector3(cos(a), sin(a), 0) * speed
		_server_spawn_p_bullet(muzzle_pos, bullet_vel, dmg, pierce, lifetime, sender)

# ============================================================
# Networking — roster (who's online) + highscores (server-authoritative)
# ============================================================

# A client reports its display name; the server records it and re-broadcasts the
# online roster so everyone's ESC screen updates.
@rpc("any_peer", "call_remote", "reliable")
func set_player_name(pname: String) -> void:
	if net_mode != NetMode.SERVER:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not net_states.has(sender):
		return
	net_states[sender]["name"] = _sanitize_name(pname)
	_broadcast_roster()

# id -> {name, level} for every connected player.
func _build_roster() -> Dictionary:
	var r := {}
	for id in net_states:
		r[id] = {
			"name": net_states[id].get("name", "Pilot"),
			"level": int(net_states[id].get("level", 1)),
		}
	return r

func _broadcast_roster() -> void:
	if net_mode != NetMode.SERVER:
		return
	receive_roster.rpc(_build_roster())

# A client asks for a fresh roster / highscore list (e.g. on opening ESC or on connect).
@rpc("any_peer", "call_remote", "reliable")
func request_roster() -> void:
	if net_mode != NetMode.SERVER:
		return
	receive_roster.rpc_id(multiplayer.get_remote_sender_id(), _build_roster())

# ============================================================
# Networking — modular ship designs (cosmetic; like enemy DNA, too varied for the
# unreliable snapshot, so sent reliably once on join and re-broadcast on change).
# The server only stores + relays the design data — it NEVER builds a mesh
# (headless authority). Clients build each peer's ship from the received design.
# ============================================================

# A client reports its ship design. The server validates it (so a malformed
# design can never reach other clients' mesh builder), stores it on the peer's
# state, and re-broadcasts every design so all clients rebuild affected ships.
@rpc("any_peer", "call_remote", "reliable")
func submit_ship_design(design: Dictionary) -> void:
	if net_mode != NetMode.SERVER:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not net_states.has(sender):
		return
	net_states[sender]["design"] = _sanitize_ship_design(design)
	_broadcast_designs()

# Clamp/whitelist every field so the server only ever relays well-formed designs.
func _sanitize_ship_design(d: Dictionary) -> Dictionary:
	var out := DEFAULT_SHIP_DESIGN.duplicate()
	out["palette"] = clampi(int(d.get("palette", 0)), 0, SHIP_PALETTES.size() - 1)
	var w := str(d.get("wings", "swept"))
	out["wings"] = w if w in SHIP_WING_OPTS else "swept"
	var en := int(d.get("engines", 2))
	out["engines"] = en if en in SHIP_ENGINE_OPTS else 2
	var t := str(d.get("tail", "twin"))
	out["tail"] = t if t in SHIP_TAIL_OPTS else "twin"
	var n := str(d.get("nose", "pointed"))
	out["nose"] = n if n in SHIP_NOSE_OPTS else "pointed"
	var l := str(d.get("leds", "auto"))
	out["leds"] = l if l in SHIP_LED_OPTS else "auto"
	return out

# id -> ship_design for every connected player.
func _build_designs() -> Dictionary:
	var r := {}
	for id in net_states:
		r[id] = net_states[id].get("design", DEFAULT_SHIP_DESIGN)
	return r

func _broadcast_designs() -> void:
	if net_mode != NetMode.SERVER:
		return
	receive_ship_designs.rpc(_build_designs())

# A joining client pulls every current design so it can build ships already online.
@rpc("any_peer", "call_remote", "reliable")
func request_ship_designs() -> void:
	if net_mode != NetMode.SERVER:
		return
	receive_ship_designs.rpc_id(multiplayer.get_remote_sender_id(), _build_designs())

# --- Emote relay: client picks → server validates → everyone shows it ---
@rpc("any_peer", "call_remote", "reliable")
func submit_emote(idx: int) -> void:
	if net_mode != NetMode.SERVER:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not net_states.has(sender):
		return
	receive_emote.rpc(sender, clampi(idx, 0, EMOTES.size() - 1))

@rpc("authority", "call_remote", "reliable")
func receive_emote(id: int, idx: int) -> void:
	if net_mode != NetMode.CLIENT or home_probing:
		return
	_show_emote_above(id, idx)

# --- Chat relay: server stamps the sender's name and broadcasts to all ---
@rpc("any_peer", "call_remote", "reliable")
func submit_chat(text: String) -> void:
	if net_mode != NetMode.SERVER:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not net_states.has(sender):
		return
	var clean := text.strip_edges()
	if clean.length() > CHAT_MAX_LEN:
		clean = clean.substr(0, CHAT_MAX_LEN)
	if clean.is_empty():
		return
	receive_chat.rpc(str(net_states[sender].get("name", "Pilot")), clean)

@rpc("authority", "call_remote", "reliable")
func receive_chat(sender_name: String, text: String) -> void:
	if net_mode != NetMode.CLIENT or home_probing:
		return
	_append_chat("%s: %s" % [sender_name, text])

@rpc("any_peer", "call_remote", "reliable")
func request_highscores() -> void:
	if net_mode != NetMode.SERVER:
		return
	receive_highscores.rpc_id(multiplayer.get_remote_sender_id(), highscores)

# A client submits a finished run. The server stores it, sorts, trims, persists to
# disk, and broadcasts the updated board to everyone.
@rpc("any_peer", "call_remote", "reliable")
func submit_score(pname: String, level: int, wave_n: int, kills_n: int, time_s: int) -> void:
	if net_mode != NetMode.SERVER:
		return
	var entry := {
		"name": _sanitize_name(pname),
		"level": clampi(level, 1, 9999),
		"wave": clampi(wave_n, 1, 99999),
		"kills": clampi(kills_n, 0, 9999999),
		"time": clampi(time_s, 0, 999999),
	}
	highscores.append(entry)
	_sort_highscores()
	if highscores.size() > HS_MAX:
		highscores.resize(HS_MAX)
	_save_highscores_server()
	receive_highscores.rpc(highscores)

# Sort by level, then wave, then kills, then (shorter) time — "who reached the
# highest level" first.
func _sort_highscores() -> void:
	highscores.sort_custom(func(a, b):
		if a["level"] != b["level"]:
			return a["level"] > b["level"]
		if a.get("wave", 0) != b.get("wave", 0):
			return a.get("wave", 0) > b.get("wave", 0)
		if a.get("kills", 0) != b.get("kills", 0):
			return a.get("kills", 0) > b.get("kills", 0)
		return a.get("time", 0) < b.get("time", 0)
	)

func _save_highscores_server() -> void:
	var f := FileAccess.open(HS_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(highscores))
		f.close()

func _load_highscores_server() -> void:
	if not FileAccess.file_exists(HS_FILE):
		return
	var f := FileAccess.open(HS_FILE, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		highscores = parsed
		_sort_highscores()

func _sanitize_name(pname: String) -> String:
	var s := pname.strip_edges()
	if s.is_empty():
		s = "Pilot"
	return s.substr(0, 18)

# ============================================================
# Networking — client
# ============================================================

func _start_client() -> void:
	# The server may be given as a hostname (e.g. the nginx-proxied domain
	# sternenflucht.it-en.ch) — ENet needs a numeric IP, so resolve it first.
	var addr := net_server_ip
	if not addr.is_valid_ip_address():
		var resolved := IP.resolve_hostname(addr, IP.TYPE_IPV4)
		if resolved.is_empty():
			resolved = IP.resolve_hostname(addr, IP.TYPE_ANY)
		if not resolved.is_empty():
			print("[MP] %s -> %s" % [addr, resolved])
			addr = resolved
		else:
			push_error("[MP] Konnte Hostname nicht aufloesen: %s" % addr)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, NET_PORT)
	if err != OK:
		push_error("[MP] create_client fehlgeschlagen: %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	print("[MP] Verbinde zu %s:%d ..." % [addr, NET_PORT])

# Connect the client multiplayer signals exactly once (the home-screen probe and a
# real co-op join both call _start_client, and signals live on the MultiplayerAPI,
# not the peer — so they must not be re-connected each time).
func _setup_net_signals() -> void:
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_connected_to_server() -> void:
	net_connected = true
	print("[MP] Verbunden als Spieler %d" % multiplayer.get_unique_id())
	# Announce our name (drives the roster) and pull the current board + roster.
	set_player_name.rpc_id(1, player_name)
	request_highscores.rpc_id(1)
	request_roster.rpc_id(1)
	if home_probing:
		# Status probe only: stay protected and disconnect again shortly once the
		# roster + board have arrived. We never render the streamed world here.
		notify_busy.rpc_id(1, true)
		probe_timer = 0.8
	else:
		# Real join: announce our ship design and pull everyone else's so we can
		# build their custom ships as their snapshots arrive.
		submit_ship_design.rpc_id(1, ship_design)
		request_ship_designs.rpc_id(1)

func _on_connection_failed() -> void:
	net_connected = false
	push_error("[MP] Verbindung zum Server fehlgeschlagen")
	if home_probing:
		_home_probe_finish()

func _on_server_disconnected() -> void:
	net_connected = false
	if home_probing:
		_home_probe_finish()
		return
	for id in remote_players.keys():
		remote_players[id]["node"].queue_free()
	remote_players.clear()
	cl_designs.clear()
	_clear_emotes()
	for f in friendlies:
		if f != null and f.node != null:
			f.node.queue_free()
	friendlies.clear()
	cl_friendlies.clear()
	_apply_objective("")
	net_roster.clear()
	if menu_open:
		_refresh_esc_lists()
	print("[MP] Server-Verbindung verloren")

# Server pushes the current online roster (id -> {name, level}).
@rpc("authority", "call_remote", "reliable")
func receive_roster(roster: Dictionary) -> void:
	if net_mode != NetMode.CLIENT:
		return
	net_roster = roster
	if menu_open:
		_refresh_esc_lists()
	if home_probing and home_status_label != null:
		var others: int = maxi(0, net_roster.size() - 1)
		home_status_label.text = "● Server online  —  %d %s" % [others, "Spieler" if others != 1 else "Spieler"]

# Server pushes every player's ship design (id -> design). We store them and, for
# any remote ship already on screen, rebuild it so the new look applies live.
# Ships not yet visible are built from cl_designs when their snapshot first arrives.
@rpc("authority", "call_remote", "reliable")
func receive_ship_designs(designs: Dictionary) -> void:
	if net_mode != NetMode.CLIENT or home_probing:
		return
	var my_id := multiplayer.get_unique_id()
	for key in designs:
		var id: int = int(key)
		if id == my_id:
			continue   # our own ship is the local p_node, not a remote mirror
		cl_designs[id] = designs[key]
		if remote_players.has(id):
			_rebuild_remote_player(id)

# Free a remote player's ship node and rebuild it from its current cl_designs entry,
# preserving the node's transform so it doesn't visibly jump.
func _rebuild_remote_player(id: int) -> void:
	if not remote_players.has(id):
		return
	var rp: Dictionary = remote_players[id]
	var pos: Vector3 = rp.get("tpos", Vector3.ZERO)
	var rot: Vector3 = Vector3.ZERO
	var old = rp.get("node")
	if old != null:
		pos = old.position
		rot = old.rotation
		old.queue_free()
	var node := _build_ship_visual(cl_designs.get(id, DEFAULT_SHIP_DESIGN))
	world.add_child(node)
	node.position = pos
	node.rotation = rot
	rp["node"] = node

# Server pushes the current highscore board (already sorted).
@rpc("authority", "call_remote", "reliable")
func receive_highscores(list: Array) -> void:
	if net_mode != NetMode.CLIENT:
		return
	highscores = list
	if menu_open:
		_refresh_esc_lists()
	if go_panel != null and go_panel.visible:
		_refresh_go_board()
	if home_panel != null and home_panel.visible:
		_refresh_home_board()

# Server reliably announces a new enemy with its full DNA so the client can
# rebuild the exact procedural mesh; positions then stream in receive_world.
@rpc("authority", "call_remote", "reliable")
func spawn_enemy(net_id: int, dna: Dictionary, pos: Vector3) -> void:
	if net_mode != NetMode.CLIENT or home_probing:
		return
	if cl_enemies.has(net_id):
		return
	var e := Entity.new()
	e.type = dna.get("role", "drone")
	e.net_id = net_id
	e.is_mega = dna.get("mega", false)   # radar marker + reward cue on clients
	e.pos = pos
	e.tpos = pos
	e.node = _build_procedural_enemy(dna)
	e.node.position = pos
	world.add_child(e.node)
	cl_enemies[net_id] = e
	enemies.append(e)

@rpc("authority", "call_remote", "reliable")
func despawn_enemy(net_id: int) -> void:
	if net_mode != NetMode.CLIENT or not cl_enemies.has(net_id):
		return
	var e: Entity = cl_enemies[net_id]
	if e.node != null:
		e.node.queue_free()
	e.dead = true
	cl_enemies.erase(net_id)
	enemies.erase(e)

# Server tells one specific client it took damage (the client owns its own HP,
# i-frames and death/respawn).
@rpc("authority", "call_remote", "reliable")
func hit_player(dmg: int) -> void:
	if net_mode != NetMode.CLIENT:
		return
	if p_invuln_timer > 0.0:
		return
	_player_take_damage(dmg)

# Server tells one client it picked up a gem.
@rpc("authority", "call_remote", "reliable")
func grant_xp(value: int) -> void:
	if net_mode != NetMode.CLIENT:
		return
	p_xp += value
	_check_level_up()

# The full per-tick world snapshot. Players + enemy positions are updated for
# known ids; bullets and gems are created on first sight and removed when absent.
@rpc("authority", "call_remote", "unreliable")
func receive_world(snap: Dictionary) -> void:
	if net_mode != NetMode.CLIENT or home_probing:
		return
	_apply_players(snap.get("pid", PackedInt32Array()), snap.get("ppos", PackedVector2Array()), snap.get("pyaw", PackedFloat32Array()), snap.get("pwave", PackedInt32Array()), snap.get("pkills", PackedInt32Array()))
	_apply_enemy_positions(snap.get("eid", PackedInt32Array()), snap.get("epos", PackedVector2Array()))
	_apply_gems(snap.get("gid", PackedInt32Array()), snap.get("gpos", PackedVector2Array()))

# Bullets stream in their own unreliable packet (see _server_broadcast).
@rpc("authority", "call_remote", "unreliable")
func receive_bullets(snap: Dictionary) -> void:
	if net_mode != NetMode.CLIENT or home_probing:
		return
	_apply_bullets(snap.get("pbid", PackedInt32Array()), snap.get("pbpos", PackedVector2Array()), snap.get("pbvel", PackedVector2Array()), cl_pbullets, p_bullets, true)
	_apply_bullets(snap.get("ebid", PackedInt32Array()), snap.get("ebpos", PackedVector2Array()), snap.get("ebvel", PackedVector2Array()), cl_ebullets, e_bullets, false)

func _apply_players(ids: PackedInt32Array, posv: PackedVector2Array, yawv: PackedFloat32Array, wavev: PackedInt32Array, killsv: PackedInt32Array) -> void:
	var my_id := multiplayer.get_unique_id()
	var seen := {}
	for i in ids.size():
		var id: int = ids[i]
		if id == my_id:
			# The server owns our wave + kill count — mirror them for HUD + score.
			if i < wavev.size():
				wave = wavev[i]
			if i < killsv.size():
				kills = killsv[i]
			continue
		seen[id] = true
		var pos: Vector3 = Vector3(posv[i].x, posv[i].y, 0)
		var yaw: float = yawv[i]
		if not remote_players.has(id):
			var node := _build_ship_visual(cl_designs.get(id, DEFAULT_SHIP_DESIGN))
			world.add_child(node)
			node.position = pos
			node.rotation = Vector3(0, 0, yaw)
			remote_players[id] = {"node": node, "tpos": pos, "tyaw": yaw}
			print("[MP] Mitspieler erschienen: %d  (sichtbar: %d)" % [id, remote_players.size()])
		else:
			remote_players[id]["tpos"] = pos
			remote_players[id]["tyaw"] = yaw
	for id in remote_players.keys():
		if not seen.has(id):
			remote_players[id]["node"].queue_free()
			remote_players.erase(id)
			cl_designs.erase(id)
			print("[MP] Mitspieler verschwunden: %d  (sichtbar: %d)" % [int(id), remote_players.size()])

func _apply_enemy_positions(ids: PackedInt32Array, posv: PackedVector2Array) -> void:
	for i in ids.size():
		var net_id: int = ids[i]
		if cl_enemies.has(net_id):
			cl_enemies[net_id].tpos = Vector3(posv[i].x, posv[i].y, 0)

func _apply_bullets(ids: PackedInt32Array, posv: PackedVector2Array, velv: PackedVector2Array, dict: Dictionary, arr: Array, is_player: bool) -> void:
	var seen := {}
	for i in ids.size():
		var net_id: int = ids[i]
		seen[net_id] = true
		var bp: Vector2 = posv[i]
		var bv: Vector2 = velv[i]
		if dict.has(net_id):
			var b: Entity = dict[net_id]
			b.pos = Vector3(bp.x, bp.y, 0)
			b.vel = Vector3(bv.x, bv.y, 0)
		else:
			var b := Entity.new()
			b.type = "p_bullet" if is_player else "e_bullet"
			b.net_id = net_id
			b.pos = Vector3(bp.x, bp.y, 0)
			b.vel = Vector3(bv.x, bv.y, 0)
			b.node = _make_player_laser_mesh(b.vel) if is_player else _make_bullet_mesh(false)
			b.node.position = b.pos
			world.add_child(b.node)
			dict[net_id] = b
			arr.append(b)
	for net_id in dict.keys():
		if not seen.has(net_id):
			var b: Entity = dict[net_id]
			if b.node != null:
				b.node.queue_free()
			dict.erase(net_id)
			arr.erase(b)

func _apply_gems(ids: PackedInt32Array, posv: PackedVector2Array) -> void:
	var seen := {}
	for i in ids.size():
		var net_id: int = ids[i]
		seen[net_id] = true
		var pos: Vector3 = Vector3(posv[i].x, posv[i].y, 0)
		if cl_gems.has(net_id):
			cl_gems[net_id].tpos = pos
		else:
			var g := Entity.new()
			g.type = "gem"
			g.net_id = net_id
			g.pos = pos
			g.tpos = pos
			g.radius = 0.35
			g.node = _make_gem_mesh()
			g.node.position = pos
			world.add_child(g.node)
			cl_gems[net_id] = g
			gems.append(g)
	for net_id in cl_gems.keys():
		if not seen.has(net_id):
			var g: Entity = cl_gems[net_id]
			if g.node != null:
				g.node.queue_free()
			cl_gems.erase(net_id)
			gems.erase(g)

# Per-frame client networking: send my transform, then smoothly interpolate every
# remote thing toward its latest snapshot value.
func _client_net_update(delta: float) -> void:
	if net_connected:
		net_send_accum += delta
		if net_send_accum >= NET_TICK:
			net_send_accum = 0.0
			submit_player_state.rpc_id(1, p_pos, atan2(p_facing.y, p_facing.x), p_level)
	# Remote player ships
	for id in remote_players:
		var r: Dictionary = remote_players[id]
		var n: Node3D = r["node"]
		n.position = n.position.lerp(r["tpos"], clamp(delta * 12.0, 0.0, 1.0))
		var nz: float = lerp_angle(n.rotation.z, r["tyaw"], clamp(delta * 12.0, 0.0, 1.0))
		n.rotation = Vector3(0, 0, nz)
	# Enemies — lerp toward snapshot position; keep e.pos current for aim/radar.
	for net_id in cl_enemies:
		var e: Entity = cl_enemies[net_id]
		e.pos = e.pos.lerp(e.tpos, clamp(delta * 12.0, 0.0, 1.0))
		if e.node != null:
			e.node.position = e.pos
	# Bullets — extrapolate by velocity between the 20 Hz snapshots so they glide.
	for net_id in cl_pbullets:
		var b: Entity = cl_pbullets[net_id]
		b.pos += b.vel * delta
		if b.node != null:
			b.node.position = b.pos
	for net_id in cl_ebullets:
		var b: Entity = cl_ebullets[net_id]
		b.pos += b.vel * delta
		if b.node != null:
			b.node.position = b.pos
	# Gems — lerp + the same idle spin/pulse the single-player gems have.
	for net_id in cl_gems:
		var g: Entity = cl_gems[net_id]
		g.pos = g.pos.lerp(g.tpos, clamp(delta * 12.0, 0.0, 1.0))
		g.pulse += delta
		if g.node != null:
			g.node.position = g.pos
			g.node.rotation.z = g.pulse * 4.0
			var s: float = 0.9 + sin(g.pulse * 6.0) * 0.12
			g.node.scale = Vector3(s, s, s)

# Standalone copy of the player ship for a remote co-op player. Reuses the exact
# geometry of _assemble_ship_body() by temporarily redirecting the member vars it
# writes, then restoring them so the local player's ship is untouched.
func _build_ship_visual(design: Dictionary = DEFAULT_SHIP_DESIGN) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * SHIP_SCALE_BASE
	var sr := Node3D.new()
	sr.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(sr)

	var s_render := ship_render
	var s_pulse := p_pulse_lights
	var s_ep := p_engine_mat_port
	var s_es := p_engine_mat_starboard
	var s_eg := p_engine_glow
	var s_egm := p_engine_glow_mat
	var s_bf := p_boost_flame
	var s_bfm := p_boost_flame_mat
	# Remote ships are built from the peer's synced design. Swap the member around
	# the build (which reads ship_design) so it doesn't clobber our own design.
	var s_design := ship_design
	ship_design = design

	ship_render = sr
	p_pulse_lights = []   # throwaway — remote ships glow but don't pulse-animate
	_assemble_ship_body()

	ship_design = s_design
	ship_render = s_render
	p_pulse_lights = s_pulse
	p_engine_mat_port = s_ep
	p_engine_mat_starboard = s_es
	p_engine_glow = s_eg
	p_engine_glow_mat = s_egm
	p_boost_flame = s_bf
	p_boost_flame_mat = s_bfm
	return root

func _build_audio() -> void:
	# Procedural laser zap — descending frequency, exponential decay envelope.
	# Generated once at startup; AudioStreamPlayer.max_polyphony lets rapid
	# shots layer instead of cutting each other off.
	var stream: AudioStreamWAV = _make_laser_sound()
	laser_sfx = AudioStreamPlayer.new()
	laser_sfx.stream = stream
	laser_sfx.volume_db = -8.0
	laser_sfx.max_polyphony = 8
	add_child(laser_sfx)
	# Subtle detuned echo layer — only triggered on multi-projectile salvos
	laser_sfx_echo = AudioStreamPlayer.new()
	laser_sfx_echo.stream = stream
	laser_sfx_echo.volume_db = -20.0
	laser_sfx_echo.pitch_scale = 0.88
	laser_sfx_echo.max_polyphony = 4
	add_child(laser_sfx_echo)
	# Enemy projectile sound — deeper, slower, slightly buzzy "thump"
	enemy_shot_sfx = AudioStreamPlayer.new()
	enemy_shot_sfx.stream = _make_enemy_shot_sound()
	enemy_shot_sfx.volume_db = -14.0
	enemy_shot_sfx.max_polyphony = 12
	add_child(enemy_shot_sfx)
	# Player ship damage — noise impact + low thump + metallic ring overtone
	damage_sfx = AudioStreamPlayer.new()
	damage_sfx.stream = _make_damage_sound()
	damage_sfx.volume_db = -14.0
	damage_sfx.max_polyphony = 3
	add_child(damage_sfx)
	# Engine loop — always playing, volume gated by ship speed in _update_player
	engine_sfx = AudioStreamPlayer.new()
	engine_sfx.stream = _make_engine_sound()
	engine_sfx.volume_db = -80.0
	add_child(engine_sfx)
	engine_sfx.play()
	# Shared streams for 3D ambient sources attached to nebulae and enemies
	thunder_stream = _make_thunder_sound()
	enemy_hum_stream = _make_enemy_hum_sound()
	# Lightning strike crack — non-3D since the bolt always lands on the player
	lightning_strike_sfx = AudioStreamPlayer.new()
	lightning_strike_sfx.stream = _make_lightning_strike_sound()
	lightning_strike_sfx.volume_db = -4.0
	lightning_strike_sfx.max_polyphony = 4
	add_child(lightning_strike_sfx)
	# Boost loop — always playing, gated by volume + pitch based on charge level
	boost_sfx = AudioStreamPlayer.new()
	boost_sfx.stream = _make_boost_sound()
	boost_sfx.volume_db = -80.0
	add_child(boost_sfx)
	boost_sfx.play()

func _make_laser_sound() -> AudioStreamWAV:
	var sample_rate: int = 22050
	var duration: float = 0.18
	var n_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	var phase: float = 0.0
	for i in n_samples:
		var t: float = float(i) / float(sample_rate)
		var freq: float = lerp(1800.0, 350.0, t / duration)
		phase += TAU * freq / float(sample_rate)
		var env: float = exp(-t * 9.0) * 0.55
		# Sine + a touch of square for crispness
		var sq: float = 1.0 if sin(phase * 0.5) >= 0.0 else -1.0
		var s: float = (sin(phase) * 0.75 + sq * 0.25) * env
		var v: int = int(clamp(s * 32767.0, -32767.0, 32767.0))
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream

func _make_damage_sound() -> AudioStreamWAV:
	# Three-layer hit: short noise burst (impact), low descending thump (mass),
	# tuned metallic ring overtone (clang). Conveys "something hit the ship".
	var sample_rate: int = 22050
	var duration: float = 0.28
	var n_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	var phase_low: float = 0.0
	var phase_ring: float = 0.0
	for i in n_samples:
		var t: float = float(i) / float(sample_rate)
		var freq_low: float = lerp(440.0, 220.0, clamp(t / 0.10, 0.0, 1.0))
		phase_low += TAU * freq_low / float(sample_rate)
		phase_ring += TAU * 1180.0 / float(sample_rate)
		var noise_env: float = exp(-t * 70.0)              # very short crack at the start
		var noise: float = (randf() * 2.0 - 1.0) * noise_env * 0.45
		var thump: float = sin(phase_low) * exp(-t * 9.5) * 0.55
		var ring: float = sin(phase_ring) * exp(-t * 6.0) * 0.28
		var s: float = noise + thump + ring
		var v: int = int(clamp(s * 32767.0, -32767.0, 32767.0))
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream

func _make_boost_sound() -> AudioStreamWAV:
	# Mid-frequency roar (band-pass-ish on noise) + a low bass tone for thrust.
	# Caller modulates volume_db and pitch_scale to convey remaining charge.
	var sample_rate: int = 22050
	var duration: float = 2.0
	var n_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	var lp1: float = 0.0
	var lp2: float = 0.0
	var lp_a: float = 0.06    # low-pass for body
	var lp_a2: float = 0.35   # tighter for the HP differentiation
	for _i in 500:
		var n_in: float = randf() * 2.0 - 1.0
		lp1 += (n_in - lp1) * lp_a
		lp2 += (lp1 - lp2) * lp_a2
	var bass_freq: float = round(78.0 * duration) / duration
	var phase_bass: float = 0.0
	for i in n_samples:
		var n_in2: float = randf() * 2.0 - 1.0
		lp1 += (n_in2 - lp1) * lp_a
		lp2 += (lp1 - lp2) * lp_a2
		var roar: float = (lp2 - lp1) * 3.5  # pseudo band-pass via LP difference
		phase_bass += TAU * bass_freq / float(sample_rate)
		var bass: float = sin(phase_bass) * 0.18
		var s: float = roar + bass
		var v: int = int(clamp(s * 32767.0, -32767.0, 32767.0))
		data.encode_s16(i * 2, v)
	var fade_n: int = int(0.13 * float(sample_rate))
	for i in fade_n:
		var blend: float = float(i) / float(fade_n)
		var idx_end: int = (n_samples - fade_n + i) * 2
		var v_end: float = float(data.decode_s16(idx_end))
		var v_start: float = float(data.decode_s16(i * 2))
		data.encode_s16(idx_end, int(lerp(v_end, v_start, blend)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = n_samples
	return stream

func _make_lightning_strike_sound() -> AudioStreamWAV:
	# Sharp crack (mid-frequency bandpass-ish noise burst) immediately followed
	# by a low-frequency boom that decays over ~0.8s.
	var sample_rate: int = 22050
	var duration: float = 0.85
	var n_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	# Bandpass-style: HP via running diff on a low-pass result
	var lp_crack: float = 0.0
	var lp_crack2: float = 0.0
	var lp_boom1: float = 0.0
	var lp_boom2: float = 0.0
	for i in n_samples:
		var t: float = float(i) / float(sample_rate)
		var n_in: float = randf() * 2.0 - 1.0
		# Crack: highish-passed noise, very short envelope
		lp_crack += (n_in - lp_crack) * 0.35
		lp_crack2 += (lp_crack - lp_crack2) * 0.35
		var hp: float = n_in - lp_crack2
		var crack_env: float = exp(-t * 40.0)
		var crack: float = hp * crack_env * 1.2
		# Boom: deep low-pass noise with longer tail
		lp_boom1 += (n_in - lp_boom1) * 0.04
		lp_boom2 += (lp_boom1 - lp_boom2) * 0.04
		var boom_env: float = exp(-t * 4.5) * (1.0 - exp(-t * 25.0))  # quick attack, slower decay
		var boom: float = lp_boom2 * 14.0 * boom_env
		var s: float = crack + boom
		var v: int = int(clamp(s * 32767.0, -32767.0, 32767.0))
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream

func _make_thunder_sound() -> AudioStreamWAV:
	# Deep three-pole low-pass on white noise → distant rumble. Slow volume
	# undulation makes it sound like rolling thunder rather than steady static.
	var sample_rate: int = 22050
	var duration: float = 4.0
	var n_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	var lp1: float = 0.0
	var lp2: float = 0.0
	var lp3: float = 0.0
	var lp_a: float = 0.012
	for _i in 800:
		var n_in: float = randf() * 2.0 - 1.0
		lp1 += (n_in - lp1) * lp_a
		lp2 += (lp1 - lp2) * lp_a
		lp3 += (lp2 - lp3) * lp_a
	for i in n_samples:
		var n_in2: float = randf() * 2.0 - 1.0
		lp1 += (n_in2 - lp1) * lp_a
		lp2 += (lp1 - lp2) * lp_a
		lp3 += (lp2 - lp3) * lp_a
		var t: float = float(i) / float(sample_rate)
		var mod_freq: float = round(0.35 * duration) / duration  # phase-aligned for clean loop
		var swell: float = 0.4 + 0.6 * (0.5 + 0.5 * sin(TAU * mod_freq * t))
		var s: float = lp3 * 14.0 * swell
		var v: int = int(clamp(s * 32767.0, -32767.0, 32767.0))
		data.encode_s16(i * 2, v)
	var fade_n: int = int(0.15 * float(sample_rate))
	for i in fade_n:
		var blend: float = float(i) / float(fade_n)
		var idx_end: int = (n_samples - fade_n + i) * 2
		var v_end: float = float(data.decode_s16(idx_end))
		var v_start: float = float(data.decode_s16(i * 2))
		data.encode_s16(idx_end, int(lerp(v_end, v_start, blend)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = n_samples
	return stream

func _make_enemy_hum_sound() -> AudioStreamWAV:
	# Low tonal hum with a slight detuned overtone + a touch of filtered noise
	# for mechanical "whirr". Phase-aligned frequencies for seamless looping.
	var sample_rate: int = 22050
	var duration: float = 2.0
	var n_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	var f1: float = round(140.0 * duration) / duration
	var f2: float = round(213.0 * duration) / duration
	var lp1: float = 0.0
	for i in n_samples:
		var n_in: float = randf() * 2.0 - 1.0
		lp1 += (n_in - lp1) * 0.1
		var t: float = float(i) / float(sample_rate)
		var tone: float = sin(TAU * f1 * t) * 0.18 + sin(TAU * f2 * t) * 0.09
		var s: float = tone + lp1 * 0.35
		var v: int = int(clamp(s * 32767.0, -32767.0, 32767.0))
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = n_samples
	return stream

func _make_engine_sound() -> AudioStreamWAV:
	# Low-pass-filtered noise looped seamlessly via end-into-start crossfade.
	# A slow sin modulator gives the static-y noise some wind-like motion.
	var sample_rate: int = 22050
	var duration: float = 3.0
	var n_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	# Two-pole low-pass state — primed by running 500 samples of warmup
	var lp1: float = 0.0
	var lp2: float = 0.0
	var lp_a: float = 0.04
	var lp_a2: float = 0.12
	for _i in 500:
		var n: float = randf() * 2.0 - 1.0
		lp1 += (n - lp1) * lp_a
		lp2 += (lp1 - lp2) * lp_a2
	# Steady drone tones (chosen so an integer number of periods fits in the
	# loop length → seamless looping without phase jump at the splice).
	var drone1_freq: float = round(95.0 * duration) / duration
	var drone2_freq: float = round(143.0 * duration) / duration
	for i in n_samples:
		var n2: float = randf() * 2.0 - 1.0
		lp1 += (n2 - lp1) * lp_a
		lp2 += (lp1 - lp2) * lp_a2
		var t: float = float(i) / float(sample_rate)
		var drone: float = sin(TAU * drone1_freq * t) * 0.18 + sin(TAU * drone2_freq * t) * 0.09
		var s: float = lp2 * 5.0 + drone
		var v: int = int(clamp(s * 32767.0, -32767.0, 32767.0))
		data.encode_s16(i * 2, v)
	# Crossfade the last 120 ms of the buffer into the first 120 ms so the loop
	# point doesn't click.
	var fade_n: int = int(0.12 * float(sample_rate))
	for i in fade_n:
		var blend: float = float(i) / float(fade_n)
		var idx_end: int = (n_samples - fade_n + i) * 2
		var v_end: float = float(data.decode_s16(idx_end))
		var v_start: float = float(data.decode_s16(i * 2))
		var mixed: int = int(lerp(v_end, v_start, blend))
		data.encode_s16(idx_end, mixed)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = n_samples
	return stream

func _make_enemy_shot_sound() -> AudioStreamWAV:
	# Deeper "thump" — slower descending pitch, buzzy detune layer, longer tail.
	var sample_rate: int = 22050
	var duration: float = 0.24
	var n_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(n_samples * 2)
	var phase1: float = 0.0
	var phase2: float = 0.0
	for i in n_samples:
		var t: float = float(i) / float(sample_rate)
		var freq: float = lerp(560.0, 130.0, t / duration)
		phase1 += TAU * freq / float(sample_rate)
		phase2 += TAU * (freq * 1.5) / float(sample_rate)  # detuned harmonic for buzz
		var env: float = exp(-t * 6.0) * 0.6
		var s: float = (sin(phase1) * 0.7 + sin(phase2) * 0.3) * env
		var v: int = int(clamp(s * 32767.0, -32767.0, 32767.0))
		data.encode_s16(i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream

func _process(delta: float) -> void:
	# Dedicated server: only the authoritative netcode runs, nothing visual.
	if net_mode == NetMode.SERVER:
		_server_process(delta)
		return
	# Home / start screen + ship-builder: no gameplay, just the ambient world +
	# the ship turntable (the editor reuses the home framing).
	if state == STATE_HOME or state == STATE_SHIPYARD:
		AudioServer.set_bus_mute(0, true)
		_home_update(delta)
		return
	# Emotes + chat run in every in-run state (incl. ESC pause), so emote
	# billboards keep floating and the wheel/chat stay responsive.
	_update_social(delta)
	# Co-op clients keep the world live during their own menus (level-up OR the ESC
	# self-pause): the server keeps simulating and keeps the player invulnerable, so we
	# only freeze their own ship. Single-player menus fully freeze the world.
	var coop_live := net_mode == NetMode.CLIENT and (state == STATE_LEVELUP or menu_open) and state != STATE_GAMEOVER
	var local_menu := menu_open or state == STATE_LEVELUP   # this player's own ship/fire frozen
	var hard_stop := (state != STATE_PLAYING or menu_open) and not coop_live
	# Mute all audio while not actively in gameplay (menu fully freezes us; game over).
	AudioServer.set_bus_mute(0, hard_stop)
	if hard_stop:
		_update_ui_text()
		_animate_background(delta * 0.3)
		if radar != null:
			radar.queue_redraw()
		return

	run_time += delta
	if net_mode == NetMode.CLIENT:
		# Co-op client: the server owns enemies, bullets, gems, waves and damage.
		# The client only drives its own ship + firing, then renders the snapshot.
		# While a menu is open the world keeps streaming, but the player's own
		# ship/fire/lightning are frozen (and the server keeps them invulnerable).
		if not local_menu:
			_update_player(delta)
			_update_fire(delta)
			_check_lightning_strikes(delta)
		_client_net_update(delta)
	else:
		_update_player(delta)
		_update_enemies(delta)
		_update_p_bullets(delta)
		_update_e_bullets(delta)
		_update_gems(delta)
		_update_fire(delta)
		_update_spawning(delta)
		_update_wave(delta)
		_update_events(delta)
		_resolve_collisions()
		_purge_dead()
		_check_lightning_strikes(delta)
	_update_shake(delta)
	_animate_background(delta)
	_animate_ship_lights(delta)
	_animate_speedlines(delta)
	_update_muzzle_flashes(delta)
	_check_state()
	_update_ui_text()
	if radar != null:
		radar.queue_redraw()

func _input(event: InputEvent) -> void:
	# While typing in chat, ESC cancels it (handled here, before GUI/pause, so it
	# doesn't also toggle the pause menu).
	if not chat_typing:
		return
	var k := event as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_ESCAPE:
		_close_chat()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if net_mode == NetMode.SERVER:
		return
	# Enter opens the chat input during a run (incl. the ESC pause). While typing,
	# the focused LineEdit consumes Enter (text_submitted), so this only OPENS it.
	var key_ev := event as InputEventKey
	if key_ev != null and not chat_typing and key_ev.pressed and not key_ev.echo \
			and (key_ev.keycode == KEY_ENTER or key_ev.keycode == KEY_KP_ENTER) \
			and state == STATE_PLAYING:
		_open_chat()
		return
	# ESC opens/closes the self-pause + server screen. (Spacebar no longer pauses.)
	if event.is_action_pressed("pause"):
		if state == STATE_GAMEOVER:
			return
		if state == STATE_SHIPYARD:
			# ESC in the hangar = discard changes and go back to the home screen.
			_shipyard_cancel()
			return
		if settings_panel != null and settings_panel.visible:
			# ESC backs out of the settings sub-panel first.
			_close_settings()
			return
		_toggle_esc_menu()

# ============================================================
# Environment / lighting / camera
# ============================================================

func _build_environment() -> void:
	var env := Environment.new()
	# Use a very dim procedural sky so metal has something to reflect
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.025, 0.04, 0.10)
	sky_mat.sky_horizon_color = Color(0.06, 0.08, 0.18)
	sky_mat.sky_curve = 0.15
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sky_mat.ground_horizon_color = Color(0.03, 0.04, 0.08)
	sky_mat.sun_angle_max = 15.0
	sky_mat.energy_multiplier = 0.6
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	# Render a flat deep-space colour as the background so no horizon line shows.
	# The sky itself is still computed and used as reflection / ambient source.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.ambient_light_sky_contribution = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_strength = 1.15
	env.glow_bloom = 0.28
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.5
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 1.8
	env.ssao_detail = 1.2
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	# Subtle adjustments: a hint of vignette and warmer tint
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	var wenv := WorldEnvironment.new()
	wenv.environment = env
	add_child(wenv)

func _build_camera() -> void:
	cam = Camera3D.new()
	cam_base_pos = CAM_OFFSET_BASE
	cam.position = cam_base_pos
	cam.fov = 58.0
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.make_current()
	# Explicit 3D audio listener anchored to the camera — guarantees positional
	# audio uses the camera position regardless of default-listener behaviour.
	var listener := AudioListener3D.new()
	cam.add_child(listener)
	listener.make_current()

func _build_lights() -> void:
	# Very dim directional fill — cosmic ambient only, not a "sun". The real
	# lighting comes from world-objects (planets, nebulae, projectiles, gems)
	# each carrying their own OmniLight3D, so the ship is lit by what surrounds
	# it instead of a fixed sky-sun. Shadows still come from this one so the
	# ship has some shape grounding.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -30, 0)
	key.light_color = Color(0.7, 0.78, 0.95)
	key.light_energy = 0.55
	key.shadow_enabled = true
	key.shadow_bias = 0.05
	key.shadow_normal_bias = 1.2
	key.shadow_blur = 1.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key.directional_shadow_max_distance = 80.0
	add_child(key)
	# Cold deep-space fill from below — prevents pure-black shadow side.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(50, 30, 0)
	fill.light_color = Color(0.35, 0.55, 0.85)
	fill.light_energy = 0.22
	add_child(fill)

# ============================================================
# Materials
# ============================================================

func _build_materials() -> void:
	mat_player = _make_mat(COL_PLAYER, COL_PLAYER_EMIT, 2.5, 0.25, 0.3)
	mat_drone = _make_mat(COL_DRONE, COL_DRONE, 1.4, 0.45, 0.1)
	mat_shooter = _make_mat(COL_SHOOTER, COL_SHOOTER, 1.4, 0.45, 0.1)
	mat_tank = _make_mat(COL_TANK, COL_TANK, 1.1, 0.55, 0.2)
	mat_boss = _make_mat(COL_BOSS, COL_BOSS, 1.8, 0.4, 0.1)
	mat_proj = _make_mat(COL_PROJ, COL_PROJ, 2.5, 0.0, 0.0)
	mat_e_bullet = _make_mat(COL_E_BULLET, COL_E_BULLET, 2.3, 0.0, 0.0)
	mat_gem = _make_mat(COL_XP, COL_XP, 1.8, 0.3, 0.0)

func _make_mat(albedo: Color, emit: Color, emit_energy: float, rough: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = emit_energy
	m.roughness = rough
	m.metallic = metallic
	return m

# ============================================================
# World root
# ============================================================

func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	bg_root = Node3D.new()
	bg_root.name = "Background"
	add_child(bg_root)

	# (Floor plane removed — XY play plane doesn't need a horizontal floor)

	# Arena rim removed — open space, no boundaries

	# (Planet temporarily disabled for visibility debugging)

func _build_arena_rim() -> void:
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.2, 0.45, 0.7)
	rim_mat.emission_enabled = true
	rim_mat.emission = Color(0.25, 0.6, 1.0)
	rim_mat.emission_energy_multiplier = 1.4
	rim_mat.roughness = 0.5
	var hw: float = ARENA_W * 0.5
	var hh: float = ARENA_H * 0.5
	var thickness: float = 0.12
	# Top, bottom, left, right
	var bars := [
		[Vector3(0, hh, 0), Vector3(ARENA_W, thickness, thickness)],
		[Vector3(0, -hh, 0), Vector3(ARENA_W, thickness, thickness)],
		[Vector3(-hw, 0, 0), Vector3(thickness, ARENA_H, thickness)],
		[Vector3(hw, 0, 0), Vector3(thickness, ARENA_H, thickness)],
	]
	for b in bars:
		var bm := BoxMesh.new()
		bm.size = b[1]
		bm.material = rim_mat
		var inst := MeshInstance3D.new()
		inst.mesh = bm
		inst.position = b[0]
		world.add_child(inst)

func _build_starfield() -> void:
	# Many small far stars with parallax depth
	var star_mat := StandardMaterial3D.new()
	star_mat.albedo_color = Color(1, 1, 1)
	star_mat.emission_enabled = true
	star_mat.emission = Color(1, 1, 1)
	star_mat.emission_energy_multiplier = 3.0
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var orange_mat := StandardMaterial3D.new()
	orange_mat.albedo_color = Color(1, 0.7, 0.4)
	orange_mat.emission_enabled = true
	orange_mat.emission = Color(1, 0.7, 0.4)
	orange_mat.emission_energy_multiplier = 2.5
	orange_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for i in 220:
		var sm := SphereMesh.new()
		var r: float = randf_range(0.04, 0.14)
		sm.radius = r
		sm.height = r * 2
		sm.material = star_mat if randf() < 0.85 else orange_mat
		var inst := MeshInstance3D.new()
		inst.mesh = sm
		inst.position = Vector3(
			randf_range(-50, 50),
			randf_range(-30, 30),
			randf_range(-60, -10)
		)
		bg_root.add_child(inst)
		stars.append(inst)

func _build_distant_objects() -> void:
	# Background planets at varying sizes / distances
	for i in 7:
		_spawn_random_planet()
	# A couple distant background nebulae behind the action plane
	for i in 2:
		_spawn_random_nebula()
	# Flyable nebulae in the XY play plane. One close to start so the player
	# encounters one within a few seconds, plus a second further out.
	_spawn_flyable_nebula(true)
	_spawn_flyable_nebula(false)
	# Asteroid clusters
	for i in 6:
		_spawn_random_asteroid_cluster()

const PLANET_SHADER_CODE := """
shader_type spatial;

uniform sampler2D noise_a : hint_default_white;
uniform sampler2D noise_b : hint_default_white;
uniform vec4 sea_col : source_color;
uniform vec4 land_col : source_color;
uniform vec4 ice_col : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform vec4 atmo_col : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform vec4 cloud_col : source_color = vec4(0.96, 0.96, 0.98, 1.0);
uniform float land_thresh : hint_range(0.0, 1.0) = 0.5;
uniform float ice_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_thresh : hint_range(0.0, 1.0) = 0.6;
uniform float atmo_strength : hint_range(0.0, 3.0) = 1.0;
uniform float emit_boost : hint_range(0.0, 1.0) = 0.3;
uniform float gas_banding : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_speed = 0.005;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.88;

void fragment() {
	vec2 uv = UV;
	// Gas giants: stretch noise into horizontal bands; rocky/ocean keep normal UVs
	vec2 surf_uv = mix(uv, vec2(uv.x * 0.5, uv.y * 6.0), gas_banding);
	float n_a = texture(noise_a, surf_uv).r;
	float n_b = texture(noise_b, surf_uv * 2.7).r;
	float n_surf = mix(n_a, n_b, 0.25);

	// Continents / seas
	float land = smoothstep(land_thresh - 0.05, land_thresh + 0.05, n_surf);
	vec3 base = mix(sea_col.rgb, land_col.rgb, land);

	// Polar ice with noisy edge so caps aren't perfect circles
	float lat = abs(uv.y - 0.5) * 2.0;
	float ice = smoothstep(0.78, 0.96, lat + (n_b - 0.5) * 0.18) * ice_strength;
	base = mix(base, ice_col.rgb, ice);

	// Cloud layer — drifts around equator independently of surface
	vec2 cloud_uv = uv + vec2(TIME * cloud_speed, 0.0);
	float n_cl1 = texture(noise_b, cloud_uv * 1.5).r;
	float n_cl2 = texture(noise_a, cloud_uv * 3.1 + vec2(0.31, 0.17)).r;
	float cl_n = (n_cl1 + n_cl2) * 0.5;
	float cloud = smoothstep(cloud_thresh, cloud_thresh + 0.18, cl_n) * cloud_strength;
	base = mix(base, cloud_col.rgb, cloud);

	// Atmospheric rim glow via Fresnel against view-space normal
	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	rim = pow(rim, 2.6);
	vec3 atmo = atmo_col.rgb * rim * atmo_strength;

	ALBEDO = base;
	EMISSION = base * emit_boost + atmo;
	METALLIC = 0.0;
	ROUGHNESS = roughness_val;
}
"""

func _make_planet_noise(freq: float, octaves: int, simplex: bool) -> ImageTexture:
	# Sync noise generation — NoiseTexture2D is async and the shader would sample
	# the default white value until the texture finished, leaving planets uniform.
	var ns := FastNoiseLite.new()
	ns.noise_type = FastNoiseLite.TYPE_SIMPLEX if simplex else FastNoiseLite.TYPE_PERLIN
	ns.seed = randi()
	ns.frequency = freq
	ns.fractal_octaves = octaves
	ns.fractal_lacunarity = 2.1
	ns.fractal_gain = 0.55
	var img: Image = ns.get_seamless_image(512, 256, false, false, 0.1)
	return ImageTexture.create_from_image(img)

func _make_planet_material(sea_col: Color, land_col: Color, atmo_col: Color,
		ice_strength: float, cloud_strength: float, gas_banding: float,
		roughness_val: float, emit_boost: float, atmo_strength: float,
		surface_freq: float = 0.012, detail_freq: float = 0.03) -> ShaderMaterial:
	var tex_a: ImageTexture = _make_planet_noise(surface_freq, 5, false)
	var tex_b: ImageTexture = _make_planet_noise(detail_freq, 4, true)
	var shader := Shader.new()
	shader.code = PLANET_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("noise_a", tex_a)
	mat.set_shader_parameter("noise_b", tex_b)
	mat.set_shader_parameter("sea_col", sea_col)
	mat.set_shader_parameter("land_col", land_col)
	mat.set_shader_parameter("atmo_col", atmo_col)
	mat.set_shader_parameter("land_thresh", randf_range(0.45, 0.58))
	mat.set_shader_parameter("ice_strength", ice_strength)
	mat.set_shader_parameter("cloud_strength", cloud_strength)
	mat.set_shader_parameter("cloud_thresh", randf_range(0.55, 0.68))
	mat.set_shader_parameter("atmo_strength", atmo_strength)
	mat.set_shader_parameter("emit_boost", emit_boost)
	mat.set_shader_parameter("gas_banding", gas_banding)
	mat.set_shader_parameter("cloud_speed", randf_range(0.003, 0.008))
	mat.set_shader_parameter("roughness_val", roughness_val)
	return mat

func _add_moon(parent: Node3D, orbit_radius: float, moon_radius: float) -> void:
	# Small cratered companion that orbits the parent planet (parent rotation drives orbit).
	var hue: float = randf() * 0.1 + 0.06  # grey-brown tones
	var sea_col: Color = Color.from_hsv(hue, 0.25, randf_range(0.35, 0.55))
	var land_col: Color = sea_col.darkened(randf_range(0.2, 0.45))
	var atmo_col: Color = Color.from_hsv(0.07, 0.3, 0.7)
	var mat: ShaderMaterial = _make_planet_material(
		sea_col, land_col, atmo_col,
		0.0, 0.0, 0.0,
		0.98, 0.25, 0.15,
		0.04, 0.09)
	var moon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = moon_radius
	sm.height = moon_radius * 2
	sm.radial_segments = 28
	sm.rings = 14
	sm.material = mat
	moon.mesh = sm
	var ang: float = randf() * TAU
	var pitch: float = randf_range(-0.25, 0.25)
	var op: Vector3 = Vector3(cos(ang) * cos(pitch), sin(pitch), sin(ang) * cos(pitch)) * orbit_radius
	moon.position = op
	parent.add_child(moon)

func _spawn_random_planet() -> void:
	# Procedural shader-driven planet — one opaque sphere, no transparency overlap.
	# Size class (small moon / medium / gas giant) drives radius, distance and biome bias.
	var size_roll: float = randf()
	var radius: float
	var dist_min: float
	var dist_max: float
	var size_class: String
	if size_roll < 0.32:
		# Small moon-like
		radius = randf_range(1.6, 3.0)
		dist_min = 80.0
		dist_max = 180.0
		size_class = "small"
	elif size_roll < 0.80:
		# Standard planet
		radius = randf_range(4.0, 7.5)
		dist_min = 140.0
		dist_max = 260.0
		size_class = "medium"
	else:
		# Gas giant or large rocky world
		radius = randf_range(9.5, 15.0)
		dist_min = 220.0
		dist_max = 360.0
		size_class = "large"

	var hue: float = randf()
	# Biome distribution biased by size: small → rocky/volcanic, large → gas giant
	var biome_roll: float = randf()
	match size_class:
		"small":
			# 0..0.28 rocky, 0.82..1.0 volcanic — skip ocean / gas
			biome_roll = randf_range(0.0, 0.28) if randf() < 0.7 else randf_range(0.82, 1.0)
		"large":
			# Mostly gas giants (0.58..0.82), occasionally ocean
			biome_roll = randf_range(0.58, 0.82) if randf() < 0.75 else randf_range(0.28, 0.58)
		_:
			pass

	var sea_col: Color
	var land_col: Color
	var atmo_col: Color
	var ice_strength: float = 0.0
	var cloud_strength: float = 0.0
	var gas_banding: float = 0.0
	var roughness_val: float = 0.88
	var emit_boost: float = 0.32

	if biome_roll < 0.28:
		# Rocky / desert — Mars-like
		sea_col = Color.from_hsv(0.05 + randf() * 0.05, 0.55, 0.55)
		land_col = sea_col.darkened(0.35)
		atmo_col = Color.from_hsv(0.07, 0.4, 1.0)
		roughness_val = 0.95
	elif biome_roll < 0.58:
		# Ocean / earth-like
		sea_col = Color.from_hsv(0.58 + randf() * 0.06, 0.78, 0.42)
		land_col = Color.from_hsv(0.27 + randf() * 0.08, 0.6, 0.5)
		atmo_col = Color.from_hsv(0.58, 0.55, 1.0)
		ice_strength = 1.0
		cloud_strength = 0.7
	elif biome_roll < 0.82:
		# Gas giant — banded
		sea_col = Color.from_hsv(hue, 0.55, 0.7)
		land_col = Color.from_hsv(fmod(hue + 0.06, 1.0), 0.7, 0.55)
		atmo_col = Color.from_hsv(fmod(hue + 0.03, 1.0), 0.4, 1.0)
		gas_banding = 1.0
		cloud_strength = 0.45
		emit_boost = 0.38
	else:
		# Volcanic
		sea_col = Color.from_hsv(0.02 + randf() * 0.03, 0.85, 0.38)
		land_col = Color.from_hsv(0.07 + randf() * 0.03, 0.95, 0.85)
		atmo_col = Color.from_hsv(0.04, 0.7, 1.0)
		roughness_val = 0.7
		emit_boost = 0.45

	var planet := Node3D.new()
	planet.position = _random_distant_pos(dist_min, dist_max)
	# Random axial tilt and orientation so each planet looks unique
	planet.rotation = Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.3, 0.3))

	var mat: ShaderMaterial = _make_planet_material(
		sea_col, land_col, atmo_col,
		ice_strength, cloud_strength, gas_banding,
		roughness_val, emit_boost, randf_range(0.85, 1.4))

	var surface := MeshInstance3D.new()
	var ssm := SphereMesh.new()
	ssm.radius = radius
	ssm.height = radius * 2
	ssm.radial_segments = 64
	ssm.rings = 32
	ssm.material = mat
	surface.mesh = ssm
	planet.add_child(surface)

	# Planet acts as a light source — its surface colour bleeds onto nearby
	# objects (most importantly the ship when it gets close). Range scales with
	# planet radius so bigger planets light a wider area.
	var planet_light := OmniLight3D.new()
	var light_col: Color = sea_col.lerp(land_col, 0.5)
	# Boost brightness slightly so it's visible against deep-space ambient
	light_col = light_col.lerp(Color(1, 1, 1), 0.3)
	planet_light.light_color = light_col
	planet_light.light_energy = 1.4 + radius * 0.08
	planet_light.omni_range = radius * 8.0 + 30.0
	planet_light.omni_attenuation = 1.4
	planet.add_child(planet_light)

	# Ring system — gas giants likely, large rocky / ocean worlds occasionally
	var ring_chance: float = 0.0
	if gas_banding > 0.5:
		ring_chance = 0.75
	elif size_class == "large":
		ring_chance = 0.25
	if randf() < ring_chance:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = radius * 1.55
		tm.outer_radius = radius * randf_range(2.2, 2.7)
		tm.ring_segments = 64
		tm.rings = 6
		var rmat := StandardMaterial3D.new()
		var ring_color: Color = Color.from_hsv(fmod(hue + 0.18, 1.0), 0.35, 0.78)
		rmat.albedo_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.7)
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.emission_enabled = true
		rmat.emission = ring_color
		rmat.emission_energy_multiplier = 0.25
		rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		tm.material = rmat
		ring.mesh = tm
		ring.rotation_degrees = Vector3(randf_range(-25, 25), randf_range(-40, 40), randf_range(-15, 15))
		planet.add_child(ring)

	# Moons orbit medium / large planets — children of the planet root inherit its
	# slow rotation, so their position swings around the parent (orbital motion).
	var moon_chance: float = 0.0
	var max_moons: int = 0
	if size_class == "large":
		moon_chance = 0.85
		max_moons = 3
	elif size_class == "medium":
		moon_chance = 0.35
		max_moons = 2
	if randf() < moon_chance:
		var moon_count: int = randi_range(1, max_moons)
		for i in moon_count:
			var moon_r: float = radius * randf_range(0.12, 0.22)
			var orbit_r: float = radius * randf_range(1.6, 2.6) + moon_r
			_add_moon(planet, orbit_r, moon_r)

	var wrap_r: float = 340.0
	if size_class == "small":
		wrap_r = 240.0
	elif size_class == "large":
		wrap_r = 420.0
	bg_root.add_child(planet)
	distant_objects.append({
		"node": planet,
		"wrap_radius": wrap_r,
		"rot_axis": Vector3(randf_range(-0.2, 0.2), 1.0, randf_range(-0.2, 0.2)).normalized(),
		"rot_speed": randf_range(0.03, 0.12),
	})

const NEBULA_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

uniform sampler2D noise_a : hint_default_white;
uniform sampler2D noise_b : hint_default_white;
uniform vec4 color_outer : source_color;
uniform vec4 color_inner : source_color;
uniform vec4 lightning_col : source_color = vec4(0.85, 0.92, 1.35, 1.0);
uniform float density : hint_range(0.0, 4.0) = 1.4;
uniform float drift_speed = 0.008;
uniform float displacement = 3.0;
uniform float swirl_strength : hint_range(0.0, 0.6) = 0.18;
uniform float lightning_strength : hint_range(0.0, 4.0) = 0.0;
uniform float lightning_rate = 0.7;
uniform float pulse_strength : hint_range(0.0, 0.4) = 0.15;
uniform float pulse_rate = 0.13;

float h11(float p) { return fract(sin(p * 41.3) * 4321.0); }

void vertex() {
	// Vertex displacement: irregular silhouette, plus a slow breathing pulse so
	// the whole shape is gently flexing over time.
	float n = texture(noise_a, UV).r;
	float breathe = sin(TIME * 0.21) * 0.05;
	VERTEX += NORMAL * (n - 0.5 + breathe) * displacement;
}

void fragment() {
	vec2 uv = UV;

	// Domain warp — sample a slow noise field and use it to perturb UV before
	// sampling the gas noise. Produces swirling, billowing motion instead of
	// flat scrolling.
	vec2 warp_uv = uv * 0.7 + vec2(TIME * drift_speed * 0.4, -TIME * drift_speed * 0.25);
	float wx = texture(noise_a, warp_uv).r - 0.5;
	float wy = texture(noise_a, warp_uv + vec2(0.37, 0.21)).r - 0.5;
	vec2 warp = vec2(wx, wy) * swirl_strength;

	// Two gas-noise layers — different scales and drift directions, both warped
	vec2 uv1 = uv + warp + vec2(TIME * drift_speed, TIME * drift_speed * 0.3);
	vec2 uv2 = uv * 2.3 + warp * 1.6 + vec2(-TIME * drift_speed * 0.7, TIME * drift_speed * 0.5);
	float n1 = texture(noise_a, uv1).r;
	float n2 = texture(noise_b, uv2).r;
	float n = mix(n1, n2, 0.45);
	n = pow(n, 1.8);

	// Slow density pulse — nebula breathes
	n *= 1.0 + pulse_strength * sin(TIME * pulse_rate);

	// Soft edge — never fully fades so inside-view still shows gas in peripheral directions
	float edge_dot = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = mix(0.55, 1.0, edge_dot);

	float hot = smoothstep(0.45, 0.85, n);
	vec3 col = mix(color_outer.rgb, color_inner.rgb, hot);
	vec3 emit = col * (0.6 + hot * 1.8);
	float a = n * edge * density;

	// Lightning bursts — periodic flashes at random positions inside dense gas
	if (lightning_strength > 0.0) {
		float lt = TIME * lightning_rate;
		float bolt_id = floor(lt);
		float ph = fract(lt);
		// Sharp flash that ramps up fast and decays exponentially
		float flash = exp(-ph * 9.0) * smoothstep(0.0, 0.04, ph);
		// Random bolt position per cycle
		vec2 bolt_uv = vec2(h11(bolt_id * 2.71), h11(bolt_id * 7.13));
		vec2 d = uv - bolt_uv;
		float local = exp(-dot(d, d) * 70.0);
		// High-freq noise filaments give branchy lightning shape
		float fil_n = texture(noise_b, uv * 8.0 + vec2(h11(bolt_id), h11(bolt_id + 0.5))).r;
		float fil = smoothstep(0.76, 0.93, fil_n);
		float bolt = (local + local * fil * 1.8) * flash * lightning_strength;
		// Only fire inside dense gas regions
		bolt *= smoothstep(0.25, 0.6, n);
		emit += lightning_col.rgb * bolt * 3.0;
		a += bolt * 0.45;
	}

	ALBEDO = emit;
	EMISSION = emit * 0.35;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

func _spawn_random_nebula() -> void:
	# Volumetric-feeling gas cloud: shader-driven wisps + irregular silhouette + bright cores.
	var radius: float = randf_range(12.0, 22.0)
	var hue: float = randf()
	var color_outer: Color = Color.from_hsv(hue, 0.65, 0.5)
	var color_inner: Color = Color.from_hsv(fmod(hue + 0.08, 1.0), 0.85, 1.0)

	var nebula := Node3D.new()
	nebula.position = _random_distant_pos(80.0, 150.0)
	nebula.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

	var tex_a: ImageTexture = _make_planet_noise(0.018, 5, false)
	var tex_b: ImageTexture = _make_planet_noise(0.04, 4, true)

	var shader := Shader.new()
	shader.code = NEBULA_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("noise_a", tex_a)
	mat.set_shader_parameter("noise_b", tex_b)
	mat.set_shader_parameter("color_outer", color_outer)
	mat.set_shader_parameter("color_inner", color_inner)
	mat.set_shader_parameter("density", randf_range(1.2, 2.0))
	mat.set_shader_parameter("drift_speed", randf_range(0.005, 0.014))
	mat.set_shader_parameter("displacement", radius * randf_range(0.28, 0.5))
	mat.set_shader_parameter("swirl_strength", randf_range(0.12, 0.28))
	mat.set_shader_parameter("pulse_strength", randf_range(0.08, 0.22))
	mat.set_shader_parameter("pulse_rate", randf_range(0.08, 0.20))
	# 35% chance of being a storm nebula with lightning
	if randf() < 0.35:
		mat.set_shader_parameter("lightning_strength", randf_range(0.5, 1.1))
		mat.set_shader_parameter("lightning_rate", randf_range(0.4, 1.1))

	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2
	sm.radial_segments = 48
	sm.rings = 24
	sm.material = mat
	shell.mesh = sm
	nebula.add_child(shell)

	# Nebula casts a soft coloured glow on nearby ships — uses the inner gas tint.
	var neb_light := OmniLight3D.new()
	neb_light.light_color = color_inner
	neb_light.light_energy = 1.1
	neb_light.omni_range = radius * 4.5
	neb_light.omni_attenuation = 1.5
	nebula.add_child(neb_light)

	# Bright stellar-nursery cores embedded in the gas
	var spot_count: int = randi_range(2, 5)
	for i in spot_count:
		var spot := MeshInstance3D.new()
		var ssm := SphereMesh.new()
		var sr: float = randf_range(0.5, 1.2)
		ssm.radius = sr
		ssm.height = sr * 2
		ssm.radial_segments = 14
		ssm.rings = 8
		var smat := StandardMaterial3D.new()
		var sc: Color = color_inner.lerp(Color(1, 1, 1), randf_range(0.3, 0.65))
		smat.albedo_color = sc
		smat.emission_enabled = true
		smat.emission = sc
		smat.emission_energy_multiplier = randf_range(2.5, 4.5)
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ssm.material = smat
		spot.mesh = ssm
		var dir: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		spot.position = dir * radius * randf_range(0.15, 0.55)
		nebula.add_child(spot)

	bg_root.add_child(nebula)
	distant_objects.append({
		"node": nebula,
		"wrap_radius": 250.0,
		"rot_axis": Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)).normalized(),
		"rot_speed": randf_range(0.005, 0.02),
	})

func _spawn_flyable_nebula(near_start: bool = false) -> void:
	# Large nebula placed in the XY play plane so the player can fly through it.
	# Alpha-blended so it acts like a real cloud — visible from outside AND from
	# inside. Non-uniform scale produces flat / elongated / spherical variants.
	var radius: float = randf_range(28.0, 55.0)
	var hue: float = randf()
	var color_outer: Color = Color.from_hsv(hue, 0.55, 0.4)
	var color_inner: Color = Color.from_hsv(fmod(hue + 0.08, 1.0), 0.8, 0.95)

	var nebula := Node3D.new()
	var ang: float = randf() * TAU
	var dist: float
	if near_start:
		dist = randf_range(28.0, 45.0)
	else:
		dist = randf_range(60.0, 140.0)
	nebula.position = Vector3(cos(ang) * dist, sin(ang) * dist, randf_range(-4.0, 4.0))
	nebula.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

	# Shape variation: flat disc / elongated cigar / spherical
	var shape_roll: float = randf()
	var sx: float = 1.0
	var sy: float = 1.0
	var sz: float = 1.0
	if shape_roll < 0.35:
		# Flat disc-shaped — galactic-plane look
		sy = randf_range(0.22, 0.45)
		sx = randf_range(0.9, 1.3)
		sz = randf_range(0.9, 1.3)
	elif shape_roll < 0.65:
		# Elongated along a random axis
		var ax: int = randi() % 3
		match ax:
			0:
				sx = randf_range(1.4, 2.1)
				sy = randf_range(0.5, 0.8)
				sz = randf_range(0.6, 0.9)
			1:
				sy = randf_range(1.4, 2.1)
				sx = randf_range(0.5, 0.8)
				sz = randf_range(0.6, 0.9)
			_:
				sz = randf_range(1.4, 2.1)
				sx = randf_range(0.6, 0.9)
				sy = randf_range(0.5, 0.8)
	# else: roughly spherical (default 1,1,1)
	nebula.scale = Vector3(sx, sy, sz)

	var tex_a: ImageTexture = _make_planet_noise(0.014, 5, false)
	var tex_b: ImageTexture = _make_planet_noise(0.035, 4, true)

	var shader := Shader.new()
	shader.code = NEBULA_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("noise_a", tex_a)
	mat.set_shader_parameter("noise_b", tex_b)
	mat.set_shader_parameter("color_outer", color_outer)
	mat.set_shader_parameter("color_inner", color_inner)
	mat.set_shader_parameter("density", randf_range(0.85, 1.5))
	mat.set_shader_parameter("drift_speed", randf_range(0.004, 0.012))
	mat.set_shader_parameter("displacement", radius * randf_range(0.3, 0.55))
	mat.set_shader_parameter("swirl_strength", randf_range(0.18, 0.38))
	mat.set_shader_parameter("pulse_strength", randf_range(0.12, 0.28))
	mat.set_shader_parameter("pulse_rate", randf_range(0.10, 0.25))
	# 65% chance for flyable nebulae to have lightning storms. Storm nebulae are
	# also registered for collision damage — flying through them can hurt.
	var is_storm: bool = randf() < 0.65
	if is_storm:
		mat.set_shader_parameter("lightning_strength", randf_range(0.7, 1.4))
		mat.set_shader_parameter("lightning_rate", randf_range(0.5, 1.4))

	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2
	sm.radial_segments = 56
	sm.rings = 28
	sm.material = mat
	shell.mesh = sm
	nebula.add_child(shell)

	# Flyable nebulae are large and the player flies through them — give them
	# a stronger interior glow that lights up the ship while inside the cloud.
	var fneb_light := OmniLight3D.new()
	fneb_light.light_color = color_inner
	fneb_light.light_energy = 1.6
	fneb_light.omni_range = radius * 2.2
	fneb_light.omni_attenuation = 1.3
	nebula.add_child(fneb_light)

	# Embedded stellar nursery cores
	var spot_count: int = randi_range(3, 7)
	for i in spot_count:
		var spot := MeshInstance3D.new()
		var ssm := SphereMesh.new()
		var sr: float = randf_range(0.5, 1.4)
		ssm.radius = sr
		ssm.height = sr * 2
		ssm.radial_segments = 14
		ssm.rings = 8
		var smat := StandardMaterial3D.new()
		var sc: Color = color_inner.lerp(Color(1, 1, 1), randf_range(0.35, 0.7))
		smat.albedo_color = sc
		smat.emission_enabled = true
		smat.emission = sc
		smat.emission_energy_multiplier = randf_range(3.0, 5.0)
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ssm.material = smat
		spot.mesh = ssm
		var dir: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		spot.position = dir * radius * randf_range(0.15, 0.6)
		nebula.add_child(spot)

	bg_root.add_child(nebula)
	distant_objects.append({
		"node": nebula,
		"wrap_radius": 180.0,
		"rot_axis": Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.3, 0.3)).normalized(),
		"rot_speed": randf_range(0.003, 0.012),
	})
	if is_storm:
		storm_nebulae.append({
			"node": nebula,
			"radius": radius,
			"damage": randi_range(6, 12),
			"strike_timer": randf_range(2.0, 4.0),
			"interval_min": 1.8,
			"interval_max": 4.5,
		})
		# 3D positional thunder rumble — louder as the player approaches the nebula
		if thunder_stream != null:
			var ap := AudioStreamPlayer3D.new()
			ap.stream = thunder_stream
			ap.volume_db = -18.0
			ap.unit_size = radius * 0.7
			ap.max_distance = radius * 5.0
			ap.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			ap.pitch_scale = randf_range(0.85, 1.1)
			nebula.add_child(ap)
			ap.play()

func _spawn_random_asteroid_cluster() -> void:
	var cluster := Node3D.new()
	cluster.position = _random_distant_pos(30.0, 110.0)
	var rock_color: Color = Color(randf_range(0.25, 0.45), randf_range(0.22, 0.38), randf_range(0.2, 0.35))
	var mat := _make_proc_hull_mat(rock_color)
	mat.metallic = 0.15
	mat.roughness = 0.9
	mat.emission_energy_multiplier = 0.04
	var count: int = randi_range(6, 14)
	for i in count:
		var a := MeshInstance3D.new()
		var pm := PrismMesh.new()
		var s: float = randf_range(0.4, 1.6)
		pm.size = Vector3(s, s * randf_range(0.7, 1.3), s * randf_range(0.8, 1.2))
		pm.material = mat
		a.mesh = pm
		a.position = Vector3(randf_range(-5, 5), randf_range(-3, 3), randf_range(-5, 5))
		a.rotation_degrees = Vector3(randf_range(0, 360), randf_range(0, 360), randf_range(0, 360))
		cluster.add_child(a)
	bg_root.add_child(cluster)
	distant_objects.append({
		"node": cluster,
		"wrap_radius": 180.0,
		"rot_axis": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(),
		"rot_speed": randf_range(0.02, 0.1),
	})

func _random_distant_pos(min_dist: float, max_dist: float) -> Vector3:
	# Position in a 3D shell with strong negative-Z bias (behind/below the action plane)
	var ang: float = randf() * TAU
	var pitch: float = randf_range(-0.4, 0.4)
	var dist: float = randf_range(min_dist, max_dist)
	var dir: Vector3 = Vector3(cos(ang) * cos(pitch), sin(pitch) * 0.5, sin(ang) * cos(pitch))
	return Vector3(dir.x * dist, dir.y * dist, -abs(dir.z * dist) - 40.0)

# ============================================================
# Player visual
# ============================================================

func _build_player() -> void:
	# F-22 / Starfury inspired fighter-jet design adapted as a space craft.
	# Airplane frame: +X = forward, +Y = up, ±Z = wings. Coordinates kept within
	# the same envelope as the previous ship so upgrade-visual functions still
	# fit (guns on wings ±Z, sensors on top +Y, pierce-spike at nose +X, etc.).
	p_node = Node3D.new()
	p_node.position = p_pos
	world.add_child(p_node)
	p_node.scale = Vector3.ONE * SHIP_SCALE_BASE * u_range_mult

	# Tilted child node — all ship meshes + upgrade attachments live here.
	# +90° around X converts the "airplane" build (wings in ±Z) into top-down
	# (wings in ±Y after yaw), so yaw rotates everything correctly.
	ship_render = Node3D.new()
	ship_render.rotation_degrees = Vector3(90, 0, 0)
	p_node.add_child(ship_render)
	# (Everything else attaches to ship_render, not p_node.)
	_assemble_ship_body()

# Unshaded emissive material for an engine plasma glow (brightness animated by
# _animate_ship_lights). Shared shape for the port/starboard engine mats.
func _make_engine_glow_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 5.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

# Builds all ship meshes + lights into the member `ship_render` and registers
# pulse-light / engine / boost materials on member vars. Split out of
# _build_player so a standalone copy can be made for remote co-op players via
# _build_ship_visual() without duplicating the ~650-line geometry.
func _assemble_ship_body() -> void:
	# Resolve the cosmetic palette from the current ship_design. The four base
	# colours (hull / accent / glow / engine) drive every painted material below;
	# the "Tarnung" palette (index 0) reproduces the original stealth-fighter look.
	var _pal_idx: int = clampi(int(ship_design.get("palette", 0)), 0, SHIP_PALETTES.size() - 1)
	var pal: Dictionary = SHIP_PALETTES[_pal_idx]
	var pal_hull: Color = pal["hull"]
	var pal_accent: Color = pal["accent"]
	var pal_glow: Color = pal["glow"]
	var pal_engine: Color = pal["engine"]
	# LED accent: "auto" follows the palette glow; a named colour overrides the
	# glowing edge strips + cockpit console (nav-tip lights keep red/green identity).
	var led_key: String = str(ship_design.get("leds", "auto"))
	var led_col: Color = pal_glow if led_key == "auto" else SHIP_LED_COLORS.get(led_key, pal_glow)

	# ===== Materials =====
	# Stealth-paint hull — desaturated slate-blue, clearcoat over metallic
	# base, mimics F-22 RAM coating. Emission stays low so external lights
	# (planets, projectiles) drive the look.
	var mat_hull := StandardMaterial3D.new()
	mat_hull.albedo_color = pal_hull
	mat_hull.metallic = 0.5
	mat_hull.roughness = 0.32
	mat_hull.metallic_specular = 0.55
	mat_hull.emission_enabled = true
	mat_hull.emission = pal_hull * 0.45
	mat_hull.emission_energy_multiplier = 0.10
	mat_hull.rim_enabled = true
	mat_hull.rim = 0.6
	mat_hull.rim_tint = 0.4
	mat_hull.clearcoat_enabled = true
	mat_hull.clearcoat = 0.45
	mat_hull.clearcoat_roughness = 0.18

	# Accent panel — lighter steel-blue, used for spine, vertical-stab edges
	var mat_accent := StandardMaterial3D.new()
	mat_accent.albedo_color = pal_accent
	mat_accent.metallic = 0.85
	mat_accent.roughness = 0.24
	mat_accent.emission_enabled = true
	mat_accent.emission = pal_accent * 0.5
	mat_accent.emission_energy_multiplier = 0.22
	mat_accent.rim_enabled = true
	mat_accent.rim = 0.45
	mat_accent.clearcoat_enabled = true
	mat_accent.clearcoat = 0.5
	mat_accent.clearcoat_roughness = 0.15

	# Very dark — armor edges, gun mounts, intake interiors, engine bay
	var mat_dark := StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.04, 0.05, 0.07)
	mat_dark.metallic = 0.55
	mat_dark.roughness = 0.5
	mat_dark.metallic_specular = 0.4

	# Intake interior — pitch-black with deep red glow ("compressor blade glow")
	var mat_intake := StandardMaterial3D.new()
	mat_intake.albedo_color = Color(0.02, 0.02, 0.03)
	mat_intake.metallic = 0.2
	mat_intake.roughness = 0.85
	mat_intake.emission_enabled = true
	mat_intake.emission = Color(1.0, 0.45, 0.25)
	mat_intake.emission_energy_multiplier = 1.4

	# Cockpit glass — high-reflectivity tear-drop canopy with blue interior tint
	var mat_glass := StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.02, 0.04, 0.10)
	mat_glass.metallic = 1.0
	mat_glass.roughness = 0.03
	mat_glass.emission_enabled = true
	mat_glass.emission = Color(0.20, 0.55, 0.95)
	mat_glass.emission_energy_multiplier = 0.5
	mat_glass.rim_enabled = true
	mat_glass.rim = 0.85
	mat_glass.rim_tint = 0.7
	mat_glass.clearcoat_enabled = true
	mat_glass.clearcoat = 1.0
	mat_glass.clearcoat_roughness = 0.02

	# Thin engraved panel-seam material
	var mat_panel_line := StandardMaterial3D.new()
	mat_panel_line.albedo_color = Color(0.015, 0.02, 0.03)
	mat_panel_line.metallic = 0.2
	mat_panel_line.roughness = 0.8

	# Glowing accent strip — wing leading edges, intake lips, vstab edges, seams.
	# Driven by the LED accent colour (defaults to the palette glow).
	var mat_panel_glow := StandardMaterial3D.new()
	mat_panel_glow.albedo_color = led_col.lightened(0.3)
	mat_panel_glow.emission_enabled = true
	mat_panel_glow.emission = led_col
	mat_panel_glow.emission_energy_multiplier = 2.6
	mat_panel_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# ============================================================
	#                  FUSELAGE (centerline body)
	# ============================================================
	# Sharp, faceted fighter body: flat box for the bulk volume, then a top
	# chine (PrismMesh ridge) and bottom keel chine to give the diamond-shaped
	# cross-section silhouette without the roundness of a cylinder.
	# Coordinate envelope (compact): -0.95 (engines) to +1.0 (nose tip).

	# Main body: flat box, slightly wider in Z than tall in Y
	var body := MeshInstance3D.new()
	var bodym := BoxMesh.new()
	bodym.size = Vector3(0.75, 0.16, 0.48); bodym.material = mat_hull
	body.mesh = bodym
	body.position = Vector3(-0.05, -0.02, 0)
	ship_render.add_child(body)

	# Top chine — sharp triangular ridge running along the spine (point up)
	var chine_top := MeshInstance3D.new()
	var ctm := PrismMesh.new()
	# Prism: size.x = base width, size.y = ridge height, size.z = length (extruded)
	ctm.size = Vector3(0.46, 0.06, 0.70); ctm.material = mat_hull
	chine_top.mesh = ctm
	# Default prism point is +Y. Default length axis is Z. Rotate around Y by 90°
	# so the length runs along ship +X instead of +Z.
	chine_top.rotation_degrees = Vector3(0, 90, 0)
	chine_top.position = Vector3(-0.05, 0.08, 0)
	ship_render.add_child(chine_top)

	# Bottom keel chine — mirror prism, point down
	var chine_bot := MeshInstance3D.new()
	var cbm := PrismMesh.new()
	cbm.size = Vector3(0.40, 0.05, 0.70); cbm.material = mat_dark
	chine_bot.mesh = cbm
	chine_bot.rotation_degrees = Vector3(180, 90, 0)  # flipped to point -Y
	chine_bot.position = Vector3(-0.05, -0.13, 0)
	ship_render.add_child(chine_bot)

	# Forward section — narrower flat box bridging body to nose
	var fwd := MeshInstance3D.new()
	var fwdm := BoxMesh.new()
	fwdm.size = Vector3(0.22, 0.14, 0.32); fwdm.material = mat_hull
	fwd.mesh = fwdm
	fwd.position = Vector3(0.43, -0.01, 0)
	ship_render.add_child(fwd)

	# Nose — design-driven (ship_design.nose). "pointed" = sharp prism + pitot,
	# "blade" = longer/thinner spike + pitot, "blunt" = stubby capped box, no pitot.
	var nose_kind: String = str(ship_design.get("nose", "pointed"))
	var nose := MeshInstance3D.new()
	var nose_has_pitot: bool = true
	var pitot_x: float = 0.91
	var pitot_len: float = 0.14
	if nose_kind == "blunt":
		var nbm := BoxMesh.new()
		nbm.size = Vector3(0.18, 0.15, 0.22); nbm.material = mat_hull
		nose.mesh = nbm
		nose.position = Vector3(0.60, 0.0, 0)
		nose_has_pitot = false
	else:
		var npm := PrismMesh.new()
		if nose_kind == "blade":
			npm.size = Vector3(0.15, 0.46, 0.09)
			nose.position = Vector3(0.72, 0, 0)
			pitot_x = 1.02; pitot_len = 0.20
		else:  # pointed (default)
			npm.size = Vector3(0.20, 0.30, 0.13)
			nose.position = Vector3(0.69, 0, 0)
		npm.material = mat_hull
		nose.mesh = npm
		# Lay prism flat with its point along +X (Z=-90; see original derivation).
		nose.rotation_degrees = Vector3(0, 0, -90)
	ship_render.add_child(nose)

	# Pitot tube — sharp needle at the tip (skipped on the blunt nose).
	if nose_has_pitot:
		var pitot := MeshInstance3D.new()
		var pitm := CylinderMesh.new()
		pitm.top_radius = 0.006; pitm.bottom_radius = 0.010; pitm.height = pitot_len
		pitm.material = mat_dark
		pitot.mesh = pitm
		pitot.rotation_degrees = Vector3(0, 0, 90)
		pitot.position = Vector3(pitot_x, 0, 0)
		ship_render.add_child(pitot)

	# Rear section — wider flat box housing the twin engines
	var rear := MeshInstance3D.new()
	var rearm := BoxMesh.new()
	rearm.size = Vector3(0.30, 0.20, 0.55); rearm.material = mat_hull
	rear.mesh = rearm
	rear.position = Vector3(-0.55, -0.01, 0)
	ship_render.add_child(rear)
	# Engine block top chine — angled accent on rear
	var rear_chine := MeshInstance3D.new()
	var rcm := PrismMesh.new()
	rcm.size = Vector3(0.50, 0.05, 0.28); rcm.material = mat_accent
	rear_chine.mesh = rcm
	rear_chine.rotation_degrees = Vector3(0, 90, 0)
	rear_chine.position = Vector3(-0.55, 0.11, 0)
	ship_render.add_child(rear_chine)

	# ============================================================
	#                  COCKPIT (angled wedge canopy)
	# ============================================================
	# Faceted canopy — three flat panels (front windshield, top, rear taper)
	# instead of a rounded bubble for a more aggressive look.
	# Position envelope: x = 0.18 .. 0.55, y = 0.07 .. 0.16

	# Windshield — angled front glass panel
	var windshield := MeshInstance3D.new()
	var wsm := PrismMesh.new()
	wsm.size = Vector3(0.10, 0.10, 0.22); wsm.material = mat_glass
	windshield.mesh = wsm
	windshield.rotation_degrees = Vector3(0, 90, 0)
	windshield.position = Vector3(0.36, 0.09, 0)
	ship_render.add_child(windshield)

	# Main canopy — flat top glass section
	var canopy := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.20, 0.08, 0.20); cm.material = mat_glass
	canopy.mesh = cm
	canopy.position = Vector3(0.25, 0.10, 0)
	ship_render.add_child(canopy)

	# Rear taper — angled back glass, opposite of windshield
	var cock_rear := MeshInstance3D.new()
	var crm := PrismMesh.new()
	crm.size = Vector3(0.10, 0.08, 0.18); crm.material = mat_glass
	cock_rear.mesh = crm
	cock_rear.rotation_degrees = Vector3(0, -90, 0)  # mirrored vs. windshield
	cock_rear.position = Vector3(0.14, 0.08, 0)
	ship_render.add_child(cock_rear)

	# Canopy center rib — single sharp dark seam running along the top
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.40, 0.018, 0.018); fm.material = mat_dark
	frame.mesh = fm
	frame.position = Vector3(0.25, 0.16, 0)
	ship_render.add_child(frame)

	# Cockpit interior glow — pilot HUD strip
	var console_mat := StandardMaterial3D.new()
	console_mat.albedo_color = led_col
	console_mat.emission_enabled = true
	console_mat.emission = led_col
	console_mat.emission_energy_multiplier = 3.0
	console_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var console := MeshInstance3D.new()
	var conm := BoxMesh.new()
	conm.size = Vector3(0.16, 0.012, 0.12); conm.material = console_mat
	console.mesh = conm
	console.position = Vector3(0.28, 0.07, 0)
	ship_render.add_child(console)
	p_pulse_lights.append({"mat": console_mat, "base": 2.6, "amp": 0.7, "freq": 1.5, "phase": 0.0})

	# Pilot seat hint
	var seat := MeshInstance3D.new()
	var stm := BoxMesh.new()
	stm.size = Vector3(0.07, 0.08, 0.09); stm.material = mat_dark
	seat.mesh = stm
	seat.position = Vector3(0.22, 0.10, 0)
	ship_render.add_child(seat)

	# ============================================================
	#                    AIR INTAKES (chin-mounted)
	# ============================================================
	# Compact wedge-shaped intakes flanking the lower forward fuselage.
	for sign_v in [-1, 1]:
		var intake := MeshInstance3D.new()
		var intm := BoxMesh.new()
		intm.size = Vector3(0.30, 0.12, 0.14); intm.material = mat_dark
		intake.mesh = intm
		intake.position = Vector3(0.20, -0.06, sign_v * 0.28)
		intake.rotation_degrees = Vector3(0, sign_v * -8, 0)
		ship_render.add_child(intake)
		# Throat glow — recessed bright red bay behind the intake
		var throat := MeshInstance3D.new()
		var trm := BoxMesh.new()
		trm.size = Vector3(0.03, 0.08, 0.10); trm.material = mat_intake
		throat.mesh = trm
		throat.position = Vector3(0.02, -0.06, sign_v * 0.28)
		ship_render.add_child(throat)
		# Cyan lip strip along the intake leading edge
		var lip := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.014, 0.018, 0.14); lm.material = mat_panel_glow
		lip.mesh = lm
		lip.position = Vector3(0.35, 0.0, sign_v * 0.28)
		ship_render.add_child(lip)

	# ============================================================
	#                          WINGS (swept delta, aggressive)
	# ============================================================
	# Sharper, shorter, more aggressively swept wings for a sporty look.
	# Wing shape is design-driven (ship_design.wings): chord/span/sweep vary per
	# option; "none" yields an empty side list so the loop builds nothing.
	var wkind: String = str(ship_design.get("wings", "swept"))
	var w_chord: float = 0.55
	var w_span: float = 0.68
	var w_le_sweep: float = 42.0
	match wkind:
		"delta":
			w_chord = 0.72; w_span = 0.52; w_le_sweep = 30.0
		"long":
			w_chord = 0.46; w_span = 0.95; w_le_sweep = 48.0
	var w_span_ratio: float = w_span / 0.68   # scales tip/edge/pylon offsets with span
	var wing_sides: Array = [] if wkind == "none" else [-1, 1]
	for sign_v in wing_sides:
		var wing := MeshInstance3D.new()
		var wm := PrismMesh.new()
		# Root chord / span are design-driven; thickness fixed at 0.05
		wm.size = Vector3(w_chord, w_span, 0.05); wm.material = mat_hull
		wing.mesh = wm
		# Starboard must be the exact Z-mirror of port. The z=0 mirror of a YXZ
		# Euler(rx,ry,rz) is Euler(-rx,-ry,rz), so BOTH the X and Y angle flip sign
		# per side. (Previously only Y flipped → the right wing came out twisted.)
		wing.rotation_degrees = Vector3(sign_v * 90, sign_v * 90, 0)
		wing.position = Vector3(-0.10, -0.04, sign_v * 0.40)
		ship_render.add_child(wing)
		# Leading-edge glow along the swept edge
		var le := MeshInstance3D.new()
		var lem := BoxMesh.new()
		lem.size = Vector3(0.50, 0.020, 0.025); lem.material = mat_panel_glow
		le.mesh = lem
		le.position = Vector3(0.02, -0.02, sign_v * 0.55 * w_span_ratio)
		le.rotation_degrees = Vector3(0, sign_v * w_le_sweep, 0)  # design-driven sweep
		ship_render.add_child(le)
		# Wing-tip navigation light (port red / starboard green)
		var tip := MeshInstance3D.new()
		var tm := SphereMesh.new()
		tm.radius = 0.05; tm.height = 0.10
		var tmat := StandardMaterial3D.new()
		var tip_col: Color = Color(0.3, 1.0, 0.4) if sign_v > 0 else Color(1.0, 0.3, 0.3)
		tmat.albedo_color = tip_col
		tmat.emission_enabled = true
		tmat.emission = tip_col
		tmat.emission_energy_multiplier = 5.0
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.material = tmat
		tip.mesh = tm
		tip.position = Vector3(-0.40, -0.03, sign_v * 0.92 * w_span_ratio)
		ship_render.add_child(tip)
		p_pulse_lights.append({"mat": tmat, "base": 4.0, "amp": 3.5, "freq": 1.8,
			"phase": (0.0 if sign_v > 0 else PI)})
		# Underwing hardpoint pylon
		var pylon := MeshInstance3D.new()
		var pym := BoxMesh.new()
		pym.size = Vector3(0.14, 0.04, 0.05); pym.material = mat_dark
		pylon.mesh = pym
		pylon.position = Vector3(-0.05, -0.08, sign_v * 0.58 * w_span_ratio)
		ship_render.add_child(pylon)

	# ============================================================
	#                TWIN VERTICAL STABILIZERS (F-22 canted)
	# ============================================================
	# Tail design (ship_design.tail): "twin" = two canted stabs, "single" = one
	# upright centre stab, "none" = no tail. Each spec carries the stab z, the
	# glow-strip z (sits a bit further outboard), and the outward cant angle.
	var tail_kind: String = str(ship_design.get("tail", "twin"))
	var tail_specs: Array = []
	match tail_kind:
		"twin":
			tail_specs = [{"z": -0.20, "vz": -0.26, "cant": -28.0}, {"z": 0.20, "vz": 0.26, "cant": 28.0}]
		"single":
			tail_specs = [{"z": 0.0, "vz": 0.0, "cant": 0.0}]
	for spec in tail_specs:
		var t_z: float = spec["z"]
		var t_vz: float = spec["vz"]
		var t_cant: float = spec["cant"]
		var vstab := MeshInstance3D.new()
		var vpm := PrismMesh.new()
		vpm.size = Vector3(0.34, 0.34, 0.04); vpm.material = mat_hull
		vstab.mesh = vpm
		vstab.position = Vector3(-0.55, 0.14, t_z)
		# Steeper sweep (-12°) + outward cant (per spec)
		vstab.rotation_degrees = Vector3(0, -12, t_cant)
		ship_render.add_child(vstab)
		# Leading-edge glow strip
		var vfg := MeshInstance3D.new()
		var vfgm := BoxMesh.new()
		vfgm.size = Vector3(0.24, 0.016, 0.02); vfgm.material = mat_panel_glow
		vfg.mesh = vfgm
		vfg.position = Vector3(-0.45, 0.32, t_vz)
		vfg.rotation_degrees = Vector3(0, -12, t_cant)
		ship_render.add_child(vfg)

	# ============================================================
	#            ENGINE NOZZLES + BOOST FLAMES (design-driven count)
	# ============================================================
	# ship_design.engines (1/2/3) → engine z-offsets. The two animated glow mats
	# (port/starboard) are ALWAYS created so _animate_ship_lights stays null-safe;
	# a centre engine reuses the port mat.
	var eng_count: int = clampi(int(ship_design.get("engines", 2)), 1, 3)
	var eng_z: Array = [0.0] if eng_count == 1 else ([-0.14, 0.14] if eng_count == 2 else [-0.22, 0.0, 0.22])
	# Bells (dark housing, no pulsing): one per engine
	for ez in eng_z:
		var bell := MeshInstance3D.new()
		var bellm := BoxMesh.new()
		bellm.size = Vector3(0.20, 0.18, 0.18); bellm.material = mat_dark
		bell.mesh = bellm
		bell.position = Vector3(-0.78, -0.02, ez)
		ship_render.add_child(bell)

	# Engine plasma glows: the two animated materials are created up-front (the
	# animation drives BOTH, regardless of count), then one glow sphere is built
	# per engine — z<0 uses the port mat, z>0 the starboard mat, a centre engine
	# (z==0) the port mat. _animate_ship_lights updates port + starboard with two
	# separate explicit assignments, so there is no shared state to fall out of sync.
	p_engine_mat_port = _make_engine_glow_mat(pal_engine)
	p_engine_mat_starboard = _make_engine_glow_mat(pal_engine)
	p_engine_glow = null
	for ez in eng_z:
		var egmat: StandardMaterial3D = p_engine_mat_starboard if ez > 0.0 else p_engine_mat_port
		var eg := MeshInstance3D.new()
		var egm := SphereMesh.new()
		egm.radius = 0.10
		egm.height = 0.20
		eg.mesh = egm
		eg.material_override = egmat
		eg.position = Vector3(-0.92, -0.02, ez)
		ship_render.add_child(eg)
		p_engine_glow = eg   # boost-pulse scales the last (rightmost) glow sphere
	p_engine_glow_mat = p_engine_mat_starboard

	# Boost flame container — twin flames, scale-driven length, shared material.
	# Container is anchored EXACTLY at the nozzle exit (-0.88 X). Each capsule
	# is offset rearward by half its mesh length so its front cap lands on the
	# container origin (= nozzle), and growing the container's scale.x extends
	# the flame only in the -X direction (out the back), never forward into
	# the ship.
	p_boost_flame = Node3D.new()
	p_boost_flame.position = Vector3(-0.88, -0.02, 0)
	p_boost_flame.scale = Vector3(0.01, 0.01, 0.01)
	p_boost_flame.visible = false
	ship_render.add_child(p_boost_flame)
	var bfmat := StandardMaterial3D.new()
	var bf_albedo: Color = pal_engine.lightened(0.3)
	bf_albedo.a = 0.85
	bfmat.albedo_color = bf_albedo
	bfmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bfmat.emission_enabled = true
	bfmat.emission = pal_engine
	bfmat.emission_energy_multiplier = 6.0
	bfmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bfmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p_boost_flame_mat = bfmat
	var flame_len: float = 0.9
	for ez in eng_z:
		var bf := MeshInstance3D.new()
		var bfm := CylinderMesh.new()
		# Cone: wide at the nozzle, tapering to a point at the rear of the flame.
		# Top is the rear (small radius, ~point), bottom is the nozzle face.
		bfm.top_radius = 0.005
		bfm.bottom_radius = 0.085
		bfm.height = flame_len
		bfm.material = bfmat
		bf.mesh = bfm
		# Rotate so the cylinder's local +Y (top = rear point) becomes world -X
		# and local -Y (bottom = wide nozzle face) becomes world +X (toward nozzle).
		bf.rotation_degrees = Vector3(0, 0, 90)
		# Offset rearward so the cone's wide face lands exactly on container origin
		# (= nozzle exit at world x=-0.88); one flame per engine.
		bf.position = Vector3(-flame_len * 0.5, 0, ez)
		p_boost_flame.add_child(bf)

	# ============================================================
	#                    HEAT VENTS + ANTENNA
	# ============================================================
	# Glowing dorsal heat slots between cockpit and engines (sits on the chine)
	for i in 3:
		var hg := MeshInstance3D.new()
		var hgm := BoxMesh.new()
		hgm.size = Vector3(0.08, 0.014, 0.04); hgm.material = mat_panel_glow
		hg.mesh = hgm
		hg.position = Vector3(-0.10 - i * 0.13, 0.115, 0)
		ship_render.add_child(hg)

	# Short antenna stub behind canopy + warning blinker
	var ant := MeshInstance3D.new()
	var ancm := CylinderMesh.new()
	ancm.top_radius = 0.008; ancm.bottom_radius = 0.018; ancm.height = 0.14
	ancm.material = mat_dark
	ant.mesh = ancm
	ant.position = Vector3(0.05, 0.20, 0)
	ship_render.add_child(ant)
	var ant_tip := MeshInstance3D.new()
	var atm := SphereMesh.new()
	atm.radius = 0.018; atm.height = 0.036
	var atmat := StandardMaterial3D.new()
	atmat.albedo_color = Color(1.0, 0.6, 0.3)
	atmat.emission_enabled = true
	atmat.emission = Color(1.0, 0.55, 0.25)
	atmat.emission_energy_multiplier = 6.0
	atmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	atm.material = atmat
	ant_tip.mesh = atm
	ant_tip.position = Vector3(0.05, 0.28, 0)
	ship_render.add_child(ant_tip)
	p_pulse_lights.append({"mat": atmat, "base": 5.0, "amp": 4.5, "freq": 2.6, "phase": 0.0})

	# ============================================================
	#               HULL DETAIL: panel lines + nav lights
	# ============================================================
	# Two diagonal panel seams angling backward from cockpit (stealth look)
	for sign_v2 in [-1, 1]:
		var diag := MeshInstance3D.new()
		var dgm := BoxMesh.new()
		dgm.size = Vector3(0.42, 0.008, 0.012); dgm.material = mat_panel_line
		diag.mesh = dgm
		diag.position = Vector3(-0.05, 0.08, sign_v2 * 0.18)
		diag.rotation_degrees = Vector3(0, sign_v2 * 18, 0)
		ship_render.add_child(diag)

	# Belly maneuvering thrusters (three small amber dots)
	for x_off in [0.35, 0.0, -0.35]:
		var thr := MeshInstance3D.new()
		var thrm := SphereMesh.new()
		thrm.radius = 0.030; thrm.height = 0.06
		var thrmat := StandardMaterial3D.new()
		thrmat.albedo_color = Color(1.0, 0.7, 0.4)
		thrmat.emission_enabled = true
		thrmat.emission = Color(1.0, 0.65, 0.35)
		thrmat.emission_energy_multiplier = 3.5
		thrmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		thrm.material = thrmat
		thr.mesh = thrm
		thr.position = Vector3(x_off, -0.16, 0)
		ship_render.add_child(thr)

	# Anti-collision strobes (white, fast blink)
	var strobe_mat := StandardMaterial3D.new()
	strobe_mat.albedo_color = Color(1.0, 1.0, 1.0)
	strobe_mat.emission_enabled = true
	strobe_mat.emission = Color(1.0, 1.0, 1.0)
	strobe_mat.emission_energy_multiplier = 4.5
	strobe_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 2:
		var sb := MeshInstance3D.new()
		var sbm := SphereMesh.new()
		sbm.radius = 0.018; sbm.height = 0.036
		sbm.material = strobe_mat
		sb.mesh = sbm
		sb.position = Vector3(-0.3 + i * 0.5, -0.15, 0)
		ship_render.add_child(sb)
	p_pulse_lights.append({"mat": strobe_mat, "base": 3.5, "amp": 4.0, "freq": 3.2, "phase": 0.0})

	# Hull number plate
	var num_mat := StandardMaterial3D.new()
	num_mat.albedo_color = Color(0.6, 0.65, 0.78)
	num_mat.metallic = 0.3
	num_mat.roughness = 0.55
	for i in 3:
		var block := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.004, 0.03); bm.material = num_mat
		block.mesh = bm
		block.position = Vector3(-0.15 + i * 0.045, 0.11, 0.18)
		ship_render.add_child(block)

	# ============================================================
	#                     EXTRA HULL DETAILS
	# ============================================================
	# Side windows — rows of small glowing rectangles along the body sides.
	# Different x positions so they don't look mechanically perfect.
	var window_mat := StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.85, 0.95, 1.0)
	window_mat.emission_enabled = true
	window_mat.emission = Color(0.45, 0.85, 1.0)
	window_mat.emission_energy_multiplier = 3.2
	window_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for sign_v in [-1, 1]:
		for i in 6:
			var win := MeshInstance3D.new()
			var wmm := BoxMesh.new()
			wmm.size = Vector3(0.045, 0.025, 0.012); wmm.material = window_mat
			win.mesh = wmm
			win.position = Vector3(-0.28 + i * 0.10, 0.02, sign_v * 0.245)
			ship_render.add_child(win)
		# Cockpit-area portholes (one row below the canopy)
		for i in 3:
			var ph := MeshInstance3D.new()
			var phm := BoxMesh.new()
			phm.size = Vector3(0.030, 0.020, 0.010); phm.material = window_mat
			ph.mesh = phm
			ph.position = Vector3(0.18 + i * 0.06, -0.02, sign_v * 0.21)
			ship_render.add_child(ph)

	# Cooling grilles — parallel thin dark strips on the upper rear (heat dump)
	for sign_v in [-1, 1]:
		for i in 5:
			var grille := MeshInstance3D.new()
			var grm := BoxMesh.new()
			grm.size = Vector3(0.01, 0.008, 0.10); grm.material = mat_panel_line
			grille.mesh = grm
			grille.position = Vector3(-0.42 - i * 0.025, 0.105, sign_v * 0.16)
			ship_render.add_child(grille)

	# Hot exhaust vent slots — three glowing orange slots on either side of
	# the rear fuselage (visible "heat dumping" while at speed).
	var hot_vent_mat := StandardMaterial3D.new()
	hot_vent_mat.albedo_color = Color(1.0, 0.5, 0.25)
	hot_vent_mat.emission_enabled = true
	hot_vent_mat.emission = Color(1.0, 0.4, 0.15)
	hot_vent_mat.emission_energy_multiplier = 2.8
	hot_vent_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for sign_v in [-1, 1]:
		for i in 3:
			var hv := MeshInstance3D.new()
			var hvm := BoxMesh.new()
			hvm.size = Vector3(0.05, 0.02, 0.012); hvm.material = hot_vent_mat
			hv.mesh = hvm
			hv.position = Vector3(-0.45 + i * 0.07, 0.0, sign_v * 0.265)
			ship_render.add_child(hv)
	p_pulse_lights.append({"mat": hot_vent_mat, "base": 2.5, "amp": 0.6, "freq": 0.9, "phase": 0.6})

	# Sensor domes — two small black hemispheres on the spine ahead/behind cockpit
	for x_off in [0.62, -0.05]:
		var sensor := MeshInstance3D.new()
		var sphm := SphereMesh.new()
		sphm.radius = 0.025; sphm.height = 0.05
		sphm.material = mat_dark
		sensor.mesh = sphm
		sensor.position = Vector3(x_off, 0.10, 0)
		ship_render.add_child(sensor)
		# Tiny red LED on top of the dome
		var led := MeshInstance3D.new()
		var ledm := SphereMesh.new()
		ledm.radius = 0.010; ledm.height = 0.020
		var ledmat := StandardMaterial3D.new()
		ledmat.albedo_color = Color(1.0, 0.3, 0.3)
		ledmat.emission_enabled = true
		ledmat.emission = Color(1.0, 0.25, 0.25)
		ledmat.emission_energy_multiplier = 5.0
		ledmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ledm.material = ledmat
		led.mesh = ledm
		led.position = Vector3(x_off, 0.13, 0)
		ship_render.add_child(led)

	# Service hatches — small flat squares of darker material along the spine
	for x_off in [0.10, -0.20, -0.40]:
		var hatch := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.08, 0.008, 0.06); hm.material = mat_dark
		hatch.mesh = hm
		hatch.position = Vector3(x_off, 0.105, 0.12)
		ship_render.add_child(hatch)

	# Sub-system status LEDs — small chain of mixed-color blinkers on the spine
	var led_colors: Array[Color] = [
		Color(0.3, 1.0, 0.4),   # green
		Color(0.4, 0.8, 1.0),   # cyan
		Color(1.0, 0.85, 0.3),  # amber
		Color(1.0, 0.4, 0.3),   # red
	]
	for i in 4:
		var sled := MeshInstance3D.new()
		var sledm := SphereMesh.new()
		sledm.radius = 0.010; sledm.height = 0.020
		var sledmat := StandardMaterial3D.new()
		sledmat.albedo_color = led_colors[i]
		sledmat.emission_enabled = true
		sledmat.emission = led_colors[i]
		sledmat.emission_energy_multiplier = 4.5
		sledmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sledm.material = sledmat
		sled.mesh = sledm
		sled.position = Vector3(0.34, 0.115, -0.075 + i * 0.05)
		ship_render.add_child(sled)
		p_pulse_lights.append({"mat": sledmat, "base": 3.5, "amp": 2.5, "freq": 2.0 + i * 0.3, "phase": i * 0.7})

	# Whip antennae — two thin spikes on the rear spine (sensor mast cluster)
	for sign_v in [-1, 1]:
		var whip := MeshInstance3D.new()
		var whm := CylinderMesh.new()
		whm.top_radius = 0.003; whm.bottom_radius = 0.008; whm.height = 0.16
		whm.material = mat_dark
		whip.mesh = whm
		whip.position = Vector3(-0.36, 0.20, sign_v * 0.06)
		whip.rotation_degrees = Vector3(0, 0, sign_v * 8)  # slight outward lean
		ship_render.add_child(whip)

	# Belly emergency lights (small steady reds, no pulse)
	for sign_v in [-1, 1]:
		var em_light := MeshInstance3D.new()
		var emm := SphereMesh.new()
		emm.radius = 0.015; emm.height = 0.030
		var emmat := StandardMaterial3D.new()
		emmat.albedo_color = Color(1.0, 0.2, 0.2)
		emmat.emission_enabled = true
		emmat.emission = Color(1.0, 0.2, 0.2)
		emmat.emission_energy_multiplier = 3.5
		emmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		emm.material = emmat
		em_light.mesh = emm
		em_light.position = Vector3(-0.30, -0.14, sign_v * 0.20)
		ship_render.add_child(em_light)

	# Wing electronics box — small dark box on the upper wing root with a glow strip
	for sign_v in [-1, 1]:
		var ebox := MeshInstance3D.new()
		var ebm := BoxMesh.new()
		ebm.size = Vector3(0.10, 0.04, 0.08); ebm.material = mat_dark
		ebox.mesh = ebm
		ebox.position = Vector3(-0.05, 0.02, sign_v * 0.34)
		ship_render.add_child(ebox)
		var estrip := MeshInstance3D.new()
		var estm := BoxMesh.new()
		estm.size = Vector3(0.08, 0.008, 0.012); estm.material = mat_panel_glow
		estrip.mesh = estm
		estrip.position = Vector3(-0.05, 0.045, sign_v * 0.34)
		ship_render.add_child(estrip)

# ============================================================
# Player update
# ============================================================

func _update_player(delta: float) -> void:
	var dir := Vector3.ZERO
	# Suppress flight input while typing in chat — keys are polled from the
	# hardware regardless of focus, so they must be gated explicitly.
	if not chat_typing:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    dir.y += 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  dir.y -= 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	var input_active: float = clamp(dir.length(), 0.0, 1.0)
	if dir.length_squared() > 0.0:
		dir = dir.normalized()

	# Boost: Shift held → drain charge for a temporary speed multiplier.
	# Recharges from empty to full in exactly BOOST_RECHARGE_TIME seconds.
	# `boost_depleted` latches when the tank runs dry mid-boost so the player
	# can't stutter-boost off the recharge by simply holding Shift; they must
	# release and re-press once charge has built back up.
	var shift_held: bool = Input.is_key_pressed(KEY_SHIFT) and not chat_typing
	if not shift_held:
		boost_depleted = false
	var want_boost: bool = shift_held and input_active > 0.0 and not boost_depleted
	boosting = want_boost and boost_charge > 0.0
	if boosting:
		boost_charge = max(0.0, boost_charge - BOOST_DRAIN_RATE * delta)
		if boost_charge <= 0.0:
			boost_depleted = true
	else:
		var rate: float = u_boost_max / BOOST_RECHARGE_TIME
		boost_charge = min(u_boost_max, boost_charge + rate * delta)

	var effective_speed: float = P_SPEED * u_speed_mult
	if boosting:
		effective_speed *= u_boost_strength
	var target_vel: Vector3 = dir * effective_speed
	# Snappier acceleration during boost so the burst is felt immediately
	var accel: float = 22.0 if boosting else 12.0
	p_vel = p_vel.lerp(target_vel, clamp(delta * accel, 0.0, 1.0))
	p_pos += p_vel * delta
	# Open space — no arena clamps. Player can fly anywhere.
	p_node.position = p_pos

	# Facing follows movement direction — player aims the ship themselves.
	# Auto-aim no longer steers; it only fires when a target happens to be in
	# front (see _update_fire / _nearest_enemy_in_cone).
	if p_vel.length() > 0.5:
		p_facing = p_vel.normalized()
	p_node.rotation = Vector3(0, 0, atan2(p_facing.y, p_facing.x))

	# Boost loop volume + pitch — both scale with remaining charge so the player
	# can hear the tank running dry. While boost is held the volume snaps to
	# the charge-driven target immediately (no fade-in lag); on release it
	# fades smoothly to silence so there's no audio pop.
	if boost_sfx != null:
		var charge_frac: float = clamp(boost_charge / max(u_boost_max, 0.01), 0.0, 1.0)
		# Non-linear curve: sound stays prominent through most of the boost,
		# then drops off sharply in the last ~30% so the warning is unmistakable.
		var fade_curve: float = pow(charge_frac, 0.55)
		if boosting:
			boost_db_smoothed = lerp(-28.0, -3.0, fade_curve)
			boost_sfx.pitch_scale = lerp(0.55, 1.0, fade_curve)
		else:
			boost_db_smoothed = lerp(boost_db_smoothed, -80.0, clamp(delta * 14.0, 0.0, 1.0))
			boost_sfx.pitch_scale = 1.0
		boost_sfx.volume_db = boost_db_smoothed

	# Engine loop volume — uses the *higher* of input intent and current speed
	# so that direction switches (W→S, etc.) don't drop the sound during the
	# velocity zero-crossing. Quieter overall than before.
	if engine_sfx != null:
		var max_speed: float = P_SPEED * u_speed_mult
		var speed_norm: float = clamp(p_vel.length() / max(max_speed, 0.01), 0.0, 1.0)
		var activity: float = max(input_active, speed_norm)
		var target_db: float = -80.0 if activity < 0.05 else lerp(-56.0, -36.0, activity)
		engine_db_smoothed = lerp(engine_db_smoothed, target_db, clamp(delta * 5.0, 0.0, 1.0))
		engine_sfx.volume_db = engine_db_smoothed

	# Engine glow pulse
	if p_engine_glow != null:
		var s: float = 1.0 + sin(run_time * 14.0) * 0.18
		p_engine_glow.scale = Vector3(s, s, s)

	# Invuln blink (only blink while invulnerable, otherwise always visible)
	if p_invuln_timer > 0.0:
		p_invuln_timer -= delta
		p_node.visible = int(p_invuln_timer * 20) % 2 != 0
	else:
		p_node.visible = true

# ============================================================
# Enemy AI
# ============================================================

func _update_enemies(delta: float) -> void:
	for e in enemies:
		if e.dead:
			continue
		e.hit_flash = max(0.0, e.hit_flash - delta * 4.0)
		# Marked escort attackers target the rescued bot, not the player.
		var tgt: Vector3 = escort_pos if e.marked else p_pos
		match e.type:
			"drone":
				_ai_chase(e, delta, 5.0, tgt)
			"shooter":
				_ai_keep_distance(e, delta, 4.2, 11.0, tgt)
				_ai_shoot(e, delta, 8, 9.5, tgt)
			"tank":
				_ai_chase(e, delta, 2.8, tgt)
			"boss":
				if e.is_mega and p_pos.distance_to(e.pos) > MEGA_WAKE:
					e.vel = e.vel.lerp(Vector3.ZERO, clamp(delta * 2.0, 0.0, 1.0))   # lurk until found
				else:
					_ai_boss(e, delta, tgt)
		e.pos += e.vel * delta
		_clamp_to_arena(e)
		if e.node != null:
			e.node.position = e.pos
			# Visual flash
			if e.hit_flash > 0.0:
				e.node.scale = Vector3.ONE * (1.0 + e.hit_flash * 0.15)
			else:
				e.node.scale = Vector3.ONE
			# Slow spin for boss
			if e.type == "boss":
				e.node.rotation.z += delta * 1.2

func _clamp_to_arena(e: Entity) -> void:
	# Open space — enemies follow player, no hard arena boundaries
	pass

func _ai_chase(e: Entity, delta: float, speed: float, target: Vector3) -> void:
	var to_p: Vector3 = target - e.pos
	var d: float = to_p.length()
	if d > 0.01:
		e.vel = e.vel.lerp(to_p / d * speed, clamp(delta * 4.0, 0.0, 1.0))

func _ai_keep_distance(e: Entity, delta: float, speed: float, ideal: float, target: Vector3) -> void:
	var to_p: Vector3 = target - e.pos
	var d: float = to_p.length()
	if d < 0.01:
		return
	var dir: Vector3 = to_p / d
	var target_vel: Vector3 = dir * speed
	if d < ideal - 1.2:
		target_vel = -dir * speed
	elif d <= ideal + 1.2:
		# Strafe perpendicular (in XY plane)
		target_vel = Vector3(-dir.y, dir.x, 0) * speed * 0.7
	e.vel = e.vel.lerp(target_vel, clamp(delta * 3.5, 0.0, 1.0))

func _ai_shoot(e: Entity, delta: float, dmg: int, bullet_speed: float, target: Vector3) -> void:
	e.shoot_timer -= delta
	if e.shoot_timer > 0.0:
		return
	e.shoot_timer = e.shoot_cd
	var dir: Vector3 = (target - e.pos).normalized()
	_spawn_e_bullet(e.pos, dir * bullet_speed, dmg)

func _ai_boss(e: Entity, delta: float, target: Vector3) -> void:
	_ai_keep_distance(e, delta, 3.2, 10.0, target)
	e.shoot_timer -= delta
	if e.shoot_timer > 0.0:
		return
	e.shoot_timer = e.shoot_cd
	var base: Vector3 = (target - e.pos).normalized()
	var base_a: float = atan2(base.y, base.x)
	for i in range(-1, 2):
		var a: float = base_a + deg_to_rad(i * 14.0)
		var v: Vector3 = Vector3(cos(a), sin(a), 0) * 11.0
		_spawn_e_bullet(e.pos, v, 12)
	if randf() < 0.2:
		for i in 10:
			var a2: float = (i / 10.0) * TAU
			_spawn_e_bullet(e.pos, Vector3(cos(a2), sin(a2), 0) * 8.5, 8)

# ============================================================
# Bullets / gems update
# ============================================================

func _update_p_bullets(delta: float) -> void:
	for b in p_bullets:
		if b.dead:
			continue
		b.pos += b.vel * delta
		b.lifetime -= delta
		if b.lifetime <= 0.0 or _out_of_arena(b.pos):
			b.dead = true
		elif b.node != null:
			b.node.position = b.pos

func _update_e_bullets(delta: float) -> void:
	for b in e_bullets:
		if b.dead:
			continue
		b.pos += b.vel * delta
		b.lifetime -= delta
		if b.lifetime <= 0.0 or _out_of_arena(b.pos):
			b.dead = true
		elif b.node != null:
			b.node.position = b.pos

func _update_gems(delta: float) -> void:
	var pickup_r: float = P_PICKUP_RANGE * u_pickup_mult
	for g in gems:
		if g.dead:
			continue
		g.pulse += delta
		var to_p: Vector3 = p_pos - g.pos
		var d: float = to_p.length()
		if d <= pickup_r:
			g.vel = g.vel.lerp(to_p.normalized() * 20.0 * (1.5 - d / pickup_r), clamp(delta * 8.0, 0.0, 1.0))
		else:
			g.vel = g.vel.lerp(Vector3.ZERO, clamp(delta * 4.0, 0.0, 1.0))
		g.pos += g.vel * delta
		if g.node != null:
			g.node.position = g.pos
			g.node.rotation.z = g.pulse * 4.0
			var s: float = 0.9 + sin(g.pulse * 6.0) * 0.12
			g.node.scale = Vector3(s, s, s)
		if d <= P_RADIUS + g.radius:
			p_xp += g.value
			g.dead = true
			_check_level_up()

func _out_of_arena(p: Vector3) -> bool:
	# Bullets despawn when they get too far from the player (open-space)
	return p.distance_to(p_pos) > 35.0

# ============================================================
# Spawning
# ============================================================

func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	if _alive_enemy_count() >= MAX_ENEMIES:
		spawn_timer = 0.5
		return
	spawn_timer = spawn_interval
	_spawn_wave_enemy()

func _alive_enemy_count() -> int:
	var n := 0
	for e in enemies:
		if not e.dead:
			n += 1
	return n

# Difficulty tier driving enemy composition: the local player's level in
# single-player, the highest connected player's level on a co-op server.
func _party_level() -> int:
	if net_mode == NetMode.SERVER:
		var m := 1
		for id in net_states:
			m = maxi(m, int(net_states[id].get("level", 1)))
		return m
	return p_level

# Shared enemy-role roll: tougher roles unlock by party level, not elapsed waves.
func _pick_enemy_kind(lvl: int = -1) -> String:
	if lvl < 0:
		lvl = _party_level()   # single-player / fallback
	var pick := randf()
	if lvl >= TANK_MIN_LEVEL and pick < 0.08:
		return "tank"
	elif lvl >= SHOOTER_MIN_LEVEL and pick < 0.32:
		return "shooter"
	return "drone"

func _spawn_wave_enemy() -> void:
	_spawn_enemy(_pick_enemy_kind(), _ring_pos(SPAWN_RING * u_range_mult))

func _ring_pos(radius: float) -> Vector3:
	# Spawn around player in open space (no arena clamps)
	var ang: float = randf() * TAU
	return p_pos + Vector3(cos(ang), sin(ang), 0) * radius

func _spawn_enemy(kind: String, pos: Vector3, wave_n: int = -1, mega: bool = false) -> Entity:
	var e := Entity.new()
	e.type = kind
	e.pos = pos
	# Per-player wave on the server (passed in), global wave in single-player.
	var wn: int = wave_n if wave_n >= 0 else wave
	var wave_scale: float = 1.0 + (wn - 1) * 0.18
	# Generate procedural DNA — gives variety even within same role
	var dna := _generate_enemy_dna(kind, wn)
	var size: float = dna["size_mult"]
	# Mega-boss event: blow up the DNA size first so the mesh (built from size_mult
	# on clients too) comes out 5x; the `mega` flag rides along in the DNA.
	if mega:
		dna["mega"] = true
		dna["size_mult"] = size * MEGA_SCALE
		size = dna["size_mult"]
	match kind:
		"drone":
			e.hp = int(round(2 * wave_scale)); e.max_hp = e.hp
			e.radius = 0.45 * size / 0.55; e.damage = 10; e.value = 1
		"shooter":
			e.hp = int(round(5 * wave_scale)); e.max_hp = e.hp
			e.radius = 0.55 * size / 0.65; e.damage = 8; e.value = 3
			e.shoot_cd = 1.8; e.shoot_timer = 1.2
		"tank":
			e.hp = int(round(20 * wave_scale)); e.max_hp = e.hp
			e.radius = 0.95 * size / 1.05; e.damage = 22; e.value = 8
		"boss":
			e.hp = int(round(150 + wn * 25)); e.max_hp = e.hp
			e.radius = 1.5 * size / 1.7; e.damage = 25; e.value = 50
			e.shoot_cd = 1.0; e.shoot_timer = 1.0
	# Mega-boss stat overrides (radius already 5x via the scaled size above).
	if mega:
		e.is_mega = true
		e.hp = e.hp * MEGA_HP_MULT; e.max_hp = e.hp   # a real, drawn-out fight
		e.damage = MEGA_DAMAGE
		e.shoot_cd = 0.8
	e.dna = dna
	# Server: headless authority — assign a network id and tell clients to build
	# the mesh from the DNA, but build nothing locally.
	if net_mode == NetMode.SERVER:
		e.net_id = _next_net_id()
		enemies.append(e)
		spawn_enemy.rpc(e.net_id, dna, pos)
		return e
	e.node = _build_procedural_enemy(dna)
	e.node.position = pos
	world.add_child(e.node)
	# 3D ambient hum for the larger enemy types — gives positional cue
	if enemy_hum_stream != null and (kind == "tank" or kind == "boss"):
		var hum := AudioStreamPlayer3D.new()
		hum.stream = enemy_hum_stream
		hum.volume_db = -6.0 if kind == "tank" else 0.0
		hum.unit_size = 12.0 if kind == "tank" else 22.0
		hum.max_distance = 60.0 if kind == "tank" else 100.0
		hum.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		hum.pitch_scale = 1.0 if kind == "tank" else 0.7  # boss sounds deeper
		e.node.add_child(hum)
		hum.play()
	enemies.append(e)
	return e

func _spawn_boss_wave() -> void:
	var radius: float = SPAWN_RING * u_range_mult * 0.6
	if net_mode == NetMode.SERVER and not net_states.is_empty():
		# Center on an active player, never one whose level-up menu is open.
		var ids: Array = []
		for id in net_states:
			if not net_states[id].get("busy", false):
				ids.append(id)
		if ids.is_empty():
			ids = net_states.keys()
		var center: Vector3 = net_states[ids[randi() % ids.size()]]["pos"]
		var ang: float = randf() * TAU
		_spawn_enemy("boss", center + Vector3(cos(ang), sin(ang), 0) * radius)
	else:
		_spawn_enemy("boss", _ring_pos(radius))

# ============================================================
# World events (server + single-player authority). Clients receive the mega-boss
# through the normal enemy sync, so only the authority drives the cadence.
# ============================================================
func _update_events(delta: float) -> void:
	if net_mode == NetMode.CLIENT:
		return
	match active_event:
		"mega":
			if mega_active == null or mega_active.dead:
				_end_event()
			return
		"escort":
			_update_escort(delta)
			return
	# No active event → count down, then start a random eligible one.
	event_timer -= delta
	if event_timer > 0.0:
		return
	event_timer = randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX)
	var center: Vector3
	var lvl: int
	var wn: int
	if net_mode == NetMode.SERVER:
		var ids: Array = []
		for id in net_states:
			if not net_states[id].get("busy", false) and int(net_states[id].get("level", 1)) >= ESCORT_MIN_LEVEL:
				ids.append(id)
		if ids.is_empty():
			return
		var pid: int = ids[randi() % ids.size()]
		center = net_states[pid]["pos"]
		lvl = int(net_states[pid].get("level", 1))
		wn = int(net_states[pid].get("wave", 1))
	else:
		if p_level < ESCORT_MIN_LEVEL:
			return
		center = p_pos
		lvl = p_level
		wn = wave
	# The mega-boss needs a higher level; otherwise (or 50/50 above it) run the escort.
	if lvl >= MEGA_MIN_LEVEL and randf() < 0.5:
		_start_mega(center, wn)
	else:
		_start_escort(center, wn)

func _start_mega(center: Vector3, wn: int) -> void:
	var ang: float = randf() * TAU
	var pos: Vector3 = center + Vector3(cos(ang), sin(ang), 0) * randf_range(MEGA_SPAWN_MIN, MEGA_SPAWN_MAX)
	mega_active = _spawn_enemy("boss", pos, wn, true)
	active_event = "mega"
	_event_announce("⚠ ANOMALIE GEORTET — ein gewaltiger Gegner lauert. Folge dem Radar!")

# A friendly pilot pinned down by marked shooters — escort/rescue event.
func _start_escort(center: Vector3, wn: int) -> void:
	var ang: float = randf() * TAU
	escort_pos = center + Vector3(cos(ang), sin(ang), 0) * randf_range(ESCORT_SPAWN_MIN, ESCORT_SPAWN_MAX)
	escort_bot = _spawn_friendly(escort_pos, ESCORT_BOT_HP)
	escort_markers.clear()
	for i in ESCORT_MARKERS:
		var ma: float = float(i) / float(ESCORT_MARKERS) * TAU + randf_range(-0.3, 0.3)
		var mp: Vector3 = escort_pos + Vector3(cos(ma), sin(ma), 0) * randf_range(5.0, 10.0)
		var me := _spawn_enemy("shooter", mp, wn)
		me.marked = true
		escort_markers.append(me)
	escort_timer = ESCORT_TIME
	escort_obj_accum = 0.0
	active_event = "escort"
	_event_announce("🆘 NOTRUF — ein Pilot wird angegriffen! Räum die markierten Gegner aus, bevor er fällt!")

func _update_escort(delta: float) -> void:
	escort_timer -= delta
	# Fail: the bot was destroyed.
	if escort_bot == null or escort_bot.dead:
		_event_announce("💀 Der Pilot wurde zerstört … Rettung gescheitert.")
		_escort_finish(false)
		return
	# Count surviving markers.
	var alive: int = 0
	for m in escort_markers:
		if m != null and not m.dead:
			alive += 1
	# Success: all markers cleared in time.
	if alive == 0:
		for i in ESCORT_GEMS:
			_spawn_gem(escort_pos + Vector3(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), 0), 50)
		_event_announce("✅ PILOT GERETTET — fette Beute als Dank!")
		_escort_finish(true)
		return
	# Fail: time up.
	if escort_timer <= 0.0:
		_event_announce("⏱ Zeit abgelaufen … der Pilot flieht.")
		_escort_finish(false)
		return
	# Live objective line (throttled to ~2 Hz).
	escort_obj_accum -= delta
	if escort_obj_accum <= 0.0:
		escort_obj_accum = 0.5
		var hp_frac: int = int(round(100.0 * float(escort_bot.hp) / float(maxi(1, escort_bot.max_hp))))
		_set_objective("🆘 Rettung — Pilot %d%%  ·  %d Gegner  ·  %ds" % [hp_frac, alive, int(ceil(escort_timer))])

func _escort_finish(_success: bool) -> void:
	# Remove any surviving markers (no loot) and end the event.
	for m in escort_markers:
		if m != null and not m.dead:
			_despawn_enemy_entity(m)
	escort_markers.clear()
	_end_event()

# Tear down the active event and arm the next countdown.
func _end_event() -> void:
	if escort_bot != null:
		_despawn_friendly_entity(escort_bot)
		escort_bot = null
	mega_active = null
	active_event = ""
	event_timer = randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX)
	_set_objective("")

# Hard reset of all event state (world reset / restart) — no rewards.
func _reset_events() -> void:
	for f in friendlies.duplicate():
		_despawn_friendly_entity(f)
	friendlies.clear()
	escort_bot = null
	escort_markers.clear()
	mega_active = null
	active_event = ""
	escort_timer = 0.0
	event_timer = randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX)
	_set_objective("")

# Show a transient banner: broadcast from the server, local on single-player.
func _event_announce(text: String) -> void:
	if net_mode == NetMode.SERVER:
		announce_event.rpc(text)
	else:
		_show_announce(text)

@rpc("authority", "call_remote", "reliable")
func announce_event(text: String) -> void:
	if net_mode != NetMode.CLIENT or home_probing:
		return
	_show_announce(text)

func _show_announce(text: String) -> void:
	if announce_label == null:
		return
	announce_label.text = text
	announce_label.visible = true
	announce_timer = 6.0

# Persistent objective line (live timer / count during an event); "" hides it.
func _set_objective(text: String) -> void:
	if net_mode == NetMode.SERVER:
		receive_objective.rpc(text)
	else:
		_apply_objective(text)

@rpc("authority", "call_remote", "reliable")
func receive_objective(text: String) -> void:
	if net_mode != NetMode.CLIENT or home_probing:
		return
	_apply_objective(text)

func _apply_objective(text: String) -> void:
	if objective_label == null:
		return
	objective_label.text = text
	objective_label.visible = not text.is_empty()

# ---- Friendly bot (escort event): a synced non-enemy entity. ----
func _spawn_friendly(pos: Vector3, hp: int) -> Entity:
	var e := Entity.new()
	e.type = "friendly"
	e.pos = pos
	e.hp = hp
	e.max_hp = hp
	e.radius = 1.6
	if net_mode == NetMode.SERVER:
		e.net_id = _next_net_id()
		friendlies.append(e)
		spawn_friendly.rpc(e.net_id, pos)
		return e
	e.node = _build_friendly_mesh()
	e.node.position = pos
	world.add_child(e.node)
	friendlies.append(e)
	return e

# Free a friendly bot: tell clients (server) or drop the local node (single).
func _despawn_friendly_entity(e) -> void:
	if e == null:
		return
	e.dead = true
	if net_mode == NetMode.SERVER:
		despawn_friendly.rpc(e.net_id)
	elif e.node != null:
		e.node.queue_free()
	friendlies.erase(e)

@rpc("authority", "call_remote", "reliable")
func spawn_friendly(net_id: int, pos: Vector3) -> void:
	if net_mode != NetMode.CLIENT or home_probing:
		return
	if cl_friendlies.has(net_id):
		return
	var e := Entity.new()
	e.type = "friendly"
	e.net_id = net_id
	e.pos = pos
	e.tpos = pos
	e.radius = 1.6
	e.node = _build_friendly_mesh()
	e.node.position = pos
	world.add_child(e.node)
	cl_friendlies[net_id] = e
	friendlies.append(e)

@rpc("authority", "call_remote", "reliable")
func despawn_friendly(net_id: int) -> void:
	if net_mode != NetMode.CLIENT or not cl_friendlies.has(net_id):
		return
	var e: Entity = cl_friendlies[net_id]
	if e.node != null:
		e.node.queue_free()
	e.dead = true
	cl_friendlies.erase(net_id)
	friendlies.erase(e)

# Distinct ally craft: reuse the player ship visual in a green palette + a
# distress beacon and a floating SOS marker.
func _build_friendly_mesh() -> Node3D:
	var root := _build_ship_visual({"palette": 2, "wings": "delta", "engines": 2, "tail": "twin", "nose": "pointed", "leds": "green"})
	root.scale *= 1.5
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(0.4, 1.0, 0.55)
	beacon.light_energy = 2.5
	beacon.omni_range = 12.0
	root.add_child(beacon)
	if emoji_font != null:
		var lbl := Label3D.new()
		lbl.text = "🆘"
		lbl.font = emoji_font
		lbl.font_size = 120
		lbl.pixel_size = 0.011
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.render_priority = 9
		lbl.position = Vector3(0, 0, 3.0)
		root.add_child(lbl)
	return root

# Remove an enemy with no loot/score (event cleanup).
func _despawn_enemy_entity(e) -> void:
	if e == null:
		return
	e.dead = true
	if net_mode == NetMode.SERVER:
		despawn_enemy.rpc(e.net_id)
	elif e.node != null:
		e.node.queue_free()

func _make_enemy_mesh(kind: String) -> Node3D:
	var root := Node3D.new()
	# Tilt all enemy meshes to top-down (same convention as player ship_render)
	var body := Node3D.new()
	body.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(body)
	match kind:
		"drone":
			_build_enemy_drone(body)
		"shooter":
			_build_enemy_shooter(body)
		"tank":
			_build_enemy_tank(body)
		"boss":
			_build_enemy_boss(body)
	return root

func _build_enemy_drone(body: Node3D) -> void:
	# Hunter drone: dome core + spike ring + 4 thrusters — vertical 3D presence
	# Central glowing core
	var core := MeshInstance3D.new()
	var csm := SphereMesh.new()
	csm.radius = 0.22; csm.height = 0.44
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1, 0.3, 0.2)
	cmat.emission_enabled = true
	cmat.emission = Color(1, 0.3, 0.2)
	cmat.emission_energy_multiplier = 4.5
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	csm.material = cmat
	core.mesh = csm
	core.position = Vector3(0, 0.05, 0)
	body.add_child(core)
	# Outer hull shell (dome top)
	var shell := MeshInstance3D.new()
	var shm := SphereMesh.new()
	shm.radius = 0.34; shm.height = 0.4
	shm.material = mat_drone
	shell.mesh = shm
	shell.position = Vector3(0, 0.1, 0)
	body.add_child(shell)
	# Bottom shell (cylinder)
	var bottom := MeshInstance3D.new()
	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.35; bcm.bottom_radius = 0.28; bcm.height = 0.18
	bcm.material = mat_drone
	bottom.mesh = bcm
	bottom.position = Vector3(0, -0.05, 0)
	body.add_child(bottom)
	# Spike ring around equator (6 spikes)
	for i in 6:
		var ang: float = (i / 6.0) * TAU
		var spike := MeshInstance3D.new()
		var spm := PrismMesh.new()
		spm.size = Vector3(0.12, 0.32, 0.1); spm.material = mat_drone
		spike.mesh = spm
		spike.position = Vector3(cos(ang) * 0.38, 0.05, sin(ang) * 0.38)
		spike.rotation_degrees = Vector3(0, rad_to_deg(ang) + 90, -90)
		body.add_child(spike)
	# Forward sensor eye on top
	var eye := MeshInstance3D.new()
	var esm := SphereMesh.new()
	esm.radius = 0.08; esm.height = 0.14
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(1, 0.9, 0.4)
	emat.emission_enabled = true
	emat.emission = Color(1, 0.9, 0.4)
	emat.emission_energy_multiplier = 5.0
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	esm.material = emat
	eye.mesh = esm
	eye.position = Vector3(0.0, 0.32, 0)
	body.add_child(eye)
	# 4 corner thrusters underneath
	for i in 4:
		var ang: float = (i / 4.0) * TAU + PI / 4
		var thr := MeshInstance3D.new()
		var tsm := SphereMesh.new()
		tsm.radius = 0.07; tsm.height = 0.14
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(1, 0.55, 0.25)
		tmat.emission_enabled = true
		tmat.emission = Color(1, 0.55, 0.25)
		tmat.emission_energy_multiplier = 4.0
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tsm.material = tmat
		thr.mesh = tsm
		thr.position = Vector3(cos(ang) * 0.22, -0.18, sin(ang) * 0.22)
		body.add_child(thr)

func _build_enemy_shooter(body: Node3D) -> void:
	# Raptor-class ranged fighter: forward-swept body + 3 cannons + twin engines
	# Main hull (tapered)
	var hull := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.95, 0.32, 0.55); hm.material = mat_shooter
	hull.mesh = hm
	body.add_child(hull)
	# Lower keel
	var keel := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.7, 0.1, 0.3); km.material = _mat_metal(Color(0.5, 0.35, 0.15))
	keel.mesh = km
	keel.position = Vector3(0, -0.2, 0)
	body.add_child(keel)
	# Forward cockpit dome (orange glass)
	var cockpit := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.16; dm.height = 0.22
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.12, 0.08, 0.05)
	cmat.emission_enabled = true
	cmat.emission = Color(1, 0.6, 0.2)
	cmat.emission_energy_multiplier = 3.0
	cmat.metallic = 0.9; cmat.roughness = 0.1
	dm.material = cmat
	cockpit.mesh = dm
	cockpit.position = Vector3(0.32, 0.22, 0)
	body.add_child(cockpit)
	# Forward-swept wings
	for sign_v in [-1, 1]:
		var wing := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.55, 0.08, 0.45); wm.material = mat_shooter
		wing.mesh = wm
		wing.position = Vector3(-0.05, -0.02, sign_v * 0.5)
		wing.rotation_degrees = Vector3(0, sign_v * -25, 0)
		body.add_child(wing)
		# Wing-mounted gun pod
		var pod := MeshInstance3D.new()
		var pbm := BoxMesh.new()
		pbm.size = Vector3(0.25, 0.12, 0.15); pbm.material = _mat_metal(Color(0.45, 0.32, 0.15))
		pod.mesh = pbm
		pod.position = Vector3(0.18, -0.04, sign_v * 0.66)
		body.add_child(pod)
		# Gun barrel out front of pod
		var barrel := MeshInstance3D.new()
		var bcm := CylinderMesh.new()
		bcm.top_radius = 0.04; bcm.bottom_radius = 0.05; bcm.height = 0.4
		bcm.material = _mat_metal(Color(0.3, 0.2, 0.1))
		barrel.mesh = bcm
		barrel.position = Vector3(0.45, -0.04, sign_v * 0.66)
		barrel.rotation_degrees = Vector3(0, 0, 90)
		body.add_child(barrel)
	# Top central cannon (bigger)
	var top_cannon := MeshInstance3D.new()
	var tcm := CylinderMesh.new()
	tcm.top_radius = 0.06; tcm.bottom_radius = 0.08; tcm.height = 0.55
	tcm.material = _mat_metal(Color(0.4, 0.3, 0.15))
	top_cannon.mesh = tcm
	top_cannon.position = Vector3(0.32, 0.32, 0)
	top_cannon.rotation_degrees = Vector3(0, 0, 90)
	body.add_child(top_cannon)
	# Dorsal heat fin
	var fin := MeshInstance3D.new()
	var fm := PrismMesh.new()
	fm.size = Vector3(0.32, 0.35, 0.05); fm.material = mat_shooter
	fin.mesh = fm
	fin.position = Vector3(-0.25, 0.28, 0)
	body.add_child(fin)
	# Twin engine nacelles
	for sign_v in [-1, 1]:
		var nac := MeshInstance3D.new()
		var ncm := CylinderMesh.new()
		ncm.top_radius = 0.13; ncm.bottom_radius = 0.15; ncm.height = 0.45
		ncm.material = _mat_metal(Color(0.4, 0.3, 0.15))
		nac.mesh = ncm
		nac.position = Vector3(-0.42, -0.05, sign_v * 0.25)
		nac.rotation_degrees = Vector3(0, 0, 90)
		body.add_child(nac)
		# Nacelle exhaust glow
		var glow := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.13; gm.height = 0.26
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(1, 0.55, 0.2)
		gmat.emission_enabled = true
		gmat.emission = Color(1, 0.55, 0.2)
		gmat.emission_energy_multiplier = 4.5
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.material = gmat
		glow.mesh = gm
		glow.position = Vector3(-0.7, -0.05, sign_v * 0.25)
		body.add_child(glow)

func _build_enemy_tank(body: Node3D) -> void:
	# Fortress tank: layered hex body + 4 corner thrusters + central rotating turret
	# Hexagonal base hull (use 6-segment cylinder)
	var base := MeshInstance3D.new()
	var bcm := CylinderMesh.new()
	bcm.top_radius = 0.95; bcm.bottom_radius = 1.1; bcm.height = 0.32
	bcm.radial_segments = 6
	bcm.material = mat_tank
	base.mesh = bcm
	base.position = Vector3(0, -0.18, 0)
	body.add_child(base)
	# Upper hull (smaller hex)
	var upper := MeshInstance3D.new()
	var ucm := CylinderMesh.new()
	ucm.top_radius = 0.6; ucm.bottom_radius = 0.85; ucm.height = 0.3
	ucm.radial_segments = 6
	ucm.material = _mat_metal(Color(0.7, 0.3, 0.55))
	upper.mesh = ucm
	upper.position = Vector3(0, 0.1, 0)
	body.add_child(upper)
	# Side armor wedges (4 around hull)
	for i in 4:
		var ang: float = (i / 4.0) * TAU + PI / 4
		var armor := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.45, 0.4, 0.25); am.material = _mat_metal(Color(0.6, 0.25, 0.5))
		armor.mesh = am
		armor.position = Vector3(cos(ang) * 0.85, -0.1, sin(ang) * 0.85)
		armor.rotation_degrees = Vector3(0, rad_to_deg(ang) + 90, 0)
		body.add_child(armor)
	# Central rotating turret (visible chunky block)
	var turret := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.55, 0.32, 0.45); tm.material = mat_tank
	turret.mesh = tm
	turret.position = Vector3(0, 0.45, 0)
	body.add_child(turret)
	# Triple cannon array (3 barrels from turret)
	for i in 3:
		var off: float = (i - 1) * 0.12
		var barrel := MeshInstance3D.new()
		var brm := CylinderMesh.new()
		brm.top_radius = 0.06; brm.bottom_radius = 0.08; brm.height = 0.55
		brm.material = _mat_metal(Color(0.3, 0.15, 0.25))
		barrel.mesh = brm
		barrel.position = Vector3(0.45, 0.45, off)
		barrel.rotation_degrees = Vector3(0, 0, 90)
		body.add_child(barrel)
	# Red command eye on top
	var eye := MeshInstance3D.new()
	var esm := SphereMesh.new()
	esm.radius = 0.13; esm.height = 0.22
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(1, 0.15, 0.35)
	emat.emission_enabled = true
	emat.emission = Color(1, 0.15, 0.35)
	emat.emission_energy_multiplier = 5.5
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	esm.material = emat
	eye.mesh = esm
	eye.position = Vector3(0, 0.62, 0)
	body.add_child(eye)
	# 4 corner thruster pods
	for i in 4:
		var ang: float = (i / 4.0) * TAU + PI / 4
		var pod := MeshInstance3D.new()
		var pcm := CylinderMesh.new()
		pcm.top_radius = 0.13; pcm.bottom_radius = 0.16; pcm.height = 0.35
		pcm.material = _mat_metal(Color(0.45, 0.2, 0.4))
		pod.mesh = pcm
		pod.position = Vector3(cos(ang) * 0.75, -0.3, sin(ang) * 0.75)
		pod.rotation_degrees = Vector3(90, 0, 0)
		body.add_child(pod)
		# Engine glow at bottom of pod
		var glow := MeshInstance3D.new()
		var gsm := SphereMesh.new()
		gsm.radius = 0.13; gsm.height = 0.26
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(1, 0.35, 0.7)
		gmat.emission_enabled = true
		gmat.emission = Color(1, 0.35, 0.7)
		gmat.emission_energy_multiplier = 4.5
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gsm.material = gmat
		glow.mesh = gsm
		glow.position = Vector3(cos(ang) * 0.75, -0.5, sin(ang) * 0.75)
		body.add_child(glow)
	# Antenna spikes on top corners
	for sign_v in [-1, 1]:
		var ant := MeshInstance3D.new()
		var acm := CylinderMesh.new()
		acm.top_radius = 0.015; acm.bottom_radius = 0.04; acm.height = 0.4
		acm.material = _mat_metal(Color(0.5, 0.25, 0.45))
		ant.mesh = acm
		ant.position = Vector3(-0.35, 0.55, sign_v * 0.25)
		body.add_child(ant)

func _build_enemy_boss(body: Node3D) -> void:
	# Massive dreadnought: layered spine + command tower + 6 weapon arms + ring + multiple engines
	# Lower hull (large flat plate)
	var lower := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(2.4, 0.4, 1.5); lm.material = _mat_metal(Color(0.5, 0.2, 0.55))
	lower.mesh = lm
	lower.position = Vector3(0, -0.25, 0)
	body.add_child(lower)
	# Mid spine
	var spine := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(2.6, 0.55, 1.0); sm.material = mat_boss
	spine.mesh = sm
	body.add_child(spine)
	# Upper command tower (3-tier)
	var tower1 := MeshInstance3D.new()
	var t1m := BoxMesh.new()
	t1m.size = Vector3(1.4, 0.3, 0.7); t1m.material = _mat_metal(Color(0.7, 0.3, 0.7))
	tower1.mesh = t1m
	tower1.position = Vector3(0.1, 0.4, 0)
	body.add_child(tower1)
	var tower2 := MeshInstance3D.new()
	var t2m := BoxMesh.new()
	t2m.size = Vector3(0.9, 0.35, 0.55); t2m.material = mat_boss
	tower2.mesh = t2m
	tower2.position = Vector3(0.25, 0.72, 0)
	body.add_child(tower2)
	# Bridge dome (glowing brain)
	var dome := MeshInstance3D.new()
	var dsm := SphereMesh.new()
	dsm.radius = 0.32; dsm.height = 0.5
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.12, 0.05, 0.18)
	dmat.emission_enabled = true
	dmat.emission = Color(1, 0.3, 1)
	dmat.emission_energy_multiplier = 4.0
	dmat.metallic = 0.95; dmat.roughness = 0.05
	dsm.material = dmat
	dome.mesh = dsm
	dome.position = Vector3(0.4, 0.95, 0)
	body.add_child(dome)
	# Bridge "eye" beam center
	var eye := MeshInstance3D.new()
	var esm := SphereMesh.new()
	esm.radius = 0.12; esm.height = 0.2
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(1, 0.4, 1)
	emat.emission_enabled = true
	emat.emission = Color(1, 0.4, 1)
	emat.emission_energy_multiplier = 6.5
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	esm.material = emat
	eye.mesh = esm
	eye.position = Vector3(0.65, 0.95, 0)
	body.add_child(eye)
	# 6 weapon arms (3 per side)
	var arm_offsets := [Vector3(0.7, 0, 0), Vector3(-0.1, 0, 0), Vector3(-0.6, 0, 0)]
	for sign_v in [-1, 1]:
		for arm_pos in arm_offsets:
			var arm := MeshInstance3D.new()
			var am := BoxMesh.new()
			am.size = Vector3(0.55, 0.2, 0.4); am.material = mat_boss
			arm.mesh = am
			arm.position = Vector3(arm_pos.x, -0.05, sign_v * 0.85)
			body.add_child(arm)
			# Twin barrel on this arm
			for off in [-0.07, 0.07]:
				var barrel := MeshInstance3D.new()
				var brm := CylinderMesh.new()
				brm.top_radius = 0.04; brm.bottom_radius = 0.06; brm.height = 0.4
				brm.material = _mat_metal(Color(0.3, 0.1, 0.3))
				barrel.mesh = brm
				barrel.position = Vector3(arm_pos.x + 0.4, -0.05, sign_v * 0.85 + off)
				barrel.rotation_degrees = Vector3(0, 0, 90)
				body.add_child(barrel)
	# Side wing extensions (2 per side)
	for sign_v in [-1, 1]:
		var wing := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(1.7, 0.18, 0.4); wm.material = _mat_metal(Color(0.55, 0.22, 0.55))
		wing.mesh = wm
		wing.position = Vector3(-0.15, 0.05, sign_v * 1.15)
		body.add_child(wing)
		# Wing tip cone glow
		var tip := MeshInstance3D.new()
		var tsm := SphereMesh.new()
		tsm.radius = 0.16; tsm.height = 0.32
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(1, 0.3, 1)
		tmat.emission_enabled = true
		tmat.emission = Color(1, 0.3, 1)
		tmat.emission_energy_multiplier = 5.0
		tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tsm.material = tmat
		tip.mesh = tsm
		tip.position = Vector3(-1.0, 0.05, sign_v * 1.35)
		body.add_child(tip)
	# 3 central main engines at rear
	for off in [-0.4, 0, 0.4]:
		var ring := MeshInstance3D.new()
		var rcm := CylinderMesh.new()
		rcm.top_radius = 0.22; rcm.bottom_radius = 0.18; rcm.height = 0.25
		rcm.material = _mat_metal(Color(0.3, 0.15, 0.35))
		ring.mesh = rcm
		ring.position = Vector3(-1.3, 0, off)
		ring.rotation_degrees = Vector3(0, 0, 90)
		body.add_child(ring)
		var glow := MeshInstance3D.new()
		var gsm := SphereMesh.new()
		gsm.radius = 0.2; gsm.height = 0.4
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(1, 0.45, 1)
		gmat.emission_enabled = true
		gmat.emission = Color(1, 0.45, 1)
		gmat.emission_energy_multiplier = 5.5
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gsm.material = gmat
		glow.mesh = gsm
		glow.position = Vector3(-1.55, 0, off)
		body.add_child(glow)
	# Forward ramming spike
	var spike := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.45, 0.7, 0.45); pm.material = mat_boss
	spike.mesh = pm
	spike.position = Vector3(1.65, -0.05, 0)
	spike.rotation_degrees = Vector3(0, 0, -90)
	body.add_child(spike)
	# Dorsal antenna spire
	var spire := MeshInstance3D.new()
	var spm := CylinderMesh.new()
	spm.top_radius = 0.02; spm.bottom_radius = 0.06; spm.height = 0.8
	spm.material = mat_boss
	spire.mesh = spm
	spire.position = Vector3(-0.7, 0.85, 0)
	body.add_child(spire)
	var spire_tip := MeshInstance3D.new()
	var stsm := SphereMesh.new()
	stsm.radius = 0.08; stsm.height = 0.16
	var stmat := StandardMaterial3D.new()
	stmat.albedo_color = Color(1, 0.5, 1)
	stmat.emission_enabled = true
	stmat.emission = Color(1, 0.5, 1)
	stmat.emission_energy_multiplier = 5.5
	stmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stsm.material = stmat
	spire_tip.mesh = stsm
	spire_tip.position = Vector3(-0.7, 1.3, 0)
	body.add_child(spire_tip)

# ============================================================
# Procedural enemy generation
# ============================================================

const PALETTES := [
	{"hull": Color(0.92, 0.42, 0.32), "eye": Color(1.0, 0.3, 0.2),  "engine": Color(1.0, 0.5, 0.25), "name": "rot"},
	{"hull": Color(1.0, 0.7, 0.25),   "eye": Color(1.0, 0.9, 0.3),  "engine": Color(1.0, 0.55, 0.2), "name": "amber"},
	{"hull": Color(0.85, 0.35, 0.7),  "eye": Color(1.0, 0.4, 0.85), "engine": Color(1.0, 0.35, 0.95),"name": "rosa"},
	{"hull": Color(0.55, 0.3, 0.85),  "eye": Color(0.8, 0.5, 1.0),  "engine": Color(0.7, 0.4, 1.0),  "name": "violett"},
	{"hull": Color(0.4, 0.85, 0.5),   "eye": Color(0.6, 1.0, 0.4),  "engine": Color(0.5, 1.0, 0.7),  "name": "toxic"},
	{"hull": Color(0.4, 0.75, 0.9),   "eye": Color(0.6, 1.0, 1.0),  "engine": Color(0.5, 0.95, 1.0), "name": "eis"},
	{"hull": Color(0.78, 0.78, 0.85), "eye": Color(1.0, 0.9, 0.7),  "engine": Color(1.0, 0.8, 0.6),  "name": "asche"},
	{"hull": Color(0.4, 0.5, 0.65),   "eye": Color(0.5, 0.95, 1.0), "engine": Color(0.6, 0.85, 1.0), "name": "stahl"},
]

const HULL_SHAPES := ["box", "elongated", "hex", "diamond", "sphere", "twin", "stacked"]
const WING_TYPES := ["none", "swept", "back_swept", "delta", "x_pattern", "small_fins"]
const WEAPON_TYPES := ["none", "single", "twin", "triple", "pod_array", "missile_rack", "turret_array", "boss_arms"]

# ============================================================
# Modular PLAYER ship design (cosmetic for now — see memory project_ship_builder).
# Keys are JSON-safe primitives (int index / stable string ids) so the design
# saves to settings.cfg and syncs over the net trivially. The mesh builder
# (_assemble_ship_body) reads the member `ship_design`; the editor (STATE_SHIPYARD)
# cycles these options and rebuilds the ship live.
# ============================================================
const SHIP_PALETTES := [
	{"name": "Tarnung", "hull": Color(0.22, 0.27, 0.36), "accent": Color(0.42, 0.55, 0.78), "glow": Color(0.35, 0.80, 1.00), "engine": Color(0.55, 0.85, 1.00)},
	{"name": "Inferno", "hull": Color(0.30, 0.10, 0.10), "accent": Color(0.70, 0.25, 0.15), "glow": Color(1.00, 0.45, 0.15), "engine": Color(1.00, 0.50, 0.20)},
	{"name": "Toxisch", "hull": Color(0.16, 0.28, 0.16), "accent": Color(0.45, 0.70, 0.25), "glow": Color(0.55, 1.00, 0.30), "engine": Color(0.60, 1.00, 0.40)},
	{"name": "Plasma", "hull": Color(0.24, 0.16, 0.34), "accent": Color(0.60, 0.40, 0.85), "glow": Color(0.80, 0.40, 1.00), "engine": Color(0.75, 0.45, 1.00)},
	{"name": "Gold", "hull": Color(0.30, 0.24, 0.12), "accent": Color(0.80, 0.65, 0.30), "glow": Color(1.00, 0.85, 0.40), "engine": Color(1.00, 0.80, 0.45)},
	{"name": "Arktis", "hull": Color(0.50, 0.58, 0.68), "accent": Color(0.75, 0.85, 0.95), "glow": Color(0.70, 0.95, 1.00), "engine": Color(0.80, 0.95, 1.00)},
]
const SHIP_WING_OPTS := ["swept", "delta", "long", "none"]
const SHIP_WING_LABELS := {"swept": "Pfeilflügel", "delta": "Delta", "long": "Lang", "none": "Keine"}
const SHIP_ENGINE_OPTS := [1, 2, 3]
const SHIP_TAIL_OPTS := ["twin", "single", "none"]
const SHIP_TAIL_LABELS := {"twin": "Doppel", "single": "Einzel", "none": "Keins"}
const SHIP_NOSE_OPTS := ["pointed", "blunt", "blade"]
const SHIP_NOSE_LABELS := {"pointed": "Spitz", "blunt": "Stumpf", "blade": "Klinge"}
# LED accent for the glowing edge strips + console. "auto" = follow the palette glow.
const SHIP_LED_OPTS := ["auto", "cyan", "red", "green", "violet", "gold", "white"]
const SHIP_LED_LABELS := {"auto": "Auto", "cyan": "Cyan", "red": "Rot", "green": "Grün", "violet": "Violett", "gold": "Gold", "white": "Weiß"}
const SHIP_LED_COLORS := {
	"cyan": Color(0.35, 0.80, 1.00),
	"red": Color(1.00, 0.30, 0.25),
	"green": Color(0.50, 1.00, 0.40),
	"violet": Color(0.80, 0.40, 1.00),
	"gold": Color(1.00, 0.85, 0.40),
	"white": Color(0.85, 0.95, 1.00),
}
# Editor rows, in display order. Adding a new designable part = add a row here +
# a builder branch + a cycle/label case (kept data-driven so it stays trivial).
const SHIPYARD_ROWS := [
	{"key": "palette", "label": "Farbschema"},
	{"key": "wings", "label": "Flügel"},
	{"key": "engines", "label": "Triebwerke"},
	{"key": "tail", "label": "Leitwerk"},
	{"key": "nose", "label": "Nase"},
	{"key": "leds", "label": "LED-Farbe"},
]
const DEFAULT_SHIP_DESIGN := {
	"palette": 0,
	"wings": "swept",
	"engines": 2,
	"tail": "twin",
	"nose": "pointed",
	"leds": "auto",
}

# ============================================================
# Social — emote wheel (hold ALT) + chat (Enter). Both relay through the server
# like designs: submit_* (client→server) → receive_* (server→all clients).
# ============================================================
const EMOTES := ["👍", "❤️", "😂", "😮", "😢", "😡", "🆘", "👋"]
const EMOTE_DURATION := 5.0                 # seconds the billboard floats above the ship
const EMOTE_OFFSET := Vector3(0, 1.3, 2.0)  # above + toward camera, in world units
const CHAT_MAX_LINES := 8                   # messages shown in the log
const CHAT_HISTORY := 30                    # messages kept
const CHAT_MAX_LEN := 120

# ============================================================
# World events — hidden, procedurally-placed encounters found via the radar.
# First type: the Mega-Boss (B), a 5x boss that lurks far away until reached.
# Implemented as a flagged enemy so it reuses the whole enemy net/spawn pipeline.
# ============================================================
const MEGA_MIN_LEVEL := 6                   # party level before mega events can appear
const MEGA_INTERVAL_MIN := 80.0             # seconds between mega events
const MEGA_INTERVAL_MAX := 150.0
const MEGA_SPAWN_MIN := 110.0               # how far from a player it hides (well beyond radar)
const MEGA_SPAWN_MAX := 165.0
const MEGA_DETECT := 220.0                  # radar reveals it within this range (hidden beyond)
const MEGA_WAKE := 75.0                     # stays dormant until a player is this close
const MEGA_SCALE := 5.0                     # 5x size vs a normal boss (visual)
const MEGA_HP_MULT := 60                    # HP vs a normal boss — high, since its huge
                                            # radius lets piercing shots multi-hit it hard
const MEGA_DAMAGE := 45                     # contact/shot damage (threatening, not instakill)
const MEGA_GEMS := 40                       # loot shower on kill

# Event A — Rescue Escort: a friendly bot pinned down by marked shooters. Clear
# them before the timer runs out or the bot dies → loot.
const ESCORT_MIN_LEVEL := 4
const ESCORT_SPAWN_MIN := 95.0
const ESCORT_SPAWN_MAX := 150.0
const ESCORT_DETECT := 220.0                # radar reveal range for the bot
const ESCORT_BOT_HP := 700                  # bot HP (drained by the markers' fire)
const ESCORT_TIME := 50.0                   # seconds to clear the markers
const ESCORT_MARKERS := 6                   # number of marked shooters
const ESCORT_GEMS := 30                     # loot shower on success
# Shared event cadence (one world event — mega OR escort — at a time).
const EVENT_INTERVAL_MIN := 80.0
const EVENT_INTERVAL_MAX := 150.0

func _make_proc_hull_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.85
	m.roughness = 0.32
	m.metallic_specular = 0.6
	# Very subtle emission so unlit side isn't pitch black
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.08
	return m

func _make_proc_glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _generate_enemy_dna(role: String, level: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = randi()
	var dna := {"role": role, "level": level}
	var pal_idx: int = (level / 2 + rng.randi() % 2) % PALETTES.size()
	dna["palette"] = PALETTES[pal_idx]
	var size_mult: float = 1.0
	var hull_opts: Array = ["box"]
	var wing_opts: Array = ["none"]
	var weapon_opts: Array = ["none"]
	var eng_count: int = 1
	var detail: int = 1
	match role:
		"drone":
			size_mult = rng.randf_range(0.45, 0.6)
			hull_opts = ["box", "diamond", "hex", "sphere"]
			wing_opts = ["none", "swept", "small_fins"]
			eng_count = rng.randi_range(1, 4)
			detail = 1
		"shooter":
			size_mult = rng.randf_range(0.6, 0.75)
			hull_opts = ["box", "elongated", "twin", "stacked"]
			wing_opts = ["swept", "back_swept", "delta", "small_fins"]
			weapon_opts = ["single", "twin", "pod_array"]
			eng_count = rng.randi_range(2, 3)
			detail = 2
		"tank":
			size_mult = rng.randf_range(0.95, 1.2)
			hull_opts = ["box", "hex", "stacked"]
			wing_opts = ["none", "small_fins"]
			weapon_opts = ["twin", "triple", "missile_rack", "turret_array"]
			eng_count = rng.randi_range(2, 4)
			detail = 3
		"boss":
			size_mult = rng.randf_range(1.5, 2.1)
			hull_opts = ["elongated", "stacked", "twin"]
			wing_opts = ["swept", "x_pattern", "delta"]
			weapon_opts = ["triple", "missile_rack", "turret_array", "boss_arms"]
			eng_count = rng.randi_range(3, 5)
			detail = 5
	size_mult *= 1.0 + (level - 1) * 0.025
	dna["size_mult"] = size_mult
	dna["hull_shape"] = hull_opts[rng.randi() % hull_opts.size()]
	dna["wing_type"] = wing_opts[rng.randi() % wing_opts.size()]
	dna["weapon_type"] = weapon_opts[rng.randi() % weapon_opts.size()]
	dna["engine_count"] = eng_count
	dna["detail_density"] = detail
	dna["eye_count"] = 1 + (1 if rng.randf() < 0.45 else 0) + (level / 4)
	dna["has_dome"] = (role == "boss") or (role == "tank" and rng.randf() < 0.5) or (role == "shooter" and rng.randf() < 0.3)
	dna["antenna_count"] = rng.randi_range(0, 1 + detail)
	dna["spike_count"] = 0 if role == "drone" else rng.randi() % 8
	dna["height_layers"] = rng.randi_range(1, 3) if detail >= 2 else 1
	dna["armor_count"] = rng.randi() % (detail + 1)
	return dna

func _build_procedural_enemy(dna: Dictionary) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(body)
	var pal: Dictionary = dna["palette"]
	var hull_col: Color = pal["hull"]
	var eye_col: Color = pal["eye"]
	var eng_col: Color = pal["engine"]
	var s: float = dna["size_mult"]
	var hull_mat := _make_proc_hull_mat(hull_col)
	var dark_mat := _make_proc_hull_mat(hull_col.darkened(0.35))
	var eye_mat := _make_proc_glow_mat(eye_col, 5.5)
	var eng_mat := _make_proc_glow_mat(eng_col, 4.5)
	var extents: Vector3 = _build_proc_hull(body, dna["hull_shape"], s, hull_mat, dark_mat, dna["height_layers"])
	if dna["wing_type"] != "none":
		_build_proc_wings(body, dna["wing_type"], extents, s, hull_mat, eye_col)
	if dna["weapon_type"] != "none":
		_build_proc_weapons(body, dna["weapon_type"], extents, s, hull_mat, dark_mat, eye_mat)
	_build_proc_engines(body, dna["engine_count"], extents, s, dark_mat, eng_mat)
	_build_proc_eyes(body, dna["eye_count"], extents, s, eye_mat)
	if dna["has_dome"]:
		_build_proc_dome(body, extents, s, hull_col, eye_col)
	for i in dna["antenna_count"]:
		_build_proc_antenna(body, i, dna["antenna_count"], extents, s, dark_mat, eye_mat)
	if dna["spike_count"] > 0:
		_build_proc_spikes(body, dna["spike_count"], extents, s, hull_mat)
	for i in dna["armor_count"]:
		_build_proc_armor(body, i, dna["armor_count"], extents, s, hull_col)
	# Bigger enemies emit a tinted point light from their eyes/engines so the
	# player ship gets lit when one approaches. Small drones stay light-free to
	# keep total light count manageable.
	if s >= 1.05:
		var el := OmniLight3D.new()
		el.light_color = eye_col
		el.light_energy = 1.4 + (s - 1.0) * 2.0
		el.omni_range = 4.0 + s * 2.0
		el.omni_attenuation = 1.6
		root.add_child(el)
	return root

func _build_proc_hull(body: Node3D, shape: String, s: float, hull_mat: StandardMaterial3D, dark_mat: StandardMaterial3D, layers: int) -> Vector3:
	match shape:
		"box":
			var size := Vector3(0.9, 0.35, 0.7) * s
			var h := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = size; bm.material = hull_mat
			h.mesh = bm
			body.add_child(h)
			return size * 0.5
		"elongated":
			var size := Vector3(1.4, 0.32, 0.6) * s
			var h := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = size; bm.material = hull_mat
			h.mesh = bm
			body.add_child(h)
			# Mid spine accent
			var spine := MeshInstance3D.new()
			var sbm := BoxMesh.new(); sbm.size = Vector3(size.x * 0.8, size.y * 0.5, size.z * 0.3); sbm.material = dark_mat
			spine.mesh = sbm; spine.position = Vector3(0, size.y * 0.55, 0)
			body.add_child(spine)
			return size * 0.5
		"hex":
			var radius := 0.55 * s
			var height := 0.4 * s
			var h := MeshInstance3D.new()
			var cm := CylinderMesh.new(); cm.top_radius = radius; cm.bottom_radius = radius * 1.1; cm.height = height; cm.radial_segments = 6
			cm.material = hull_mat
			h.mesh = cm
			body.add_child(h)
			return Vector3(radius * 1.1, height * 0.5, radius * 1.1)
		"diamond":
			var size := Vector3(0.85, 0.4, 0.7) * s
			var top := MeshInstance3D.new()
			var tpm := PrismMesh.new(); tpm.size = size; tpm.material = hull_mat
			top.mesh = tpm
			body.add_child(top)
			# Mirror bottom prism for full diamond
			var bot := MeshInstance3D.new()
			var bpm := PrismMesh.new(); bpm.size = size; bpm.material = hull_mat
			bot.mesh = bpm; bot.rotation_degrees = Vector3(180, 0, 0)
			body.add_child(bot)
			return size * 0.5
		"sphere":
			var radius := 0.45 * s
			var h := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = radius; sm.height = radius * 2
			sm.material = hull_mat
			h.mesh = sm
			body.add_child(h)
			return Vector3(radius, radius, radius)
		"twin":
			var size := Vector3(0.7, 0.3, 0.35) * s
			for sign_v in [-1, 1]:
				var h := MeshInstance3D.new()
				var bm := BoxMesh.new(); bm.size = size; bm.material = hull_mat
				h.mesh = bm; h.position = Vector3(0, 0, sign_v * size.z * 1.05)
				body.add_child(h)
			# Connecting bridge
			var bridge := MeshInstance3D.new()
			var bbm := BoxMesh.new(); bbm.size = Vector3(size.x * 0.6, size.y * 0.5, size.z * 2.0); bbm.material = dark_mat
			bridge.mesh = bbm
			body.add_child(bridge)
			return Vector3(size.x * 0.5, size.y * 0.5, size.z * 1.5)
		"stacked":
			var w := 0.7 * s
			var d := 0.55 * s
			var tot_h := 0.0
			for i in maxi(1, layers):
				var layer_h := (0.3 - i * 0.04) * s
				var layer_w := w * (1.0 - i * 0.15)
				var layer_d := d * (1.0 - i * 0.15)
				var h := MeshInstance3D.new()
				var bm := BoxMesh.new(); bm.size = Vector3(layer_w, layer_h, layer_d); bm.material = hull_mat if i % 2 == 0 else dark_mat
				h.mesh = bm
				h.position = Vector3(0, tot_h + layer_h * 0.5, 0)
				body.add_child(h)
				tot_h += layer_h
			return Vector3(w * 0.5, tot_h * 0.5, d * 0.5)
	return Vector3(0.4, 0.2, 0.35) * s

func _build_proc_wings(body: Node3D, wing_type: String, ext: Vector3, s: float, hull_mat: StandardMaterial3D, eye_col: Color) -> void:
	var tip_mat := _make_proc_glow_mat(eye_col, 4.0)
	match wing_type:
		"swept":
			for sign_v in [-1, 1]:
				var w := MeshInstance3D.new()
				var bm := BoxMesh.new(); bm.size = Vector3(0.5 * s, 0.06 * s, 0.5 * s); bm.material = hull_mat
				w.mesh = bm
				w.position = Vector3(-ext.x * 0.3, 0, sign_v * (ext.z + 0.25 * s))
				w.rotation_degrees = Vector3(0, sign_v * 20, 0)
				body.add_child(w)
				_add_wing_tip(body, w.position + Vector3(-0.18 * s, 0, sign_v * 0.18 * s), 0.05 * s, tip_mat)
		"back_swept":
			for sign_v in [-1, 1]:
				var w := MeshInstance3D.new()
				var bm := BoxMesh.new(); bm.size = Vector3(0.45 * s, 0.06 * s, 0.55 * s); bm.material = hull_mat
				w.mesh = bm
				w.position = Vector3(ext.x * 0.2, 0, sign_v * (ext.z + 0.28 * s))
				w.rotation_degrees = Vector3(0, sign_v * -22, 0)
				body.add_child(w)
				_add_wing_tip(body, w.position + Vector3(0.18 * s, 0, sign_v * 0.18 * s), 0.05 * s, tip_mat)
		"delta":
			for sign_v in [-1, 1]:
				var w := MeshInstance3D.new()
				var pm := PrismMesh.new(); pm.size = Vector3(0.6 * s, 0.55 * s, 0.06 * s); pm.material = hull_mat
				w.mesh = pm
				w.position = Vector3(-ext.x * 0.4, 0, sign_v * (ext.z + 0.3 * s))
				w.rotation_degrees = Vector3(90, sign_v * 25, 0)
				body.add_child(w)
		"x_pattern":
			for diag in [Vector2(1,1), Vector2(1,-1), Vector2(-1,1), Vector2(-1,-1)]:
				var w := MeshInstance3D.new()
				var bm := BoxMesh.new(); bm.size = Vector3(0.55 * s, 0.06 * s, 0.4 * s); bm.material = hull_mat
				w.mesh = bm
				w.position = Vector3(diag.x * ext.x * 0.5, 0, diag.y * (ext.z + 0.2 * s))
				w.rotation_degrees = Vector3(0, rad_to_deg(atan2(diag.y, diag.x)) - (90 if diag.x > 0 else -90), 0)
				body.add_child(w)
				_add_wing_tip(body, w.position + Vector3(0, 0, diag.y * 0.12 * s), 0.05 * s, tip_mat)
		"small_fins":
			for sign_v in [-1, 1]:
				var f := MeshInstance3D.new()
				var pm := PrismMesh.new(); pm.size = Vector3(0.22 * s, 0.18 * s, 0.04 * s); pm.material = hull_mat
				f.mesh = pm
				f.position = Vector3(-ext.x * 0.4, ext.y * 0.6, sign_v * ext.z * 0.5)
				f.rotation_degrees = Vector3(0, sign_v * 25, 0)
				body.add_child(f)

func _add_wing_tip(body: Node3D, pos: Vector3, r: float, mat: StandardMaterial3D) -> void:
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2
	sm.material = mat
	tip.mesh = sm
	tip.position = pos
	body.add_child(tip)

func _build_proc_weapons(body: Node3D, wtype: String, ext: Vector3, s: float, hull_mat: StandardMaterial3D, dark_mat: StandardMaterial3D, glow_mat: StandardMaterial3D) -> void:
	match wtype:
		"single":
			_add_barrel(body, Vector3(ext.x + 0.3 * s, ext.y * 0.5, 0), 0.4 * s, 0.07 * s, dark_mat, glow_mat)
		"twin":
			for sign_v in [-1, 1]:
				_add_barrel(body, Vector3(ext.x + 0.25 * s, 0, sign_v * ext.z * 0.45), 0.4 * s, 0.06 * s, dark_mat, glow_mat)
		"triple":
			for off in [-0.18 * s, 0, 0.18 * s]:
				_add_barrel(body, Vector3(ext.x + 0.3 * s, ext.y * 0.4, off), 0.5 * s, 0.06 * s, dark_mat, glow_mat)
		"pod_array":
			for sign_v in [-1, 1]:
				var pod := MeshInstance3D.new()
				var bm := BoxMesh.new(); bm.size = Vector3(0.22 * s, 0.12 * s, 0.18 * s); bm.material = dark_mat
				pod.mesh = bm
				pod.position = Vector3(ext.x * 0.4, -ext.y * 0.4, sign_v * ext.z * 1.2)
				body.add_child(pod)
				_add_barrel(body, Vector3(ext.x * 0.4 + 0.3 * s, -ext.y * 0.4, sign_v * ext.z * 1.2), 0.32 * s, 0.045 * s, dark_mat, glow_mat)
		"missile_rack":
			for sign_v in [-1, 1]:
				for i in 3:
					var off: float = (i - 1) * 0.1 * s
					var rocket := MeshInstance3D.new()
					var cm := CylinderMesh.new(); cm.top_radius = 0.05 * s; cm.bottom_radius = 0.05 * s; cm.height = 0.35 * s
					cm.material = dark_mat
					rocket.mesh = cm
					rocket.position = Vector3(ext.x * 0.2, ext.y * 0.4, sign_v * (ext.z + 0.08 * s) + off)
					rocket.rotation_degrees = Vector3(0, 0, 90)
					body.add_child(rocket)
		"turret_array":
			for sign_v in [-1, 1]:
				var turret := MeshInstance3D.new()
				var bm := BoxMesh.new(); bm.size = Vector3(0.3 * s, 0.18 * s, 0.28 * s); bm.material = hull_mat
				turret.mesh = bm
				turret.position = Vector3(ext.x * 0.2, ext.y + 0.15 * s, sign_v * ext.z * 0.6)
				body.add_child(turret)
				_add_barrel(body, turret.position + Vector3(0.28 * s, 0, 0), 0.4 * s, 0.05 * s, dark_mat, glow_mat)
		"boss_arms":
			# 6 long weapon arms
			for sign_v in [-1, 1]:
				for arm_off in [0.5 * s, -0.05 * s, -0.55 * s]:
					var arm := MeshInstance3D.new()
					var bm := BoxMesh.new(); bm.size = Vector3(0.5 * s, 0.18 * s, 0.35 * s); bm.material = hull_mat
					arm.mesh = bm
					arm.position = Vector3(arm_off, 0, sign_v * (ext.z + 0.3 * s))
					body.add_child(arm)
					# twin barrel
					for off2 in [-0.08 * s, 0.08 * s]:
						_add_barrel(body, Vector3(arm_off + 0.35 * s, 0, sign_v * (ext.z + 0.3 * s) + off2), 0.32 * s, 0.04 * s, dark_mat, glow_mat)

func _add_barrel(body: Node3D, pos: Vector3, length: float, radius: float, dark_mat: StandardMaterial3D, glow_mat: StandardMaterial3D) -> void:
	var barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = radius * 0.85; cm.bottom_radius = radius; cm.height = length
	cm.material = dark_mat
	barrel.mesh = cm
	barrel.position = pos
	barrel.rotation_degrees = Vector3(0, 0, 90)
	body.add_child(barrel)
	# Muzzle tip glow
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = radius * 1.1; sm.height = radius * 2.2
	sm.material = glow_mat
	tip.mesh = sm
	tip.position = pos + Vector3(length * 0.55, 0, 0)
	body.add_child(tip)

func _build_proc_engines(body: Node3D, count: int, ext: Vector3, s: float, dark_mat: StandardMaterial3D, glow_mat: StandardMaterial3D) -> void:
	if count <= 0:
		return
	if count == 1:
		_add_engine(body, Vector3(-ext.x - 0.15 * s, 0, 0), 0.22 * s, dark_mat, glow_mat)
	elif count == 2:
		for sign_v in [-1, 1]:
			_add_engine(body, Vector3(-ext.x - 0.12 * s, 0, sign_v * ext.z * 0.5), 0.18 * s, dark_mat, glow_mat)
	elif count == 3:
		_add_engine(body, Vector3(-ext.x - 0.18 * s, 0, 0), 0.22 * s, dark_mat, glow_mat)
		for sign_v in [-1, 1]:
			_add_engine(body, Vector3(-ext.x - 0.1 * s, 0, sign_v * ext.z * 0.7), 0.15 * s, dark_mat, glow_mat)
	elif count >= 4:
		for i in count:
			var ang: float = (i / float(count)) * TAU
			_add_engine(body, Vector3(-ext.x - 0.08 * s, cos(ang) * ext.y * 0.6, sin(ang) * ext.z * 0.6), 0.13 * s, dark_mat, glow_mat)

func _add_engine(body: Node3D, pos: Vector3, r: float, dark_mat: StandardMaterial3D, glow_mat: StandardMaterial3D) -> void:
	# Housing ring
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = r * 1.1; cm.bottom_radius = r * 0.9; cm.height = r * 1.2
	cm.material = dark_mat
	ring.mesh = cm
	ring.position = pos + Vector3(-r * 0.3, 0, 0)
	ring.rotation_degrees = Vector3(0, 0, 90)
	body.add_child(ring)
	# Glow ball
	var g := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2
	sm.material = glow_mat
	g.mesh = sm
	g.position = pos
	body.add_child(g)

func _build_proc_eyes(body: Node3D, count: int, ext: Vector3, s: float, mat: StandardMaterial3D) -> void:
	if count == 1:
		var eye := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 0.13 * s; sm.height = 0.22 * s
		sm.material = mat
		eye.mesh = sm
		eye.position = Vector3(ext.x * 0.85, ext.y * 0.5, 0)
		body.add_child(eye)
	else:
		for i in count:
			var t: float = (i + 0.5) / count
			var off: float = (t - 0.5) * ext.z * 1.4
			var eye := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 0.09 * s; sm.height = 0.18 * s
			sm.material = mat
			eye.mesh = sm
			eye.position = Vector3(ext.x * 0.8, ext.y * 0.4, off)
			body.add_child(eye)

func _build_proc_dome(body: Node3D, ext: Vector3, s: float, hull_col: Color, eye_col: Color) -> void:
	var dome_mat := StandardMaterial3D.new()
	dome_mat.albedo_color = hull_col.darkened(0.6)
	dome_mat.metallic = 0.95
	dome_mat.roughness = 0.08
	dome_mat.emission_enabled = true
	dome_mat.emission = eye_col
	dome_mat.emission_energy_multiplier = 2.0
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = ext.x * 0.4; sm.height = ext.x * 0.6
	sm.material = dome_mat
	dome.mesh = sm
	dome.position = Vector3(ext.x * 0.1, ext.y + sm.radius * 0.6, 0)
	body.add_child(dome)

func _build_proc_antenna(body: Node3D, i: int, total: int, ext: Vector3, s: float, dark_mat: StandardMaterial3D, glow_mat: StandardMaterial3D) -> void:
	var height: float = 0.3 * s + i * 0.05 * s
	var x_off: float = -ext.x * 0.5 + i * 0.18 * s
	var stalk := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.012 * s; cm.bottom_radius = 0.025 * s; cm.height = height
	cm.material = dark_mat
	stalk.mesh = cm
	stalk.position = Vector3(x_off, ext.y + height * 0.5, 0)
	body.add_child(stalk)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.04 * s; sm.height = 0.08 * s
	sm.material = glow_mat
	tip.mesh = sm
	tip.position = Vector3(x_off, ext.y + height, 0)
	body.add_child(tip)

func _build_proc_spikes(body: Node3D, count: int, ext: Vector3, s: float, mat: StandardMaterial3D) -> void:
	for i in count:
		var ang: float = (i / float(count)) * TAU
		var spike := MeshInstance3D.new()
		var pm := PrismMesh.new(); pm.size = Vector3(0.1 * s, 0.3 * s, 0.08 * s); pm.material = mat
		spike.mesh = pm
		spike.position = Vector3(cos(ang) * ext.x * 1.1, 0.05 * s, sin(ang) * ext.z * 1.1)
		spike.rotation_degrees = Vector3(0, rad_to_deg(ang) + 90, -90)
		body.add_child(spike)

func _build_proc_armor(body: Node3D, i: int, total: int, ext: Vector3, s: float, hull_col: Color) -> void:
	var armor_mat := StandardMaterial3D.new()
	armor_mat.albedo_color = hull_col.lerp(Color(0.3, 0.25, 0.2), 0.4)
	armor_mat.metallic = 0.4; armor_mat.roughness = 0.7
	var t: float = (i + 0.5) / total
	var side: int = -1 if i % 2 == 0 else 1
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(ext.x * 0.6, ext.y * 0.7, 0.1 * s); bm.material = armor_mat
	plate.mesh = bm
	plate.position = Vector3((t - 0.5) * ext.x * 0.6, 0, side * (ext.z + 0.06 * s))
	body.add_child(plate)

func _spawn_p_bullet(pos: Vector3, vel: Vector3) -> void:
	var b := Entity.new()
	b.type = "p_bullet"
	b.pos = pos
	b.vel = vel
	b.radius = PROJ_RADIUS
	b.damage = u_damage
	b.lifetime = PROJ_LIFETIME * u_range_mult
	b.pierce = u_pierce
	b.node = _make_player_laser_mesh(vel)
	b.node.position = pos
	world.add_child(b.node)
	p_bullets.append(b)

func _spawn_muzzle_flash(pos: Vector3, angle: float) -> void:
	# Bright unshaded sphere + a real OmniLight3D for a one-frame "lit by gunfire"
	# look on nearby ship parts. Both decay over ~0.08 s in _update_muzzle_flashes.
	var life: float = 0.09
	# Visible flash mesh (slightly elongated along firing direction)
	var flash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.65, 0.55, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.4)
	mat.emission_energy_multiplier = 9.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.material = mat
	flash.mesh = sm
	flash.position = pos + Vector3(cos(angle), sin(angle), 0) * 0.2
	world.add_child(flash)
	# Short-lived point light so nearby geometry lights up briefly
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.5)
	light.light_energy = 4.5
	light.omni_range = 4.0
	light.position = pos
	world.add_child(light)
	p_muzzle_lights.append({
		"light": light,
		"flash": flash,
		"mat": mat,
		"life": life,
		"life_max": life,
		"energy_max": 4.5,
		"emit_max": 9.0,
	})

func _spawn_e_bullet(pos: Vector3, vel: Vector3, dmg: int) -> void:
	var b := Entity.new()
	b.type = "e_bullet"
	b.pos = pos
	b.vel = vel
	b.radius = 0.15
	b.damage = dmg
	b.lifetime = 3.5
	if net_mode == NetMode.SERVER:
		b.net_id = _next_net_id()
		e_bullets.append(b)
		return
	b.node = _make_bullet_mesh(false)
	b.node.position = pos
	world.add_child(b.node)
	e_bullets.append(b)
	if enemy_shot_sfx != null:
		enemy_shot_sfx.play()

func _make_bullet_mesh(is_player: bool) -> Node3D:
	var root := Node3D.new()
	var inst := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = (PROJ_RADIUS if is_player else 0.12)
	sm.height = sm.radius * 2.0
	sm.material = mat_proj if is_player else mat_e_bullet
	inst.mesh = sm
	root.add_child(inst)
	# Glow halo
	var halo := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = sm.radius * 2.0
	hm.height = sm.radius * 4.0
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(1, 1, 1, 0.15)
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.emission_enabled = true
	hmat.emission = (COL_PROJ if is_player else COL_E_BULLET)
	hmat.emission_energy_multiplier = 1.8
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.material = hmat
	halo.mesh = hm
	root.add_child(halo)
	# Enemy bullet light — small purple glow that illuminates the ship as it
	# passes. Player bullets get their light in _make_player_laser_mesh.
	if not is_player:
		var l := OmniLight3D.new()
		l.light_color = COL_E_BULLET
		l.light_energy = 1.8
		l.omni_range = 3.5
		l.omni_attenuation = 1.7
		root.add_child(l)
	return root

func _make_player_laser_mesh(vel: Vector3) -> Node3D:
	# Elongated tracer-style laser bolt. Three layers stacked along the firing
	# direction: a thin bright core, a wider red halo, and a long faint trail
	# stretching backward so the projectile reads as a fast-moving streak.
	var root := Node3D.new()

	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = COL_LASER_CORE
	core_mat.emission_enabled = true
	core_mat.emission = COL_LASER_CORE
	core_mat.emission_energy_multiplier = 7.5
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var core := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.09
	cm.height = 1.4
	cm.material = core_mat
	core.mesh = cm
	root.add_child(core)

	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color = Color(COL_LASER.r, COL_LASER.g, COL_LASER.b, 0.45)
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.emission_enabled = true
	halo_mat.emission = COL_LASER
	halo_mat.emission_energy_multiplier = 3.5
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var halo := MeshInstance3D.new()
	var hm := CapsuleMesh.new()
	hm.radius = 0.22
	hm.height = 1.7
	hm.material = halo_mat
	halo.mesh = hm
	root.add_child(halo)

	# Long faint trail stretching backward — gives the tracer feel.
	# Sits behind the bullet (negative Y in capsule local space = "backward"
	# after the root rotation aligns +Y with velocity).
	var trail_mat := StandardMaterial3D.new()
	trail_mat.albedo_color = Color(COL_LASER.r, COL_LASER.g, COL_LASER.b, 0.22)
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.emission_enabled = true
	trail_mat.emission = COL_LASER
	trail_mat.emission_energy_multiplier = 2.2
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var trail := MeshInstance3D.new()
	var trm := CapsuleMesh.new()
	trm.radius = 0.14
	trm.height = 3.4
	trm.material = trail_mat
	trail.mesh = trm
	# Shift it back so it stretches "behind" the bullet, not symmetrically through it
	trail.position = Vector3(0, -1.5, 0)
	root.add_child(trail)

	# Travelling point light — the bolt itself illuminates the ship and any
	# nearby objects as it flies past. Small range to keep it cheap.
	var l := OmniLight3D.new()
	l.light_color = COL_LASER
	l.light_energy = 2.4
	l.omni_range = 4.5
	l.omni_attenuation = 1.8
	root.add_child(l)

	# CapsuleMesh extends along the Y axis. Rotate around Z so +Y aligns with
	# the velocity direction in the XY play plane.
	var ang: float = atan2(vel.y, vel.x) - PI * 0.5
	root.rotation = Vector3(0, 0, ang)
	return root

func _spawn_gem(pos: Vector3, value: int) -> void:
	var g := Entity.new()
	g.type = "gem"
	g.pos = pos
	g.vel = Vector3(randf_range(-2, 2), randf_range(-2, 2), 0)
	g.radius = 0.35
	g.value = value
	if net_mode == NetMode.SERVER:
		g.net_id = _next_net_id()
		gems.append(g)
		return
	g.node = _make_gem_mesh()
	g.node.position = pos
	world.add_child(g.node)
	gems.append(g)

func _make_gem_mesh() -> Node3D:
	var root := Node3D.new()
	var inst := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.45, 0.65, 0.45)
	pm.material = mat_gem
	inst.mesh = pm
	inst.rotation_degrees = Vector3(0, 0, 0)
	root.add_child(inst)
	# Mirror prism below
	var inst2 := MeshInstance3D.new()
	var pm2 := PrismMesh.new()
	pm2.size = Vector3(0.45, 0.65, 0.45)
	pm2.material = mat_gem
	inst2.mesh = pm2
	inst2.rotation_degrees = Vector3(0, 0, 180)
	root.add_child(inst2)
	# Gem light — small but very visible; piles of gems on the ground will
	# collectively light the area around them.
	var l := OmniLight3D.new()
	l.light_color = COL_XP
	l.light_energy = 1.4
	l.omni_range = 3.2
	l.omni_attenuation = 1.6
	root.add_child(l)
	return root

# ============================================================
# Auto-fire
# ============================================================

func _update_fire(delta: float) -> void:
	if chat_typing:
		return   # no auto-fire while typing in chat
	fire_timer -= delta
	if fire_timer > 0.0:
		return
	fire_timer = P_FIRE_RATE / u_fire_rate_mult
	# Auto-aim only fires when an enemy is roughly in front of the ship —
	# the player has to actively turn to bring targets into the cone.
	var target: Entity = _nearest_enemy_in_cone()
	if target == null:
		fire_timer = 0.12
		return
	var dir: Vector3 = (target.pos - p_pos).normalized()
	var n: int = u_projectiles
	var spread: float = deg_to_rad(u_spread_deg)
	var base_a: float = atan2(dir.y, dir.x)
	# Client: the server owns the authoritative bullets — send a fire command with
	# this player's stats and only render local muzzle flash + sound for feel.
	if net_mode == NetMode.CLIENT:
		fire_bullets.rpc_id(1, p_pos, base_a, n, u_spread_deg, u_damage, u_pierce, PROJ_LIFETIME * u_range_mult, PROJ_SPEED)
		for i in n:
			var ct: float = 0.5 if n == 1 else float(i) / float(n - 1)
			var coff: float = (ct - 0.5) * spread * (1.0 if n > 1 else 0.0)
			var ca: float = base_a + coff
			_spawn_muzzle_flash(p_pos + Vector3(cos(ca), sin(ca), 0) * 0.8, ca)
		if laser_sfx != null:
			laser_sfx.play()
			if u_projectiles > 1 and laser_sfx_echo != null:
				get_tree().create_timer(0.035).timeout.connect(
					func(): if laser_sfx_echo != null: laser_sfx_echo.play()
				)
		return
	for i in n:
		var t: float = 0.5 if n == 1 else float(i) / float(n - 1)
		var off: float = (t - 0.5) * spread * (1.0 if n > 1 else 0.0)
		var a: float = base_a + off
		var muzzle_pos: Vector3 = p_pos + Vector3(cos(a), sin(a), 0) * 0.8
		var bullet_vel: Vector3 = Vector3(cos(a), sin(a), 0) * PROJ_SPEED
		_spawn_p_bullet(muzzle_pos, bullet_vel)
		_spawn_muzzle_flash(muzzle_pos, a)
	if laser_sfx != null:
		laser_sfx.play()
		if u_projectiles > 1 and laser_sfx_echo != null:
			# 35 ms delayed quieter, slightly-detuned second pew → subtle "double" feel
			get_tree().create_timer(0.035).timeout.connect(
				func(): if laser_sfx_echo != null: laser_sfx_echo.play()
			)

func _nearest_enemy() -> Entity:
	var best: Entity = null
	var best_d: float = P_RANGE * u_range_mult
	for e in enemies:
		if e.dead:
			continue
		var d: float = e.pos.distance_to(p_pos)
		if d < best_d:
			best_d = d
			best = e
	return best

func _nearest_enemy_in_cone() -> Entity:
	# Like _nearest_enemy, but only considers enemies whose direction from the
	# player lies within FIRE_CONE_DEG of p_facing. Drives the new "ship must
	# point roughly at target before it fires" mechanic.
	var best: Entity = null
	var best_d: float = P_RANGE * u_range_mult
	var cone_cos: float = cos(deg_to_rad(FIRE_CONE_DEG))
	for e in enemies:
		if e.dead:
			continue
		var to_e: Vector3 = e.pos - p_pos
		var d: float = to_e.length()
		if d > best_d or d < 0.001:
			continue
		if to_e.normalized().dot(p_facing) < cone_cos:
			continue
		best_d = d
		best = e
	return best

# ============================================================
# Collisions
# ============================================================

func _resolve_collisions() -> void:
	for b in p_bullets:
		if b.dead:
			continue
		for e in enemies:
			if e.dead:
				continue
			if b.pos.distance_to(e.pos) <= b.radius + e.radius:
				e.hp -= b.damage
				e.hit_flash = 1.0
				if b.pierce > 0:
					b.pierce -= 1
				else:
					b.dead = true
				if e.hp <= 0:
					_kill_enemy(e)
				if b.dead:
					break

	# Enemy bullets vs the rescued bot (escort event) — independent of player i-frames.
	if escort_bot != null and not escort_bot.dead:
		for b in e_bullets:
			if b.dead:
				continue
			if b.pos.distance_to(escort_bot.pos) <= escort_bot.radius + b.radius:
				escort_bot.hp -= b.damage
				b.dead = true
				if escort_bot.hp <= 0:
					escort_bot.dead = true

	if p_invuln_timer <= 0.0:
		for b in e_bullets:
			if b.dead:
				continue
			if b.pos.distance_to(p_pos) <= P_RADIUS + b.radius:
				_player_take_damage(b.damage)
				b.dead = true
				if p_invuln_timer > 0.0:
					break

	if p_invuln_timer <= 0.0:
		for e in enemies:
			if e.dead:
				continue
			if e.pos.distance_to(p_pos) <= P_RADIUS + e.radius:
				_player_take_damage(e.damage)
				var push: Vector3 = (e.pos - p_pos).normalized() * 1.6
				e.pos += push
				break

func _kill_enemy(e: Entity, killer_id: int = -1) -> void:
	e.dead = true
	if net_mode == NetMode.SERVER:
		# Credit the kill to the player who fired the killing shot (per-player score).
		if killer_id >= 0 and net_states.has(killer_id):
			net_states[killer_id]["kills"] = int(net_states[killer_id].get("kills", 0)) + 1
	else:
		kills += 1
	var gem_count: int = 1
	if e.type == "shooter":
		gem_count = 2
	elif e.type == "tank":
		gem_count = 4
	elif e.type == "boss":
		gem_count = 12
	if e.is_mega:
		gem_count = MEGA_GEMS   # big loot shower for the hidden event
		_event_announce("💥 MEGA-BOSS BESIEGT — riesige Beute!")
	for i in gem_count:
		_spawn_gem(e.pos + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), 0), e.value)
	if net_mode == NetMode.SERVER:
		despawn_enemy.rpc(e.net_id)
		return
	_camera_shake(0.6 if e.type == "boss" else 0.18, 0.25 if e.type == "boss" else 0.1)

func _player_take_damage(dmg: int) -> void:
	p_hp -= dmg
	p_invuln_timer = P_INVULN
	_camera_shake(0.45, 0.2)
	if damage_sfx != null:
		damage_sfx.play()

func _check_lightning_strikes(delta: float) -> void:
	# When inside a storm nebula, periodic lightning strikes can hit the player.
	# Uses ellipsoid containment via the nebula's local transform (handles its
	# rotation and non-uniform scale automatically).
	for sn in storm_nebulae:
		sn["strike_timer"] -= delta
		if sn["strike_timer"] > 0.0:
			continue
		sn["strike_timer"] = randf_range(sn["interval_min"], sn["interval_max"])
		var node: Node3D = sn["node"]
		if not is_instance_valid(node):
			continue
		var local: Vector3 = node.to_local(Vector3(p_pos.x, p_pos.y, 0.0))
		if local.length() < sn["radius"]:
			# Visible bolt always plays — even during i-frames — so the player
			# sees the strike that's been counted.
			_spawn_lightning_bolt(Vector3(p_pos.x, p_pos.y, 0.0))
			if p_invuln_timer <= 0.0:
				_player_take_damage(int(sn["damage"]))
				_camera_shake(0.55, 0.18)
	_update_lightning_bolts(delta)

func _spawn_lightning_bolt(target_pos: Vector3) -> void:
	# Build a jagged emissive bolt from above the play plane down through the
	# target. Made of short box segments with random XY jitter between them so
	# the path looks fractal. A second pass with thicker, dimmer boxes forms a
	# glow halo around the bright core.
	if lightning_strike_sfx != null:
		lightning_strike_sfx.pitch_scale = randf_range(0.92, 1.08)
		lightning_strike_sfx.play()
	var root := Node3D.new()
	world.add_child(root)

	var start: Vector3 = target_pos + Vector3(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5), 32.0)
	var end: Vector3 = target_pos + Vector3(0, 0, -5.0)
	var n_segs: int = randi_range(10, 14)

	# Build a jittered path from start to end
	var path: Array[Vector3] = [start]
	for i in range(1, n_segs):
		var t: float = float(i) / float(n_segs)
		var base: Vector3 = start.lerp(end, t)
		# Wider jitter in middle, tightening as it approaches target
		var jitter_scale: float = (1.0 - abs(t - 0.5) * 1.8) * 1.4
		var jitter: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-0.4, 0.4)) * jitter_scale
		path.append(base + jitter)
	path.append(end)

	# Core (thin, very bright) and halo (thicker, dimmer) materials
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(1.0, 1.0, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.85, 0.92, 1.0)
	core_mat.emission_energy_multiplier = 12.0
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color = Color(0.6, 0.75, 1.0, 0.4)
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.emission_enabled = true
	halo_mat.emission = Color(0.5, 0.7, 1.0)
	halo_mat.emission_energy_multiplier = 5.0
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for i in range(path.size() - 1):
		_add_bolt_segment(root, path[i], path[i + 1], 0.12, core_mat)
		_add_bolt_segment(root, path[i], path[i + 1], 0.45, halo_mat)

	# Optional side branches off the main bolt
	var branch_count: int = randi_range(0, 2)
	for b in branch_count:
		var idx: int = randi_range(2, path.size() - 3)
		var branch_start: Vector3 = path[idx]
		var branch_dir: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), -randf_range(0.2, 0.7)).normalized()
		var branch_len: float = randf_range(2.5, 5.5)
		var branch_end: Vector3 = branch_start + branch_dir * branch_len
		var sub_segs: int = 4
		var prev: Vector3 = branch_start
		for s in range(1, sub_segs + 1):
			var t: float = float(s) / float(sub_segs)
			var bp: Vector3 = branch_start.lerp(branch_end, t) + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), 0)
			_add_bolt_segment(root, prev, bp, 0.08, core_mat)
			_add_bolt_segment(root, prev, bp, 0.3, halo_mat)
			prev = bp

	active_bolts.append({
		"root": root,
		"age": 0.0,
		"lifetime": randf_range(0.18, 0.28),
	})

func _add_bolt_segment(parent: Node3D, a: Vector3, b: Vector3, thickness: float, mat: Material) -> void:
	var len_v: float = (b - a).length()
	if len_v < 0.001:
		return
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thickness, thickness, len_v)
	bm.material = mat
	box.mesh = bm
	parent.add_child(box)
	box.position = (a + b) * 0.5
	var dir: Vector3 = (b - a).normalized()
	var up: Vector3 = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	# look_at points -Z at the target; aiming at `a` makes +Z point toward `b`
	# which matches the box's length axis.
	box.look_at(a, up)

func _update_lightning_bolts(delta: float) -> void:
	# Bolts pop bright then disappear — no fade animation, just lifetime cull.
	var i: int = active_bolts.size() - 1
	while i >= 0:
		var bolt = active_bolts[i]
		bolt["age"] += delta
		if bolt["age"] >= bolt["lifetime"]:
			if is_instance_valid(bolt["root"]):
				bolt["root"].queue_free()
			active_bolts.remove_at(i)
		i -= 1

# ============================================================
# Wave / level up
# ============================================================

func _update_wave(delta: float) -> void:
	wave_timer -= delta
	if wave_timer <= 0.0:
		_next_wave()

func _next_wave() -> void:
	wave += 1
	wave_timer = WAVE_DURATION
	spawn_interval = max(0.35, 1.5 - wave * 0.08)
	if wave % BOSS_EVERY == 0 and _party_level() >= BOSS_MIN_LEVEL:
		_spawn_boss_wave()

func _xp_for_next() -> int:
	return XP_BASE + (p_level - 1) * XP_INC + int(pow(p_level - 1, 1.5))

func _check_level_up() -> void:
	while p_xp >= _xp_for_next():
		p_xp -= _xp_for_next()
		p_level += 1
		_offer_levelup()
		return

func _offer_levelup() -> void:
	state = STATE_LEVELUP
	# Tell the server we're picking an upgrade so it keeps us invulnerable while the
	# world keeps simulating around us (co-op: no shared pause).
	if net_mode == NetMode.CLIENT:
		notify_busy.rpc_id(1, true)
	var pool := _upgrade_pool()
	pool.shuffle()
	var picks: Array = []
	while picks.size() < 3 and pool.size() > 0:
		picks.append(pool.pop_front())
	for i in levelup_buttons.size():
		var btn: Button = levelup_buttons[i]
		if i < picks.size():
			btn.visible = true
			btn.text = picks[i]["label"]
			btn.set_meta("upgrade", picks[i])
		else:
			btn.visible = false
	levelup_panel.visible = true

func _upgrade_pool() -> Array:
	return [
		{"id":"proj","label":"+1 Schuss pro Salve","apply":Callable(self, "_up_proj")},
		{"id":"rate","label":"+25% Feuerrate","apply":Callable(self, "_up_rate")},
		{"id":"dmg", "label":"+30% Schaden","apply":Callable(self, "_up_dmg")},
		{"id":"speed","label":"+15% Geschwindigkeit","apply":Callable(self, "_up_speed")},
		{"id":"range","label":"+25% Reichweite","apply":Callable(self, "_up_range")},
		{"id":"pickup","label":"+40% Pickup-Radius","apply":Callable(self, "_up_pickup")},
		{"id":"hp",  "label":"+25 Max HP","apply":Callable(self, "_up_maxhp")},
		{"id":"heal","label":"Heilung: voll auffüllen","apply":Callable(self, "_up_heal")},
		{"id":"pierce","label":"+1 Durchschlag","apply":Callable(self, "_up_pierce")},
		{"id":"boost_tank","label":"+40% Boost-Tank","apply":Callable(self, "_up_boost_tank")},
		{"id":"boost_str","label":"+15% Boost-Stärke","apply":Callable(self, "_up_boost_strength")},
	]

func _up_proj():   u_projectiles += 1;       _visual_add_gun()
func _up_rate():   u_fire_rate_mult *= 1.25; _visual_add_rate_coil()   # weapon overclock, not an engine
func _up_dmg():    u_damage = int(round(u_damage * 1.30)); _visual_grow_damage_core()
func _up_speed():  u_speed_mult *= 1.15;     _visual_add_engine()      # speed = thruster pods
func _up_range():
	u_range_mult *= 1.25
	_visual_add_sensor()
	_apply_range_zoom()

func _apply_range_zoom() -> void:
	# Range upgrades zoom the camera out and scale the ship up by the same
	# factor — net effect: ship stays the same size on screen, but more world
	# becomes visible (matching the now-longer shooting range).
	cam_base_pos = CAM_OFFSET_BASE * u_range_mult
	if p_node != null:
		p_node.scale = Vector3.ONE * SHIP_SCALE_BASE * u_range_mult
func _up_pickup(): u_pickup_mult *= 1.40;    _visual_set_pickup_ring()
func _up_maxhp():  p_max_hp += 25; p_hp += 25; _visual_add_armor()
func _up_heal():   p_hp = p_max_hp
func _up_pierce(): u_pierce += 1;            _visual_set_pierce_lance()
func _up_boost_tank():
	u_boost_max *= 1.40
	boost_charge = u_boost_max  # refund full on capacity upgrade
	_visual_add_boost_tank()
func _up_boost_strength():
	u_boost_strength += 0.25
	_visual_add_boost_nozzle()

# ============================================================
# Visual upgrade attachments
# ============================================================

func _mat_metal(albedo: Color, emit_e: float = 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = albedo
	m.emission_energy_multiplier = emit_e
	m.metallic = 0.7
	m.roughness = 0.3
	return m

func _visual_add_gun() -> void:
	# Small wing-mounted cannon — compact, not a big long cylinder.
	var n: int = visual_guns.size()
	var side: int = -1 if (n % 2 == 0) else 1
	var stack: int = (n / 2) + 1
	var gun_root := Node3D.new()
	# Short stubby barrel
	var gun := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.032
	cm.bottom_radius = 0.05
	cm.height = 0.26
	cm.material = _mat_metal(Color(0.42, 0.47, 0.56))
	gun.mesh = cm
	gun.position = Vector3(0.26, 0.0, 0)
	gun.rotation_degrees = Vector3(0, 0, 90)
	gun_root.add_child(gun)
	# Tiny muzzle glow
	var muzzle := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.045; mm.height = 0.09
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.5, 1.0, 0.95)
	mmat.emission_enabled = true
	mmat.emission = Color(0.5, 1.0, 0.95)
	mmat.emission_energy_multiplier = 4.0
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.material = mmat
	muzzle.mesh = mm
	muzzle.position = Vector3(0.42, 0.0, 0)
	gun_root.add_child(muzzle)
	# Small mount
	var mount := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.07, 0.12); bm.material = _mat_metal(Color(0.3, 0.34, 0.4))
	mount.mesh = bm
	mount.position = Vector3(0.1, -0.03, 0)
	gun_root.add_child(mount)
	gun_root.position = Vector3(0.04, 0.05, side * (0.26 + stack * 0.15))
	ship_render.add_child(gun_root)
	visual_guns.append(gun_root)

func _visual_add_engine() -> void:
	# Speed: a small, cleanly-shaped tapered thruster nozzle at the rear.
	var n: int = visual_engines.size()
	var side: int = -1 if (n % 2 == 0) else 1
	var stack: int = (n / 2) + 1
	var zpos: float = side * (0.32 + stack * 0.16)
	# Tapered nozzle (narrow at the front, flares at the rear exit)
	var noz := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.085   # rear flare
	cm.bottom_radius = 0.05 # front (mates to hull)
	cm.height = 0.22
	cm.material = _mat_metal(Color(0.4, 0.45, 0.55))
	noz.mesh = cm
	noz.position = Vector3(-0.52, -0.02, zpos)
	noz.rotation_degrees = Vector3(0, 0, 90)
	ship_render.add_child(noz)
	# Small bright exhaust glow at the nozzle exit
	var glow := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.07; gm.bottom_radius = 0.02; gm.height = 0.1
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.5, 0.9, 1.0)
	gmat.emission_enabled = true
	gmat.emission = Color(0.5, 0.9, 1.0)
	gmat.emission_energy_multiplier = 4.0
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.material = gmat
	glow.mesh = gm
	glow.position = Vector3(-0.66, -0.02, zpos)
	glow.rotation_degrees = Vector3(0, 0, 90)
	ship_render.add_child(glow)
	visual_engines.append(noz)

func _visual_grow_damage_core() -> void:
	# Damage upgrade: glowing energy core under cockpit grows brighter/larger
	visual_damage_lvl += 1
	if visual_damage_core != null:
		visual_damage_core.queue_free()
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var r: float = 0.13 + visual_damage_lvl * 0.04
	sm.radius = r; sm.height = r * 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.8)
	mat.emission_energy_multiplier = 2.0 + visual_damage_lvl * 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat
	core.mesh = sm
	core.position = Vector3(0.05, 0.06, 0)
	ship_render.add_child(core)
	visual_damage_core = core

func _visual_add_speed_fin() -> void:
	# Custom tail fin / aero fin — extra speed look
	var n: int = visual_speed_fins.size()
	var side: int = -1 if (n % 2 == 0) else 1
	var fin := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.3, 0.32, 0.06); pm.material = _mat_metal(Color(0.5, 0.6, 0.75))
	fin.mesh = pm
	fin.position = Vector3(-0.35, 0.22, side * 0.22)
	fin.rotation_degrees = Vector3(0, 0, 12 * side)
	ship_render.add_child(fin)
	visual_speed_fins.append(fin)

func _visual_add_sensor() -> void:
	# Custom antenna/dish on top of ship
	var n: int = visual_sensors.size()
	var stalk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015; cyl.bottom_radius = 0.022
	cyl.height = 0.28 + n * 0.06
	cyl.material = _mat_metal(Color(0.6, 0.65, 0.7))
	stalk.mesh = cyl
	stalk.position = Vector3(0.05 - n * 0.18, 0.32 + (cyl.height * 0.5), 0)
	ship_render.add_child(stalk)
	var dish := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08; sm.height = 0.1
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.6, 1.0, 0.7)
	dmat.emission_enabled = true
	dmat.emission = Color(0.5, 1.0, 0.7)
	dmat.emission_energy_multiplier = 2.5
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = dmat
	dish.mesh = sm
	dish.position = Vector3(0.05 - n * 0.18, 0.36 + cyl.height, 0)
	ship_render.add_child(dish)
	visual_sensors.append(stalk)

func _visual_set_pickup_ring() -> void:
	# Magnetic pickup ring around the ship — radius scales with the pickup level, so
	# each upgrade visibly widens the collection ring.
	if visual_pickup_ring != null:
		visual_pickup_ring.queue_free()
	visual_pickup_ring = MeshInstance3D.new()
	var inner: float = 0.7 * u_pickup_mult
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = inner + 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.7, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.55, 1.0)
	mat.emission_energy_multiplier = 1.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.55
	tm.material = mat
	visual_pickup_ring.mesh = tm
	# Torus default lies in XZ plane (open along Y) — perfect for our ring around ship
	ship_render.add_child(visual_pickup_ring)

func _visual_add_armor() -> void:
	# Layered steel armor plating hugging the hull (base plate + raised plate +
	# glowing edge trim) — reads as real armor, not a flat copper box.
	var n: int = visual_armor.size()
	var side: int = -1 if (n % 2 == 0) else 1
	var stack: int = (n / 2)
	var root := Node3D.new()
	var steel := _mat_metal(Color(0.5, 0.55, 0.62), 0.12)
	steel.roughness = 0.45
	# Base plate (flat, hugs the hull)
	var base := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.4, 0.055, 0.16); bb.material = steel
	base.mesh = bb
	root.add_child(base)
	# Raised upper plate (layered look)
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.27, 0.05, 0.12); tb.material = steel
	top.mesh = tb
	top.position = Vector3(0.0, 0.05, 0)
	root.add_child(top)
	# Thin glowing trim strip along the outer edge
	var trim := MeshInstance3D.new()
	var trb := BoxMesh.new()
	trb.size = Vector3(0.4, 0.02, 0.025)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.5, 0.85, 1.0)
	tmat.emission_enabled = true
	tmat.emission = Color(0.45, 0.8, 1.0)
	tmat.emission_energy_multiplier = 1.6
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trb.material = tmat
	trim.mesh = trb
	trim.position = Vector3(0.0, 0.02, side * 0.085)
	root.add_child(trim)
	root.position = Vector3(-0.1 + stack * 0.28, 0.04, side * 0.46)
	ship_render.add_child(root)
	visual_armor.append(root)

func _visual_set_pierce_lance() -> void:
	# Custom tapered cylinder forming a spike — pierce upgrade
	if visual_pierce != null:
		visual_pierce.queue_free()
	visual_pierce = Node3D.new()
	var spike := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.05
	cm.height = 0.22 + u_pierce * 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.3)
	mat.emission_energy_multiplier = 2.5
	mat.metallic = 0.8
	mat.roughness = 0.2
	cm.material = mat
	spike.mesh = cm
	# Cylinder default vertical (+Y up). Rotate Z=-90° to lay it forward (+X tip).
	# Small spike sitting at the nose (not a big lance floating ahead).
	spike.position = Vector3(0.92 + (cm.height * 0.5), 0, 0)
	spike.rotation_degrees = Vector3(0, 0, -90)
	visual_pierce.add_child(spike)
	ship_render.add_child(visual_pierce)

func _visual_add_rate_coil() -> void:
	# Fire-rate: a small glowing weapon "overclock" cell beside the guns — a bright
	# energy core with thin dark caps + a glow ring. Reads as hotter, faster-firing
	# weapons (not a gray block, not an engine).
	var n: int = visual_rate_coils.size()
	var side: int = -1 if (n % 2 == 0) else 1
	var stack: int = n / 2
	var root := Node3D.new()
	# Bright glowing energy core (the main visual)
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(1.0, 0.55, 0.18)
	emat.emission_enabled = true
	emat.emission = Color(1.0, 0.45, 0.12)
	emat.emission_energy_multiplier = 3.8
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var core := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.045; cm.bottom_radius = 0.045; cm.height = 0.2
	cm.material = emat
	core.mesh = cm
	core.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(core)
	# Thin dark metal end caps
	var capmat := _mat_metal(Color(0.28, 0.31, 0.38))
	for ex in [-0.1, 0.1]:
		var cap := MeshInstance3D.new()
		var ccm := CylinderMesh.new()
		ccm.top_radius = 0.055; ccm.bottom_radius = 0.055; ccm.height = 0.04
		ccm.material = capmat
		cap.mesh = ccm
		cap.rotation_degrees = Vector3(0, 0, 90)
		cap.position = Vector3(ex, 0, 0)
		root.add_child(cap)
	# Glow ring around the middle
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.05; tm.outer_radius = 0.072
	tm.material = emat
	ring.mesh = tm
	ring.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(ring)
	root.position = Vector3(0.1, 0.12, side * (0.26 + stack * 0.15))
	ship_render.add_child(root)
	visual_rate_coils.append(root)

func _visual_add_boost_tank() -> void:
	# Boost capacity: extra fuel canisters strapped to the rear spine. More tank = more boost.
	var n: int = visual_boost_tanks.size()
	var side: int = -1 if (n % 2 == 0) else 1
	var stack: int = n / 2
	var root := Node3D.new()
	var tank := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.07; cm.height = 0.34
	cm.material = _mat_metal(Color(0.42, 0.46, 0.52))
	tank.mesh = cm
	tank.rotation_degrees = Vector3(0, 0, 90)   # lie along X
	root.add_child(tank)
	# Glowing fuel-level stripe
	var stripe := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.074; sc.bottom_radius = 0.074; sc.height = 0.08
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.3, 0.9, 1.0)
	smat.emission_enabled = true
	smat.emission = Color(0.3, 0.85, 1.0)
	smat.emission_energy_multiplier = 2.4
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sc.material = smat
	stripe.mesh = sc
	stripe.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(stripe)
	root.position = Vector3(-0.36, 0.16 + stack * 0.14, side * 0.13)
	ship_render.add_child(root)
	visual_boost_tanks.append(root)

func _visual_add_boost_nozzle() -> void:
	# Boost strength: flared afterburner nozzles around the twin engine exits.
	# Rebuilt each upgrade so they grow with boost strength.
	if visual_boost_nozzle != null:
		visual_boost_nozzle.queue_free()
	visual_boost_nozzle = Node3D.new()
	var steps: float = max(1.0, round((u_boost_strength - 1.8) / 0.25))   # number of strength upgrades
	var flare: float = 0.15 + steps * 0.03
	var length: float = 0.18 + steps * 0.025
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(0.4, 0.6, 0.95)
	nmat.emission_enabled = true
	nmat.emission = Color(0.35, 0.6, 1.0)
	nmat.emission_energy_multiplier = 1.8
	nmat.metallic = 0.8; nmat.roughness = 0.25
	for zsign in [-1, 1]:
		var noz := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = flare      # wide flare at the rear (-X after Z+90 rotation)
		cm.bottom_radius = 0.1     # narrow end meets the engine
		cm.height = length
		cm.material = nmat
		noz.mesh = cm
		noz.rotation_degrees = Vector3(0, 0, 90)
		noz.position = Vector3(-0.93 - length * 0.5, -0.02, zsign * 0.14)
		visual_boost_nozzle.add_child(noz)
	ship_render.add_child(visual_boost_nozzle)

func _on_levelup_pick(idx: int) -> void:
	if idx >= levelup_buttons.size():
		return
	var btn: Button = levelup_buttons[idx]
	if not btn.visible:
		return
	var up: Dictionary = btn.get_meta("upgrade")
	up["apply"].call()
	levelup_panel.visible = false
	state = STATE_PLAYING
	# Resume server-side damage, but keep a short grace window so we're not instantly
	# hit by whatever drifted into us while the menu was open.
	if net_mode == NetMode.CLIENT:
		notify_busy.rpc_id(1, false)
		p_invuln_timer = maxf(p_invuln_timer, 1.0)

# ============================================================
# State / restart / shake
# ============================================================

func _check_state() -> void:
	if p_hp > 0 or state == STATE_GAMEOVER:
		return
	# Co-op: tell the server we're down so it stops damaging us and spawning on the
	# corpse while the death screen is up. Single-player just freezes behind it.
	if net_mode == NetMode.CLIENT:
		notify_busy.rpc_id(1, true)
	_show_gameover()

func _show_gameover() -> void:
	state = STATE_GAMEOVER
	menu_open = false
	if esc_panel != null:
		esc_panel.visible = false
	go_panel.visible = true
	go_title.text = "GAME OVER"
	go_title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	go_detail.text = _run_stats_text()
	# Prime the highscore entry: prefill the name, re-arm the save button, and pull
	# the freshest board from the server so it shows up to date.
	score_submitted = false
	if go_name_edit != null:
		go_name_edit.text = player_name
	if go_save_btn != null:
		go_save_btn.disabled = false
		go_save_btn.text = "Score speichern"
	if net_mode == NetMode.CLIENT and net_connected:
		request_highscores.rpc_id(1)
	_update_personal_best()
	_refresh_go_board()

# Submit the just-finished run to the leaderboard (server-global in co-op, local
# file in single-player), using the name currently in the field.
func _on_save_score() -> void:
	if score_submitted:
		return
	if go_name_edit != null:
		player_name = _sanitize_name(go_name_edit.text)
	_save_settings()
	score_submitted = true
	if go_save_btn != null:
		go_save_btn.disabled = true
		go_save_btn.text = "Gespeichert ✓"
	var lvl := p_level
	var wv := wave
	var kl := kills
	var tm := int(run_time)
	if net_mode == NetMode.CLIENT:
		if net_connected:
			set_player_name.rpc_id(1, player_name)
			submit_score.rpc_id(1, player_name, lvl, wv, kl, tm)
	else:
		# Single-player: keep a local board on disk.
		highscores.append({"name": player_name, "level": lvl, "wave": wv, "kills": kl, "time": tm})
		_sort_highscores()
		if highscores.size() > HS_MAX:
			highscores.resize(HS_MAX)
		_save_highscores_server()
		_refresh_go_board()

func _refresh_go_board() -> void:
	if go_board_label != null:
		go_board_label.text = _highscore_text(12)

func _run_stats_text() -> String:
	var secs := int(run_time)
	var tstr := "%d:%02d" % [secs / 60, secs % 60]
	var line1 := "Welle %d     ·     %d Kills     ·     %s überlebt     ·     Level %d" % [wave, kills, tstr, p_level]
	var line2 := "Schaden %d   ·   Feuerrate %d%%   ·   Schüsse/Salve %d   ·   Durchschlag %d" % [u_damage, int(round(u_fire_rate_mult * 100.0)), u_projectiles, u_pierce]
	var line3 := "Tempo %d%%   ·   Reichweite %d%%   ·   Max HP %d   ·   Pickup %d%%" % [int(round(u_speed_mult * 100.0)), int(round(u_range_mult * 100.0)), p_max_hp, int(round(u_pickup_mult * 100.0))]
	var line4 := "Boost-Tank %d%%   ·   Boost-Stärke %d%%" % [int(round(u_boost_max * 100.0)), int(round(u_boost_strength / 1.8 * 100.0))]
	return line1 + "\n\n" + line2 + "\n" + line3 + "\n" + line4

# Buttons on the death screen dispatch by mode: co-op keeps the shared world alive,
# single-player does a full local reset.
func _on_restart_pressed() -> void:
	if net_mode == NetMode.CLIENT:
		_coop_restart()
	else:
		_restart_run()

func _on_give_up_pressed() -> void:
	if net_mode == NetMode.CLIENT and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	get_tree().quit()

# Co-op restart: leave the server-owned world untouched (enemies/bullets/gems keep
# streaming in) — just reset our own progression and rejoin with a grace window.
func _coop_restart() -> void:
	_reset_player_progression()
	run_time = 0.0
	kills = 0
	wave = 1
	reset_my_run.rpc_id(1)   # tell the server to reset our per-player wave + kills too
	notify_busy.rpc_id(1, false)
	p_invuln_timer = maxf(p_invuln_timer, 2.0)
	state = STATE_PLAYING
	menu_open = false
	go_panel.visible = false
	levelup_panel.visible = false
	if esc_panel != null:
		esc_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false

# Resets the ship + all upgrade stats back to a fresh run. Shared by the
# single-player full restart and the co-op rejoin.
func _reset_player_progression() -> void:
	if p_node != null:
		p_node.queue_free()
	visual_guns.clear()
	visual_engines.clear()
	visual_armor.clear()
	visual_sensors.clear()
	visual_speed_fins.clear()
	visual_rate_coils.clear()
	visual_boost_tanks.clear()
	visual_boost_nozzle = null
	visual_pierce = null
	visual_pickup_ring = null
	visual_damage_core = null
	visual_damage_lvl = 0
	_build_player()
	p_vel = Vector3.ZERO
	p_hp = P_HP
	p_max_hp = P_HP
	p_level = 1
	p_xp = 0
	fire_timer = 0.0
	u_speed_mult = 1.0
	u_fire_rate_mult = 1.0
	u_damage = 12
	u_projectiles = 1
	u_range_mult = 1.0
	_apply_range_zoom()
	u_pickup_mult = 1.0
	u_pierce = 0
	u_boost_max = 1.0
	u_boost_strength = 1.8
	boost_charge = 1.0
	boosting = false
	boost_depleted = false

func _restart_run() -> void:
	for e in enemies:
		if e.node != null:
			e.node.queue_free()
	for b in p_bullets:
		if b.node != null:
			b.node.queue_free()
	for b in e_bullets:
		if b.node != null:
			b.node.queue_free()
	for g in gems:
		if g.node != null:
			g.node.queue_free()
	enemies.clear()
	p_bullets.clear()
	e_bullets.clear()
	gems.clear()
	_reset_events()
	_reset_player_progression()
	p_pos = Vector3.ZERO
	wave = 1
	wave_timer = WAVE_DURATION
	spawn_timer = 1.5
	spawn_interval = 1.5
	p_invuln_timer = 0.0
	kills = 0
	run_time = 0.0
	state = STATE_PLAYING
	menu_open = false
	go_panel.visible = false
	levelup_panel.visible = false
	if esc_panel != null:
		esc_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false

func _purge_dead() -> void:
	var keep_e: Array = []
	for e in enemies:
		if e.dead:
			if e.node != null:
				e.node.queue_free()
		else:
			keep_e.append(e)
	enemies = keep_e
	var keep_pb: Array = []
	for b in p_bullets:
		if b.dead:
			if b.node != null:
				b.node.queue_free()
		else:
			keep_pb.append(b)
	p_bullets = keep_pb
	var keep_eb: Array = []
	for b in e_bullets:
		if b.dead:
			if b.node != null:
				b.node.queue_free()
		else:
			keep_eb.append(b)
	e_bullets = keep_eb
	var keep_g: Array = []
	for g in gems:
		if g.dead:
			if g.node != null:
				g.node.queue_free()
		else:
			keep_g.append(g)
	gems = keep_g

func _camera_shake(amount: float, dur: float) -> void:
	shake_amount = max(shake_amount, amount)
	shake_timer = max(shake_timer, dur)

func _update_shake(delta: float) -> void:
	# Follow camera: smoothly trail the player while keeping the side angle
	var follow_target: Vector3 = p_pos + cam_base_pos
	var shake_off: Vector3 = Vector3.ZERO
	if shake_timer > 0.0:
		shake_timer -= delta
		var s: float = shake_amount * (shake_timer / max(0.001, shake_timer + delta))
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * s * 0.45
		if shake_timer <= 0.0:
			shake_amount = 0.0
	cam.position = cam.position.lerp(follow_target, clamp(delta * 5.5, 0.0, 1.0)) + shake_off
	cam.look_at(p_pos, Vector3.UP)
	# Smoothly ease FOV toward target (boost widens it; default snaps back)
	if cam != null:
		cam.fov = lerp(cam.fov, p_cam_fov_target, clamp(delta * 6.0, 0.0, 1.0))

func _animate_ship_lights(delta: float) -> void:
	# Sine-pulse the emission of every registered status light so the ship feels
	# alive. Each entry has its own freq/phase so they don't pulse in unison.
	var t: float = run_time
	for L in p_pulse_lights:
		var mat: StandardMaterial3D = L["mat"]
		if mat == null:
			continue
		var v: float = sin(t * L["freq"] * TAU + L["phase"])
		mat.emission_energy_multiplier = max(0.05, L["base"] + L["amp"] * v)
	# Engine glow: BOTH engines updated with two EXPLICIT assignments (no loop,
	# no array iteration). Whatever was making the left engine fail to pulse,
	# this guarantees the assignment happens for both.
	var speed_norm: float = clamp(p_vel.length() / P_SPEED, 0.0, 1.5)
	var boost_kick: float = (u_boost_strength - 1.0) if boosting else 0.0
	var target_e: float = 3.0 + speed_norm * 3.0 + boost_kick * 3.5
	var jitter: float = 0.25 * sin(t * 28.0)
	var engine_val: float = max(1.0, target_e + jitter)
	if p_engine_mat_port != null:
		p_engine_mat_port.emission_energy_multiplier = engine_val
	if p_engine_mat_starboard != null:
		p_engine_mat_starboard.emission_energy_multiplier = engine_val
	# Boost flame: visible only while boosting, length scales with charge level.
	if p_boost_flame != null and p_boost_flame_mat != null:
		var want_visible: bool = boosting and boost_charge > 0.01
		p_boost_flame.visible = want_visible
		var target_len: float = 0.0
		var target_rad: float = 0.0
		if want_visible:
			# Length pulses 0.85x..1.15x for a "breathing" jet
			var pulse: float = 1.0 + 0.15 * sin(t * 22.0)
			target_len = 3.8 * pulse * (0.7 + 0.3 * (boost_charge / max(0.001, u_boost_max)))
			target_rad = 1.2 + 0.15 * sin(t * 18.0)
		# Scale.x is along ship-forward (engine direction) after the Z-rotation;
		# scale.y is the radius. Smooth so it doesn't pop.
		var cur: Vector3 = p_boost_flame.scale
		var tgt: Vector3 = Vector3(target_len if want_visible else 0.01,
			target_rad if want_visible else 0.01,
			target_rad if want_visible else 0.01)
		# Quick ramp-up, slow fade-out
		var lerp_t: float = clamp(delta * (14.0 if want_visible else 8.0), 0.0, 1.0)
		p_boost_flame.scale = cur.lerp(tgt, lerp_t)
		p_boost_flame_mat.emission_energy_multiplier = (7.5 if want_visible else 0.5)
	# Camera FOV target: snap upward while boosting, ease back when not.
	if boosting:
		p_cam_fov_target = p_cam_fov_base + 10.0
	else:
		p_cam_fov_target = p_cam_fov_base

func _build_speedlines() -> void:
	# Radial streak overlay used during boost. Each streak is a ColorRect with
	# its own outward direction; alpha is gated globally by speedlines_alpha.
	speedlines_layer = CanvasLayer.new()
	speedlines_layer.layer = 9  # in front of game world, behind HUD (HUD is layer 10+ usually)
	add_child(speedlines_layer)
	var n: int = 26
	for i in n:
		var rect := ColorRect.new()
		rect.color = Color(0.85, 0.95, 1.0, 0.0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.size = Vector2(randf_range(40, 90), 2.0)
		rect.pivot_offset = rect.size * 0.5
		speedlines_layer.add_child(rect)
		# Initial direction radiates from screen center
		var ang: float = randf() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var radius: float = randf_range(80, 260)
		var center := Vector2(640, 360)
		var pos: Vector2 = center + dir * radius
		rect.position = pos - rect.size * 0.5
		rect.rotation = ang
		speedlines.append({
			"rect": rect,
			"dir": dir,
			"speed": randf_range(900.0, 1500.0),
			"center": center,
		})

func _animate_speedlines(delta: float) -> void:
	# Target alpha: full during boost, zero otherwise. Smoothly ramp.
	var want: float = 1.0 if (boosting and boost_charge > 0.02) else 0.0
	speedlines_alpha = lerp(speedlines_alpha, want, clamp(delta * (10.0 if want > 0 else 5.0), 0.0, 1.0))
	if speedlines_alpha < 0.005:
		# Hide all streaks while idle to skip per-rect work
		for s in speedlines:
			var rect: ColorRect = s["rect"]
			rect.color.a = 0.0
		return
	for s in speedlines:
		var rect: ColorRect = s["rect"]
		var dir: Vector2 = s["dir"]
		# Push outward, alpha falls off near screen edges → respawn near center
		var center: Vector2 = s["center"]
		var pos: Vector2 = rect.position + rect.size * 0.5
		pos += dir * s["speed"] * delta
		var off: Vector2 = pos - center
		var dist: float = off.length()
		if dist > 720.0:
			# Respawn near center with new direction
			var ang2: float = randf() * TAU
			s["dir"] = Vector2(cos(ang2), sin(ang2))
			var r2: float = randf_range(60, 180)
			pos = center + s["dir"] * r2
			rect.rotation = ang2
		rect.position = pos - rect.size * 0.5
		# Alpha curve: fade in within first ~150px, hold, fade out past ~600px
		var a: float = 1.0
		if dist < 150.0:
			a = dist / 150.0
		elif dist > 500.0:
			a = max(0.0, 1.0 - (dist - 500.0) / 220.0)
		rect.color.a = a * speedlines_alpha * 0.55

func _update_muzzle_flashes(delta: float) -> void:
	# Tick down each active muzzle flash, fade emission + light energy with life.
	var keep: Array = []
	for entry in p_muzzle_lights:
		entry["life"] -= delta
		if entry["life"] <= 0.0:
			if entry["light"] != null and is_instance_valid(entry["light"]):
				entry["light"].queue_free()
			if entry["flash"] != null and is_instance_valid(entry["flash"]):
				entry["flash"].queue_free()
			continue
		var frac: float = entry["life"] / entry["life_max"]
		if entry["light"] != null and is_instance_valid(entry["light"]):
			entry["light"].light_energy = entry["energy_max"] * frac
		if entry["mat"] != null:
			entry["mat"].emission_energy_multiplier = entry["emit_max"] * frac
			var c: Color = entry["mat"].albedo_color
			c.a = frac
			entry["mat"].albedo_color = c
		if entry["flash"] != null and is_instance_valid(entry["flash"]):
			entry["flash"].scale = Vector3.ONE * (0.6 + frac * 0.8)
		keep.append(entry)
	p_muzzle_lights = keep

func _animate_background(delta: float) -> void:
	# Wrap stars around the player so the field is endless
	var wrap_max: float = 70.0
	var wrap_min: float = 45.0
	for s in stars:
		var diff: Vector3 = s.position - p_pos
		if diff.length() > wrap_max:
			var new_dir: Vector3 = -diff.normalized() + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.3, 0.3))
			new_dir = new_dir.normalized()
			s.position = p_pos + new_dir * randf_range(wrap_min, wrap_max - 5.0)
	# Wrap + rotate distant objects (planets, nebulae, asteroid clusters)
	for obj_data in distant_objects:
		var node: Node3D = obj_data["node"]
		var wr: float = obj_data["wrap_radius"]
		# Slow rotation for visual life
		var axis: Vector3 = obj_data["rot_axis"]
		var rs: float = obj_data["rot_speed"]
		node.rotate(axis, rs * delta)
		# Wrap if too far in XY (ignore Z so it stays distant)
		var dx: float = node.position.x - p_pos.x
		var dy: float = node.position.y - p_pos.y
		var planar: float = sqrt(dx * dx + dy * dy)
		if planar > wr:
			# Move to opposite side at near-distance
			var inv: Vector3 = -Vector3(dx, dy, 0).normalized()
			var inv_off: Vector3 = inv + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), 0)
			inv_off = inv_off.normalized()
			var new_planar: float = randf_range(wr * 0.5, wr * 0.85)
			node.position = Vector3(p_pos.x + inv_off.x * new_planar, p_pos.y + inv_off.y * new_planar, node.position.z)

# ============================================================
# HUD
# ============================================================

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	# All gameplay HUD lives in this container so the home screen can hide it in one shot.
	# Overlay panels (level-up / game-over / ESC / settings / home) are added to `hud`
	# directly, so they keep drawing on top of the gameplay HUD.
	hud_game = Control.new()
	hud_game.size = Vector2(1280, 720)
	hud_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_game)

	lbl_hp = _hud_label("", Vector2(18, 14), 14, COL_TEXT)
	_hud_rect(Vector2(18, 36), Vector2(260, 12), Color(0.12, 0.06, 0.08))
	bar_hp_fill = _hud_rect(Vector2(18, 36), Vector2(260, 12), Color(0.55, 0.95, 0.55))

	lbl_xp = _hud_label("", Vector2(18, 58), 12, COL_DIM)
	_hud_rect(Vector2(18, 78), Vector2(260, 8), Color(0.08, 0.08, 0.14))
	bar_xp_fill = _hud_rect(Vector2(18, 78), Vector2(260, 8), Color(0.45, 0.85, 1.0))

	lbl_boost = _hud_label("BOOST  [Shift]", Vector2(18, 92), 11, Color(1.0, 0.75, 0.35))
	bar_boost_bg = _hud_rect(Vector2(18, 110), Vector2(260, 6), Color(0.10, 0.06, 0.04))
	bar_boost_fill = _hud_rect(Vector2(18, 110), Vector2(260, 6), Color(1.0, 0.65, 0.25))

	lbl_wave = _hud_label("", Vector2(560, 14), 20, COL_TEXT)
	lbl_wave.size = Vector2(160, 28)
	lbl_wave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Transient event banner (centre-top) — shown by _show_announce.
	announce_label = _hud_label("", Vector2(140, 120), 19, Color(1.0, 0.82, 0.4))
	announce_label.size = Vector2(1000, 28)
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_label.visible = false
	# Persistent objective line (live during an event) — shown by _set_objective.
	objective_label = _hud_label("", Vector2(140, 150), 16, Color(0.55, 1.0, 0.7))
	objective_label.size = Vector2(1000, 24)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.visible = false

	lbl_time = _hud_label("", Vector2(1140, 14), 14, COL_DIM)
	lbl_time.size = Vector2(120, 22)
	lbl_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	lbl_stats = _hud_label("", Vector2(18, 690), 11, COL_DIM)

	var lbl_ver := _hud_label("v" + GAME_VERSION, Vector2(1130, 700), 10, Color(0.45, 0.55, 0.7))
	lbl_ver.size = Vector2(130, 16)
	lbl_ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Radar mini-map bottom-right
	radar = RadarPanel.new()
	radar.main = self
	radar.size = Vector2(radar.radius_pixels * 2.0, radar.radius_pixels * 2.0)
	radar.position = Vector2(1280 - radar.size.x - 20, 720 - radar.size.y - 20)
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_game.add_child(radar)

func _hud_label(text: String, pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	hud_game.add_child(l)
	return l

func _hud_rect(pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_game.add_child(r)
	return r

func _update_ui_text() -> void:
	lbl_hp.text = "HÜLLE   %d / %d" % [max(0, p_hp), p_max_hp]
	bar_hp_fill.size = Vector2(260.0 * clamp(float(p_hp) / float(p_max_hp), 0.0, 1.0), 12)
	var need: int = _xp_for_next()
	lbl_xp.text = "LV %d   ·   %d / %d XP" % [p_level, p_xp, need]
	bar_xp_fill.size = Vector2(260.0 * clamp(float(p_xp) / float(need), 0.0, 1.0), 8)
	# Boost bar — width by current charge, color flashes brighter while boosting
	var boost_frac: float = clamp(boost_charge / max(u_boost_max, 0.01), 0.0, 1.0)
	bar_boost_fill.size = Vector2(260.0 * boost_frac, 6)
	bar_boost_fill.color = Color(1.0, 0.9, 0.45) if boosting else Color(1.0, 0.65, 0.25)
	# Co-op: the wave timer ticks per-player on the server and isn't streamed, so
	# just show the wave number; single-player keeps the live countdown.
	if net_mode == NetMode.CLIENT:
		lbl_wave.text = "WELLE %d" % wave
	else:
		lbl_wave.text = "WELLE %d   %ds" % [wave, max(0, int(ceil(wave_timer)))]
	lbl_time.text = "%02d:%02d" % [int(run_time) / 60, int(run_time) % 60]
	lbl_stats.text = "Schaden %d  ·  Schüsse %d  ·  Feuerrate %.0f%%  ·  Reichweite %.0f%%  ·  Tempo %.0f%%  ·  Durchschlag %d  ·  Kills %d" % [
		u_damage, u_projectiles, u_fire_rate_mult * 100.0,
		u_range_mult * 100.0, u_speed_mult * 100.0,
		u_pierce, kills
	]

# ============================================================
# Level-up panel
# ============================================================

func _build_levelup_panel() -> void:
	levelup_panel = Control.new()
	levelup_panel.size = Vector2(1280, 720)
	levelup_panel.visible = false
	hud.add_child(levelup_panel)

	var bg := ColorRect.new()
	bg.size = Vector2(1280, 720)
	bg.color = Color(0.0, 0.0, 0.02, 0.72)
	levelup_panel.add_child(bg)

	var title := Label.new()
	title.text = "LEVEL UP"
	title.position = Vector2(0, 180)
	title.size = Vector2(1280, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.5, 1.0, 1.0))
	title.add_theme_font_size_override("font_size", 44)
	levelup_panel.add_child(title)

	var sub := Label.new()
	sub.text = "Wähle eine Verstärkung"
	sub.position = Vector2(0, 234)
	sub.size = Vector2(1280, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", COL_DIM)
	sub.add_theme_font_size_override("font_size", 16)
	levelup_panel.add_child(sub)

	var bw: float = 320.0
	var bh: float = 100.0
	var gap: float = 40.0
	var total_w: float = bw * 3 + gap * 2
	var start_x: float = (1280 - total_w) * 0.5
	for i in 3:
		var b := Button.new()
		b.position = Vector2(start_x + i * (bw + gap), 320)
		b.size = Vector2(bw, bh)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_on_levelup_pick.bind(i))
		levelup_panel.add_child(b)
		levelup_buttons.append(b)

func _build_go_panel() -> void:
	go_panel = Control.new()
	go_panel.size = Vector2(1280, 720)
	go_panel.visible = false
	hud.add_child(go_panel)
	var bg := ColorRect.new()
	bg.size = Vector2(1280, 720)
	bg.color = Color(0.0, 0.0, 0.0, 0.86)
	go_panel.add_child(bg)
	go_title = Label.new()
	go_title.position = Vector2(0, 36)
	go_title.size = Vector2(1280, 72)
	go_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_title.add_theme_font_size_override("font_size", 56)
	go_panel.add_child(go_title)
	go_detail = Label.new()
	go_detail.position = Vector2(0, 120)
	go_detail.size = Vector2(1280, 120)
	go_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_detail.add_theme_color_override("font_color", COL_DIM)
	go_detail.add_theme_font_size_override("font_size", 16)
	go_panel.add_child(go_detail)

	# Highscore entry row: name field + save button.
	var name_lbl := Label.new()
	name_lbl.text = "Dein Name:"
	name_lbl.position = Vector2(330, 256)
	name_lbl.size = Vector2(120, 40)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_lbl.add_theme_color_override("font_color", COL_TEXT)
	name_lbl.add_theme_font_size_override("font_size", 16)
	go_panel.add_child(name_lbl)
	go_name_edit = LineEdit.new()
	go_name_edit.position = Vector2(462, 252)
	go_name_edit.size = Vector2(260, 44)
	go_name_edit.max_length = 18
	go_name_edit.placeholder_text = "Pilot"
	go_name_edit.add_theme_font_size_override("font_size", 18)
	go_panel.add_child(go_name_edit)
	go_save_btn = Button.new()
	go_save_btn.text = "Score speichern"
	go_save_btn.position = Vector2(738, 252)
	go_save_btn.size = Vector2(180, 44)
	go_save_btn.add_theme_font_size_override("font_size", 16)
	go_save_btn.pressed.connect(_on_save_score)
	go_panel.add_child(go_save_btn)

	# Leaderboard.
	var board_hdr := Label.new()
	board_hdr.text = "★  BESTENLISTE  ★"
	board_hdr.position = Vector2(0, 312)
	board_hdr.size = Vector2(1280, 28)
	board_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board_hdr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	board_hdr.add_theme_font_size_override("font_size", 20)
	go_panel.add_child(board_hdr)
	go_board_label = Label.new()
	go_board_label.position = Vector2(0, 348)
	go_board_label.size = Vector2(1280, 250)
	go_board_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_board_label.add_theme_color_override("font_color", COL_TEXT)
	go_board_label.add_theme_font_size_override("font_size", 15)
	go_panel.add_child(go_board_label)

	var restart_btn := Button.new()
	restart_btn.text = "Neu Starten"
	restart_btn.position = Vector2(420, 636)
	restart_btn.size = Vector2(200, 52)
	restart_btn.add_theme_font_size_override("font_size", 20)
	restart_btn.pressed.connect(_on_restart_pressed)
	go_panel.add_child(restart_btn)
	var giveup_btn := Button.new()
	giveup_btn.text = "Aufgeben"
	giveup_btn.position = Vector2(660, 636)
	giveup_btn.size = Vector2(200, 52)
	giveup_btn.add_theme_font_size_override("font_size", 20)
	giveup_btn.pressed.connect(_on_give_up_pressed)
	go_panel.add_child(giveup_btn)

# ============================================================
# ESC screen — self-pause + server roster + leaderboard + settings
# ============================================================

func _build_esc_panel() -> void:
	esc_panel = Control.new()
	esc_panel.size = Vector2(1280, 720)
	esc_panel.visible = false
	hud.add_child(esc_panel)

	var bg := ColorRect.new()
	bg.size = Vector2(1280, 720)
	bg.color = Color(0.0, 0.01, 0.04, 0.84)
	esc_panel.add_child(bg)

	var title := Label.new()
	title.text = "PAUSE"
	title.position = Vector2(0, 24)
	title.size = Vector2(1280, 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	title.add_theme_font_size_override("font_size", 44)
	esc_panel.add_child(title)

	var sub := Label.new()
	sub.text = "Du bist geschützt — kein Schaden, keine Gegner spawnen um dich"
	sub.position = Vector2(0, 84)
	sub.size = Vector2(1280, 26)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", COL_DIM)
	sub.add_theme_font_size_override("font_size", 15)
	esc_panel.add_child(sub)

	# Left column — who's online.
	var ros_hdr := Label.new()
	ros_hdr.text = "SPIELER ONLINE"
	ros_hdr.position = Vector2(90, 140)
	ros_hdr.size = Vector2(420, 26)
	ros_hdr.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	ros_hdr.add_theme_font_size_override("font_size", 20)
	esc_panel.add_child(ros_hdr)
	esc_roster_label = Label.new()
	esc_roster_label.position = Vector2(90, 178)
	esc_roster_label.size = Vector2(420, 360)
	esc_roster_label.add_theme_color_override("font_color", COL_TEXT)
	esc_roster_label.add_theme_font_size_override("font_size", 16)
	esc_panel.add_child(esc_roster_label)

	# Right column — leaderboard.
	var brd_hdr := Label.new()
	brd_hdr.text = "★  BESTENLISTE  ★"
	brd_hdr.position = Vector2(560, 140)
	brd_hdr.size = Vector2(640, 26)
	brd_hdr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	brd_hdr.add_theme_font_size_override("font_size", 20)
	esc_panel.add_child(brd_hdr)
	esc_board_label = Label.new()
	esc_board_label.position = Vector2(560, 178)
	esc_board_label.size = Vector2(640, 360)
	esc_board_label.add_theme_color_override("font_color", COL_TEXT)
	esc_board_label.add_theme_font_size_override("font_size", 15)
	esc_panel.add_child(esc_board_label)

	# Button row: Weiter · Neu Starten · Aufgeben · Einstellungen
	var labels := ["Weiter", "Neu Starten", "Aufgeben", "Einstellungen"]
	var calls := [Callable(self, "_toggle_esc_menu"), Callable(self, "_on_restart_pressed"),
		Callable(self, "_on_give_up_pressed"), Callable(self, "_open_settings")]
	var bw: float = 200.0
	var gap: float = 20.0
	var start_x: float = (1280.0 - (bw * 4 + gap * 3)) * 0.5
	for i in 4:
		var b := Button.new()
		b.text = labels[i]
		b.position = Vector2(start_x + i * (bw + gap), 600)
		b.size = Vector2(bw, 52)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(calls[i])
		esc_panel.add_child(b)

	_build_settings_panel()

func _build_settings_panel() -> void:
	settings_panel = Control.new()
	settings_panel.size = Vector2(1280, 720)
	settings_panel.visible = false
	hud.add_child(settings_panel)   # top-level overlay so it opens from ESC *and* the home screen

	var dim := ColorRect.new()
	dim.size = Vector2(1280, 720)
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	settings_panel.add_child(dim)

	var box := ColorRect.new()
	box.position = Vector2(390, 170)
	box.size = Vector2(500, 380)
	box.color = Color(0.05, 0.08, 0.14, 0.98)
	settings_panel.add_child(box)

	var stitle := Label.new()
	stitle.text = "EINSTELLUNGEN"
	stitle.position = Vector2(390, 188)
	stitle.size = Vector2(500, 36)
	stitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stitle.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	stitle.add_theme_font_size_override("font_size", 26)
	settings_panel.add_child(stitle)

	# Name
	var nl := Label.new()
	nl.text = "Dein Name"
	nl.position = Vector2(420, 250)
	nl.add_theme_color_override("font_color", COL_TEXT)
	nl.add_theme_font_size_override("font_size", 16)
	settings_panel.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.position = Vector2(420, 278)
	name_edit.size = Vector2(440, 42)
	name_edit.max_length = 18
	name_edit.placeholder_text = "Pilot"
	name_edit.add_theme_font_size_override("font_size", 18)
	name_edit.text_changed.connect(_on_name_changed)
	settings_panel.add_child(name_edit)

	# Master volume
	var vl := Label.new()
	vl.text = "Lautstärke"
	vl.position = Vector2(420, 340)
	vl.add_theme_color_override("font_color", COL_TEXT)
	vl.add_theme_font_size_override("font_size", 16)
	settings_panel.add_child(vl)
	vol_slider = HSlider.new()
	vol_slider.position = Vector2(420, 372)
	vol_slider.size = Vector2(440, 24)
	vol_slider.min_value = -40.0
	vol_slider.max_value = 6.0
	vol_slider.step = 1.0
	vol_slider.value = master_vol_db
	vol_slider.value_changed.connect(_on_volume_changed)
	settings_panel.add_child(vol_slider)

	# Fullscreen
	fullscreen_check = CheckBox.new()
	fullscreen_check.text = "  Vollbild"
	fullscreen_check.position = Vector2(420, 412)
	fullscreen_check.add_theme_font_size_override("font_size", 16)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	settings_panel.add_child(fullscreen_check)

	var back := Button.new()
	back.text = "Zurück"
	back.position = Vector2(490, 478)
	back.size = Vector2(300, 48)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(_close_settings)
	settings_panel.add_child(back)

# Toggle the ESC self-pause. Only openable during play. In co-op the world keeps
# running but the server marks us busy (invulnerable + nothing spawns around us);
# single-player fully freezes (see _process).
func _toggle_esc_menu() -> void:
	if state != STATE_PLAYING:
		return
	menu_open = not menu_open
	esc_panel.visible = menu_open
	if menu_open:
		if settings_panel != null:
			settings_panel.visible = false
		if net_mode == NetMode.CLIENT and net_connected:
			notify_busy.rpc_id(1, true)
			request_roster.rpc_id(1)
			request_highscores.rpc_id(1)
		_refresh_esc_lists()
	else:
		if net_mode == NetMode.CLIENT and net_connected:
			notify_busy.rpc_id(1, false)
			p_invuln_timer = maxf(p_invuln_timer, 1.0)

func _refresh_esc_lists() -> void:
	if esc_roster_label != null:
		esc_roster_label.text = _roster_text()
	if esc_board_label != null:
		esc_board_label.text = _highscore_text(14)

func _open_settings() -> void:
	if settings_panel == null:
		return
	if name_edit != null:
		name_edit.text = player_name
	if vol_slider != null:
		vol_slider.value = master_vol_db
	if fullscreen_check != null:
		fullscreen_check.button_pressed = fullscreen_on
	settings_panel.visible = true
	settings_panel.move_to_front()   # ensure it draws above the ESC or home panel

func _close_settings() -> void:
	if settings_panel != null:
		settings_panel.visible = false
	player_name = _sanitize_name(player_name)
	if net_mode == NetMode.CLIENT and net_connected:
		set_player_name.rpc_id(1, player_name)
	_save_settings()
	_refresh_esc_lists()
	if home_panel != null and home_panel.visible and home_name_edit != null:
		home_name_edit.text = player_name

func _on_name_changed(new_text: String) -> void:
	player_name = new_text

func _on_volume_changed(v: float) -> void:
	master_vol_db = v
	AudioServer.set_bus_volume_db(0, v)

func _on_fullscreen_toggled(pressed: bool) -> void:
	fullscreen_on = pressed
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED)

# Roster text for the ESC screen. Single-player shows just the local pilot.
func _roster_text() -> String:
	if net_mode != NetMode.CLIENT:
		return "● %s  (du)  —  Lv %d" % [player_name, p_level]
	if not net_connected:
		return "— nicht verbunden —"
	if net_roster.is_empty():
		return "— niemand online —"
	var my_id := multiplayer.get_unique_id()
	var ids: Array = net_roster.keys()
	ids.sort()
	var lines: Array = []
	for id in ids:
		var info: Dictionary = net_roster[id]
		var nm: String = str(info.get("name", "Pilot"))
		var lv: int = int(info.get("level", 1))
		var me: String = "  (du)" if int(id) == my_id else ""
		lines.append("●  %s%s  —  Lv %d" % [nm, me, lv])
	return "\n".join(lines)

# Formats the top `limit` highscore entries into a single multi-line string.
func _highscore_text(limit: int) -> String:
	if highscores.is_empty():
		return "— noch keine Einträge —\nSei der Erste!"
	var n: int = min(limit, highscores.size())
	var lines: Array = []
	for i in n:
		var e: Dictionary = highscores[i]
		var secs: int = int(e.get("time", 0))
		var tstr := "%d:%02d" % [secs / 60, secs % 60]
		var nm: String = str(e.get("name", "Pilot"))
		lines.append("%d.  %s  —  Lv %d  ·  Welle %d  ·  %d Kills  ·  %s" % [
			i + 1, nm, int(e.get("level", 1)), int(e.get("wave", 1)), int(e.get("kills", 0)), tstr])
	return "\n".join(lines)

# ============================================================
# Home / start screen
# ============================================================

# Builds the start-screen overlay: title, pilot name (corner), personal best,
# global leaderboard, server status + refresh, and the main action buttons. The
# live 3D world (starfield + a slowly turning ship) shows through as the backdrop.
func _build_home_panel() -> void:
	home_panel = Control.new()
	home_panel.size = Vector2(1280, 720)
	home_panel.visible = false
	hud.add_child(home_panel)

	# Dark bands top & bottom keep text readable; the clear centre frames the ship.
	var top_band := ColorRect.new()
	top_band.size = Vector2(1280, 132)
	top_band.color = Color(0.0, 0.01, 0.04, 0.8)
	top_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home_panel.add_child(top_band)
	var bottom_band := ColorRect.new()
	bottom_band.position = Vector2(0, 500)
	bottom_band.size = Vector2(1280, 220)
	bottom_band.color = Color(0.0, 0.01, 0.04, 0.8)
	bottom_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home_panel.add_child(bottom_band)

	_home_label("STERNENFLUCHT", Vector2(0, 30), 56, Color(0.6, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 1280)
	_home_label("Twin-Stick Roguelike", Vector2(0, 92), 15, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER, 1280)

	# Top-left: server status + manual refresh.
	home_status_label = _home_label("Server: …", Vector2(40, 22), 16, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, 380)
	var refresh_btn := Button.new()
	refresh_btn.text = "Aktualisieren"
	refresh_btn.position = Vector2(40, 52)
	refresh_btn.size = Vector2(140, 30)
	refresh_btn.add_theme_font_size_override("font_size", 13)
	refresh_btn.pressed.connect(_home_probe)
	home_panel.add_child(refresh_btn)

	# Top-right corner: pilot name.
	_home_label("DEIN NAME", Vector2(1000, 22), 13, COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 240)
	home_name_edit = LineEdit.new()
	home_name_edit.position = Vector2(1000, 46)
	home_name_edit.size = Vector2(240, 38)
	home_name_edit.max_length = 18
	home_name_edit.placeholder_text = "Pilot"
	home_name_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	home_name_edit.add_theme_font_size_override("font_size", 18)
	home_name_edit.text_changed.connect(_on_name_changed)
	home_panel.add_child(home_name_edit)

	# Left: personal best.
	var best_box := ColorRect.new()
	best_box.position = Vector2(40, 150)
	best_box.size = Vector2(360, 150)
	best_box.color = Color(0.04, 0.07, 0.13, 0.55)
	best_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home_panel.add_child(best_box)
	_home_label("DEIN REKORD", Vector2(60, 162), 18, Color(0.55, 0.95, 1.0), HORIZONTAL_ALIGNMENT_LEFT, 320)
	home_best_label = _home_label("", Vector2(60, 196), 16, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, 320)
	home_best_label.size = Vector2(320, 96)

	# Right: global leaderboard.
	var brd_box := ColorRect.new()
	brd_box.position = Vector2(880, 150)
	brd_box.size = Vector2(360, 320)
	brd_box.color = Color(0.04, 0.07, 0.13, 0.55)
	brd_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home_panel.add_child(brd_box)
	_home_label("★ BESTENLISTE ★", Vector2(880, 162), 18, Color(1.0, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER, 360)
	home_board_label = _home_label("", Vector2(898, 198), 12, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, 324)
	home_board_label.size = Vector2(324, 262)

	# Bottom: primary actions — online play is the default (left, accented), offline secondary.
	home_coop_btn = Button.new()
	home_coop_btn.text = "Spielen"
	home_coop_btn.position = Vector2(360, 536)
	home_coop_btn.size = Vector2(260, 60)
	home_coop_btn.add_theme_font_size_override("font_size", 22)
	home_coop_btn.pressed.connect(_home_play_coop)
	home_panel.add_child(home_coop_btn)
	var sp_btn := Button.new()
	sp_btn.text = "Offline-spielen"
	sp_btn.position = Vector2(660, 536)
	sp_btn.size = Vector2(260, 60)
	sp_btn.add_theme_font_size_override("font_size", 22)
	sp_btn.pressed.connect(_home_play_single)
	home_panel.add_child(sp_btn)
	var yard_btn := Button.new()
	yard_btn.text = "Werkstatt"
	yard_btn.position = Vector2(360, 612)
	yard_btn.size = Vector2(176, 44)
	yard_btn.add_theme_font_size_override("font_size", 16)
	yard_btn.pressed.connect(_open_shipyard)
	home_panel.add_child(yard_btn)
	var set_btn := Button.new()
	set_btn.text = "Einstellungen"
	set_btn.position = Vector2(552, 612)
	set_btn.size = Vector2(176, 44)
	set_btn.add_theme_font_size_override("font_size", 16)
	set_btn.pressed.connect(_open_settings)
	home_panel.add_child(set_btn)
	var quit_btn := Button.new()
	quit_btn.text = "Beenden"
	quit_btn.position = Vector2(744, 612)
	quit_btn.size = Vector2(176, 44)
	quit_btn.add_theme_font_size_override("font_size", 16)
	quit_btn.pressed.connect(_home_quit)
	home_panel.add_child(quit_btn)

	_home_label("v" + GAME_VERSION, Vector2(1110, 698), 11, Color(0.45, 0.55, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 130)

func _home_label(text: String, pos: Vector2, size: int, col: Color, align: int, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(width, 28)
	l.horizontal_alignment = align as HorizontalAlignment
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	home_panel.add_child(l)
	return l

# ============================================================
# Ship builder / hangar (STATE_SHIPYARD) — opened from the home screen.
# ◀ ▶ cycle cosmetic ship_design options and rebuild the showcased ship live;
# "Speichern" persists via _save_settings, "Verwerfen"/ESC restores the design
# snapshot taken on open. Design keys are validated in _load_settings.
# ============================================================
func _build_shipyard_panel() -> void:
	shipyard_panel = Control.new()
	shipyard_panel.size = Vector2(1280, 720)
	shipyard_panel.visible = false
	hud.add_child(shipyard_panel)

	# Dark control column on the left; the ship stays framed in the centre.
	var col := ColorRect.new()
	col.position = Vector2(40, 92)
	col.size = Vector2(360, 596)
	col.color = Color(0.0, 0.02, 0.06, 0.82)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shipyard_panel.add_child(col)

	var title := Label.new()
	title.text = "WERKSTATT"
	title.position = Vector2(40, 104)
	title.size = Vector2(360, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.6, 0.95, 1.0))
	shipyard_panel.add_child(title)

	var hint := Label.new()
	hint.text = "Gestalte dein Schiff – andere sehen es im Koop."
	hint.position = Vector2(60, 144)
	hint.size = Vector2(320, 40)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", COL_DIM)
	shipyard_panel.add_child(hint)

	# One row per designable part (data-driven — see SHIPYARD_ROWS).
	shipyard_val_labels.clear()
	var ry: float = 190.0
	for row in SHIPYARD_ROWS:
		_shipyard_row(str(row["key"]), str(row["label"]), ry)
		ry += 62.0

	var save_btn := Button.new()
	save_btn.text = "Speichern"
	save_btn.position = Vector2(60, 624)
	save_btn.size = Vector2(190, 46)
	save_btn.add_theme_font_size_override("font_size", 18)
	save_btn.pressed.connect(_shipyard_save)
	shipyard_panel.add_child(save_btn)

	var back_btn := Button.new()
	back_btn.text = "Verwerfen"
	back_btn.position = Vector2(262, 624)
	back_btn.size = Vector2(118, 46)
	back_btn.add_theme_font_size_override("font_size", 15)
	back_btn.pressed.connect(_shipyard_cancel)
	shipyard_panel.add_child(back_btn)

# One editor row: category label + ◀ [value] ▶ at vertical offset y.
func _shipyard_row(cat_key: String, title: String, y: float) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.position = Vector2(60, y)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", COL_DIM)
	shipyard_panel.add_child(lbl)

	var left := Button.new()
	left.text = "◀"
	left.position = Vector2(60, y + 22)
	left.size = Vector2(42, 34)
	left.add_theme_font_size_override("font_size", 16)
	left.pressed.connect(_shipyard_cycle.bind(cat_key, -1))
	shipyard_panel.add_child(left)

	var val := Label.new()
	val.position = Vector2(106, y + 22)
	val.size = Vector2(226, 34)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val.add_theme_font_size_override("font_size", 17)
	val.add_theme_color_override("font_color", COL_TEXT)
	shipyard_panel.add_child(val)
	shipyard_val_labels[cat_key] = val

	var right := Button.new()
	right.text = "▶"
	right.position = Vector2(336, y + 22)
	right.size = Vector2(42, 34)
	right.add_theme_font_size_override("font_size", 16)
	right.pressed.connect(_shipyard_cycle.bind(cat_key, 1))
	shipyard_panel.add_child(right)

func _open_shipyard() -> void:
	_shipyard_backup = ship_design.duplicate()
	state = STATE_SHIPYARD
	if home_panel != null:
		home_panel.visible = false
	if shipyard_panel != null:
		shipyard_panel.visible = true
	# Centre + spin the ship like the home turntable.
	if p_node != null:
		p_node.position = Vector3.ZERO
	home_ship_spin = 0.0
	_shipyard_refresh_labels()

func _shipyard_cycle(cat_key: String, dir: int) -> void:
	match cat_key:
		"palette":
			var pn: int = SHIP_PALETTES.size()
			ship_design["palette"] = (int(ship_design.get("palette", 0)) + dir + pn) % pn
		"wings":
			ship_design["wings"] = _cycle_str(SHIP_WING_OPTS, str(ship_design.get("wings", "swept")), dir)
		"engines":
			var en: int = SHIP_ENGINE_OPTS.size()
			var ec: int = SHIP_ENGINE_OPTS.find(int(ship_design.get("engines", 2)))
			if ec < 0:
				ec = 0
			ship_design["engines"] = SHIP_ENGINE_OPTS[(ec + dir + en) % en]
		"tail":
			ship_design["tail"] = _cycle_str(SHIP_TAIL_OPTS, str(ship_design.get("tail", "twin")), dir)
		"nose":
			ship_design["nose"] = _cycle_str(SHIP_NOSE_OPTS, str(ship_design.get("nose", "pointed")), dir)
		"leds":
			ship_design["leds"] = _cycle_str(SHIP_LED_OPTS, str(ship_design.get("leds", "auto")), dir)
	_rebuild_player_ship()
	_shipyard_refresh_labels()

# Wrap-around cycle of a string option within its list.
func _cycle_str(opts: Array, cur_val: String, dir: int) -> String:
	var n: int = opts.size()
	var i: int = opts.find(cur_val)
	if i < 0:
		i = 0
	return str(opts[(i + dir + n) % n])

func _shipyard_refresh_labels() -> void:
	for key in shipyard_val_labels:
		shipyard_val_labels[key].text = _shipyard_value_text(str(key))

# Human-readable current value shown in an editor row.
func _shipyard_value_text(key: String) -> String:
	match key:
		"palette":
			var pi: int = clampi(int(ship_design.get("palette", 0)), 0, SHIP_PALETTES.size() - 1)
			return str(SHIP_PALETTES[pi]["name"])
		"wings":
			return str(SHIP_WING_LABELS.get(str(ship_design.get("wings", "swept")), "—"))
		"engines":
			return str(int(ship_design.get("engines", 2)))
		"tail":
			return str(SHIP_TAIL_LABELS.get(str(ship_design.get("tail", "twin")), "—"))
		"nose":
			return str(SHIP_NOSE_LABELS.get(str(ship_design.get("nose", "pointed")), "—"))
		"leds":
			return str(SHIP_LED_LABELS.get(str(ship_design.get("leds", "auto")), "—"))
	return "—"

func _shipyard_save() -> void:
	_save_settings()
	_show_home()

func _shipyard_cancel() -> void:
	if ship_design != _shipyard_backup:
		ship_design = _shipyard_backup.duplicate()
		_rebuild_player_ship()
	_show_home()

# Frees and rebuilds the player ship from the current ship_design, preserving the
# node's transform. Used live in the hangar on each option change.
func _rebuild_player_ship() -> void:
	var old_pos := p_pos
	var old_rot := Vector3.ZERO
	if p_node != null:
		old_pos = p_node.position
		old_rot = p_node.rotation
		p_node.queue_free()
	p_pulse_lights.clear()   # _assemble_ship_body re-appends; avoid stale freed refs
	_build_player()
	if p_node != null:
		p_node.position = old_pos
		p_node.rotation = old_rot

# ============================================================
# Social — emote wheel (hold ALT) + chat (Enter). Build, update, networking.
# ============================================================
func _load_emoji_font() -> void:
	# Windows colour-emoji font so emotes render in colour. Missing file
	# (non-Windows / odd install) → null, emotes fall back to the default font.
	var path := "C:/Windows/Fonts/seguiemj.ttf"
	if FileAccess.file_exists(path):
		var f := FontFile.new()
		if f.load_dynamic_font(path) == OK:
			emoji_font = f

func _build_social_ui() -> void:
	# Chat (bottom-left) — added to `hud` AFTER the overlay panels so the input
	# draws on top, including over the ESC pause screen.
	chat_root = Control.new()
	chat_root.size = Vector2(1280, 720)
	chat_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_root.visible = false
	hud.add_child(chat_root)

	chat_log_label = Label.new()
	chat_log_label.position = Vector2(18, 446)
	chat_log_label.size = Vector2(444, 168)
	chat_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	chat_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_log_label.add_theme_font_size_override("font_size", 13)
	chat_log_label.add_theme_color_override("font_color", COL_TEXT)
	chat_log_label.modulate = Color(1, 1, 1, 0.85)
	chat_root.add_child(chat_log_label)

	chat_input = LineEdit.new()
	chat_input.position = Vector2(18, 620)
	chat_input.size = Vector2(444, 30)
	chat_input.max_length = CHAT_MAX_LEN
	chat_input.placeholder_text = "Nachricht … (Enter senden · Esc abbrechen)"
	chat_input.visible = false
	chat_input.add_theme_font_size_override("font_size", 14)
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_root.add_child(chat_input)

	# Emote wheel (hidden until ALT is held).
	var wheel := EmoteWheel.new()
	wheel.size = Vector2(1280, 720)
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.visible = false
	hud.add_child(wheel)
	wheel.setup(EMOTES, emoji_font)
	emote_wheel = wheel

func _update_social(delta: float) -> void:
	_update_emotes(delta)
	_update_emote_wheel()
	if announce_timer > 0.0:
		announce_timer -= delta
		if announce_timer <= 0.0 and announce_label != null:
			announce_label.visible = false

# ---- Emote wheel selection ----
func _update_emote_wheel() -> void:
	if emote_wheel == null:
		return
	var allowed: bool = state == STATE_PLAYING and not menu_open and not chat_typing and net_mode != NetMode.SERVER
	var alt: bool = allowed and Input.is_key_pressed(KEY_ALT)
	if alt and not emote_wheel_open:
		emote_wheel_open = true
		emote_wheel.set_hovered(-1)
		emote_wheel.visible = true
	elif emote_wheel_open and not alt:
		var chosen: int = emote_wheel.hovered
		emote_wheel_open = false
		emote_wheel.visible = false
		if chosen >= 0:
			_fire_emote(chosen)
	if emote_wheel_open:
		var v: Vector2 = emote_wheel.get_local_mouse_position() - emote_wheel.wheel_center
		if v.length() < 48.0:
			emote_wheel.set_hovered(-1)   # centre deadzone = cancel
		else:
			var step: float = TAU / float(emote_wheel.seg_count)
			var rel: float = fposmod(atan2(v.y, v.x) + PI / 2.0, TAU)
			emote_wheel.set_hovered(int(round(rel / step)) % emote_wheel.seg_count)

func _fire_emote(idx: int) -> void:
	idx = clampi(idx, 0, EMOTES.size() - 1)
	if net_mode == NetMode.CLIENT and net_connected:
		submit_emote.rpc_id(1, idx)   # server echoes to everyone, incl. us
	else:
		_show_emote_above(-1, idx)    # offline: show locally

# ---- Emote billboards (Label3D floating above a ship) ----
func _show_emote_above(id: int, idx: int) -> void:
	if world == null:
		return
	idx = clampi(idx, 0, EMOTES.size() - 1)
	# One emote per player at a time — replace any existing one.
	for e in active_emotes:
		if int(e.get("follow", -999)) == id:
			if e["label"] != null:
				e["label"].queue_free()
			active_emotes.erase(e)
			break
	var lbl := Label3D.new()
	lbl.text = str(EMOTES[idx])
	if emoji_font != null:
		lbl.font = emoji_font
	lbl.font_size = 200
	lbl.pixel_size = 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = false
	lbl.render_priority = 10
	lbl.outline_size = 26
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	world.add_child(lbl)
	lbl.position = _emote_follow_pos(id) + EMOTE_OFFSET
	active_emotes.append({"label": lbl, "follow": id, "timer": EMOTE_DURATION})

func _emote_follow_pos(id: int) -> Vector3:
	if id == -1:
		return p_pos
	if net_mode == NetMode.CLIENT and id == multiplayer.get_unique_id():
		return p_pos
	if remote_players.has(id):
		var node = remote_players[id].get("node")
		if node != null:
			return node.position
	return p_pos

func _update_emotes(delta: float) -> void:
	if active_emotes.is_empty():
		return
	var keep: Array = []
	for e in active_emotes:
		e["timer"] = float(e["timer"]) - delta
		if e["timer"] <= 0.0 or e["label"] == null:
			if e["label"] != null:
				e["label"].queue_free()
			continue
		e["label"].position = _emote_follow_pos(int(e["follow"])) + EMOTE_OFFSET
		keep.append(e)
	active_emotes = keep

func _clear_emotes() -> void:
	for e in active_emotes:
		if e["label"] != null:
			e["label"].queue_free()
	active_emotes.clear()
	emote_wheel_open = false
	if emote_wheel != null:
		emote_wheel.visible = false

# ---- Chat ----
func _open_chat() -> void:
	if chat_input == null or chat_typing:
		return
	chat_typing = true
	chat_root.visible = true
	chat_root.move_to_front()   # draw above the ESC pause panel
	chat_input.visible = true
	chat_input.text = ""
	chat_input.grab_focus()

func _close_chat() -> void:
	if chat_input == null:
		return
	chat_input.visible = false
	chat_input.release_focus()
	chat_typing = false

func _on_chat_submitted(text: String) -> void:
	_send_chat(text)
	_close_chat()

func _send_chat(text: String) -> void:
	var clean := text.strip_edges()
	if clean.length() > CHAT_MAX_LEN:
		clean = clean.substr(0, CHAT_MAX_LEN)
	if clean.is_empty():
		return
	if net_mode == NetMode.CLIENT and net_connected:
		submit_chat.rpc_id(1, clean)   # server echoes to everyone, incl. us
	else:
		_append_chat("%s: %s" % [player_name, clean])

func _append_chat(line: String) -> void:
	chat_messages.append(line)
	if chat_messages.size() > CHAT_HISTORY:
		chat_messages = chat_messages.slice(chat_messages.size() - CHAT_HISTORY)
	if chat_log_label != null:
		var start: int = maxi(0, chat_messages.size() - CHAT_MAX_LINES)
		chat_log_label.text = "\n".join(chat_messages.slice(start))

# Switch to the home screen: hide the gameplay HUD + any overlay, show the menu,
# refresh its content and kick off a fresh server reachability probe.
func _show_home() -> void:
	state = STATE_HOME
	menu_open = false
	_close_chat()
	_clear_emotes()
	if chat_root != null:
		chat_root.visible = false
	if hud_game != null:
		hud_game.visible = false
	if levelup_panel != null:
		levelup_panel.visible = false
	if go_panel != null:
		go_panel.visible = false
	if esc_panel != null:
		esc_panel.visible = false
	if settings_panel != null:
		settings_panel.visible = false
	if shipyard_panel != null:
		shipyard_panel.visible = false
	if home_panel != null:
		home_panel.visible = true
	if home_name_edit != null:
		home_name_edit.text = player_name
	if home_coop_btn != null:
		# Online play ("Spielen") is the default: always accented + focused (Enter starts it).
		home_coop_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
		home_coop_btn.grab_focus()
	_refresh_home_best()
	_refresh_home_board()
	_home_probe()

func _home_update(delta: float) -> void:
	_animate_background(delta * 0.4)
	# Slow turntable spin of the showcased ship.
	if p_node != null:
		home_ship_spin += delta * 0.4
		p_node.rotation.z = home_ship_spin
	# Keep the camera framed on the ship at the origin.
	if cam != null:
		cam.position = cam.position.lerp(cam_base_pos, clamp(delta * 4.0, 0.0, 1.0))
		cam.look_at(Vector3.ZERO, Vector3.UP)
	# Reachability probe: count down the connection / data-collection window.
	if home_probing:
		probe_timer -= delta
		if probe_timer <= 0.0:
			_home_probe_finish()

func _refresh_home_best() -> void:
	if home_best_label == null:
		return
	if best_level <= 0:
		home_best_label.text = "Noch kein Lauf.\nStürz dich ins Getümmel!"
	else:
		home_best_label.text = "Level %d\nWelle %d   ·   %d Kills\nZeit %d:%02d" % [
			best_level, best_wave, best_kills, best_time / 60, best_time % 60]

func _refresh_home_board() -> void:
	if home_board_label != null:
		home_board_label.text = _highscore_text(13)

# Lightweight reachability check: briefly connect, pull the roster + board, then
# disconnect again. We do NOT stay connected or render the streamed world (guards
# in spawn_enemy / receive_world / receive_bullets skip while home_probing).
func _home_probe() -> void:
	if home_probing:
		return
	if net_server_ip.is_empty():
		net_server_ip = DEFAULT_SERVER
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	net_connected = false
	net_roster.clear()
	home_probing = true
	probe_timer = 4.0   # connection timeout; shrinks to ~0.8s once connected
	net_mode = NetMode.CLIENT   # so receive_roster / receive_highscores dispatch
	if home_status_label != null:
		home_status_label.text = "Server: verbinde …"
	_start_client()

func _home_probe_finish() -> void:
	if not home_probing:
		return
	var was_connected := net_connected
	var others: int = maxi(0, net_roster.size() - 1)
	home_probing = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	net_connected = false
	net_mode = NetMode.SINGLE
	_coop_clear_world()   # drop anything that streamed in during the probe
	if home_status_label != null:
		home_status_label.text = ("● Server online  —  %d Spieler" % others) if was_connected else "○ Server offline"

# Frees every client-mirrored entity (enemies / bullets / gems / remote players)
# and clears the parallel arrays. Used before joining co-op and after a probe.
func _coop_clear_world() -> void:
	for d in [cl_enemies, cl_pbullets, cl_ebullets, cl_gems]:
		for k in d.keys():
			var ent = d[k]
			if ent != null and ent.node != null:
				ent.node.queue_free()
		d.clear()
	for id in remote_players.keys():
		var rp = remote_players[id]
		if rp != null and rp.get("node") != null:
			rp["node"].queue_free()
	remote_players.clear()
	cl_designs.clear()
	_clear_emotes()
	for f in friendlies:
		if f != null and f.node != null:
			f.node.queue_free()
	friendlies.clear()
	cl_friendlies.clear()
	_apply_objective("")
	enemies.clear()
	p_bullets.clear()
	e_bullets.clear()
	gems.clear()

# Shared setup when leaving the home screen for a run.
func _begin_play_common() -> void:
	player_name = _sanitize_name(player_name)
	if home_name_edit != null:
		home_name_edit.text = player_name
	_save_settings()
	if home_panel != null:
		home_panel.visible = false
	if hud_game != null:
		hud_game.visible = true
	if chat_root != null:
		chat_root.visible = true
	home_ship_spin = 0.0
	if p_node != null:
		p_node.rotation.z = 0.0

func _home_play_single() -> void:
	home_probing = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	net_connected = false
	net_mode = NetMode.SINGLE
	_begin_play_common()
	# Local single-player board lives in the same file the server uses for its global one.
	_coop_clear_world()
	highscores = []
	_load_highscores_server()
	_restart_run()   # full clean local run; sets STATE_PLAYING

func _home_play_coop() -> void:
	home_probing = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	net_connected = false
	if net_server_ip.is_empty():
		net_server_ip = DEFAULT_SERVER
	net_mode = NetMode.CLIENT
	_begin_play_common()
	_coop_clear_world()
	_reset_player_progression()
	p_pos = Vector3.ZERO
	if p_node != null:
		p_node.position = p_pos
	run_time = 0.0
	kills = 0
	wave = 1
	wave_timer = WAVE_DURATION
	p_invuln_timer = maxf(p_invuln_timer, 2.0)
	score_submitted = false
	state = STATE_PLAYING
	_start_client()

func _home_quit() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	get_tree().quit()

# True if a (level, wave, kills, time) run beats the stored personal best, using the
# same ordering as the leaderboard (level → wave → kills → shorter time).
func _is_better_run(lv: int, wv: int, kl: int, tm: int) -> bool:
	if lv != best_level:
		return lv > best_level
	if wv != best_wave:
		return wv > best_wave
	if kl != best_kills:
		return kl > best_kills
	return tm < best_time

func _update_personal_best() -> void:
	var tm := int(run_time)
	if best_level == 0 or _is_better_run(p_level, wave, kills, tm):
		best_level = p_level
		best_wave = wave
		best_kills = kills
		best_time = tm
		_save_settings()

# ============================================================
# Settings persistence (client/single-player only)
# ============================================================

func _load_settings() -> void:
	player_name = "Pilot-%d" % (randi() % 9000 + 1000)
	ship_design = DEFAULT_SHIP_DESIGN.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK:
		player_name = str(cfg.get_value("player", "name", player_name))
		master_vol_db = float(cfg.get_value("audio", "master_db", 0.0))
		fullscreen_on = bool(cfg.get_value("display", "fullscreen", false))
		best_level = int(cfg.get_value("best", "level", 0))
		best_wave = int(cfg.get_value("best", "wave", 0))
		best_kills = int(cfg.get_value("best", "kills", 0))
		best_time = int(cfg.get_value("best", "time", 0))
		# Ship design — read raw, then run through the same validator the server
		# uses so a hand-edited or stale file can never produce invalid parts.
		ship_design = _sanitize_ship_design({
			"palette": cfg.get_value("ship", "palette", 0),
			"wings": cfg.get_value("ship", "wings", "swept"),
			"engines": cfg.get_value("ship", "engines", 2),
			"tail": cfg.get_value("ship", "tail", "twin"),
			"nose": cfg.get_value("ship", "nose", "pointed"),
			"leds": cfg.get_value("ship", "leds", "auto"),
		})
	player_name = _sanitize_name(player_name)

func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, master_vol_db)
	if fullscreen_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("audio", "master_db", master_vol_db)
	cfg.set_value("display", "fullscreen", fullscreen_on)
	cfg.set_value("best", "level", best_level)
	cfg.set_value("best", "wave", best_wave)
	cfg.set_value("best", "kills", best_kills)
	cfg.set_value("best", "time", best_time)
	cfg.set_value("ship", "palette", int(ship_design.get("palette", 0)))
	cfg.set_value("ship", "wings", str(ship_design.get("wings", "swept")))
	cfg.set_value("ship", "engines", int(ship_design.get("engines", 2)))
	cfg.set_value("ship", "tail", str(ship_design.get("tail", "twin")))
	cfg.set_value("ship", "nose", str(ship_design.get("nose", "pointed")))
	cfg.set_value("ship", "leds", str(ship_design.get("leds", "auto")))
	cfg.save(SETTINGS_FILE)

# ============================================================
# Self-updater — checks GitHub Releases, downloads the new exe, and
# swaps it in via a helper batch on the next launch.
# Releases are tagged "v<GAME_VERSION>" and carry one asset named
# "Sternenflucht.exe" (the single embedded-pck build).
# ============================================================

func _build_updater_ui() -> void:
	updater_layer = CanvasLayer.new()
	updater_layer.layer = 100   # above the HUD
	add_child(updater_layer)
	var panel := ColorRect.new()
	panel.name = "panel"
	panel.color = Color(0.04, 0.06, 0.12, 0.92)
	panel.position = Vector2(340, 8)
	panel.size = Vector2(600, 40)
	updater_layer.add_child(panel)
	updater_label = Label.new()
	updater_label.position = Vector2(12, 0)
	updater_label.size = Vector2(380, 40)
	updater_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	updater_label.add_theme_font_size_override("font_size", 13)
	updater_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	panel.add_child(updater_label)
	updater_btn_yes = Button.new()
	updater_btn_yes.text = "Aktualisieren"
	updater_btn_yes.position = Vector2(400, 6)
	updater_btn_yes.size = Vector2(110, 28)
	updater_btn_yes.add_theme_font_size_override("font_size", 12)
	updater_btn_yes.pressed.connect(_on_update_accept)
	panel.add_child(updater_btn_yes)
	updater_btn_no = Button.new()
	updater_btn_no.text = "Später"
	updater_btn_no.position = Vector2(516, 6)
	updater_btn_no.size = Vector2(72, 28)
	updater_btn_no.add_theme_font_size_override("font_size", 12)
	updater_btn_no.pressed.connect(_on_update_dismiss)
	panel.add_child(updater_btn_no)
	updater_layer.visible = false   # hidden until an update is found

	http_check = HTTPRequest.new()
	add_child(http_check)
	http_check.request_completed.connect(_on_version_check_completed)
	http_download = HTTPRequest.new()
	add_child(http_download)
	http_download.request_completed.connect(_on_update_download_completed)

func _check_for_updates() -> void:
	var url := "https://api.github.com/repos/%s/releases/latest" % UPDATE_REPO
	# GitHub requires a User-Agent; the Accept header pins the API version.
	var headers := ["User-Agent: Sternenflucht-Updater",
		"Accept: application/vnd.github+json"]
	var err := http_check.request(url, headers)
	if err != OK:
		push_warning("Update-Check fehlgeschlagen (request): %d" % err)

func _on_version_check_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("Update-Check: HTTP %d (result %d)" % [code, result])
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Update-Check: ungültige Antwort")
		return
	var tag := String(data.get("tag_name", ""))
	var remote_ver := tag.lstrip("v")
	if remote_ver == "" or not _version_is_newer(remote_ver, GAME_VERSION):
		return   # already up to date
	# Find the Windows exe asset.
	var dl_url := ""
	for a in data.get("assets", []):
		if String(a.get("name", "")) == "Sternenflucht.exe":
			dl_url = String(a.get("browser_download_url", ""))
			break
	if dl_url == "":
		push_warning("Update %s gefunden, aber kein Sternenflucht.exe-Asset" % tag)
		return
	update_new_version = remote_ver
	update_asset_url = dl_url
	_show_update_banner()

# Returns true if semver string `a` is strictly newer than `b`.
func _version_is_newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in range(max(pa.size(), pb.size())):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return na > nb
	return false

func _show_update_banner() -> void:
	updater_label.text = "Neue Version v%s verfügbar (du hast v%s)" % [update_new_version, GAME_VERSION]
	updater_btn_yes.disabled = false
	updater_layer.visible = true

func _on_update_dismiss() -> void:
	updater_layer.visible = false

func _on_update_accept() -> void:
	if update_asset_url == "":
		return
	updater_btn_yes.disabled = true
	updater_label.text = "Lade v%s …" % update_new_version
	var target := OS.get_executable_path().get_base_dir().path_join("Sternenflucht_update.exe")
	http_download.download_file = target
	var headers := ["User-Agent: Sternenflucht-Updater"]
	var err := http_download.request(update_asset_url, headers)
	if err != OK:
		updater_label.text = "Download fehlgeschlagen (%d)" % err
		updater_btn_yes.disabled = false

func _on_update_download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 0):
		updater_label.text = "Download fehlgeschlagen (HTTP %d)" % code
		updater_btn_yes.disabled = false
		return
	updater_label.text = "Installiere v%s, starte neu …" % update_new_version
	_apply_update_and_restart()

# A running exe can't overwrite itself on Windows, so we spawn a detached
# batch that waits for this process to exit, swaps the file, and relaunches.
func _apply_update_and_restart() -> void:
	var exe_path := OS.get_executable_path()
	var dir := exe_path.get_base_dir()
	var new_exe := dir.path_join("Sternenflucht_update.exe")
	var bat_path := dir.path_join("apply_update.bat")
	var pid := OS.get_process_id()
	var bat := "@echo off\r\n"
	bat += ":waitloop\r\n"
	bat += "tasklist /FI \"PID eq %d\" 2>nul | find \"%d\" >nul\r\n" % [pid, pid]
	bat += "if not errorlevel 1 (\r\n"
	bat += "  timeout /t 1 /nobreak >nul\r\n"
	bat += "  goto waitloop\r\n"
	bat += ")\r\n"
	bat += "move /Y \"%s\" \"%s\" >nul\r\n" % [new_exe.replace("/", "\\"), exe_path.replace("/", "\\")]
	bat += "start \"\" \"%s\"\r\n" % exe_path.replace("/", "\\")
	bat += "del \"%~f0\"\r\n"
	var f := FileAccess.open(bat_path, FileAccess.WRITE)
	if f == null:
		updater_label.text = "Update fehlgeschlagen (Schreibrechte?)"
		updater_btn_yes.disabled = false
		return
	f.store_string(bat)
	f.close()
	# Launch the helper detached, then quit so it can replace this exe.
	OS.create_process("cmd.exe", ["/c", "start", "", "/min", bat_path.replace("/", "\\")])
	get_tree().quit()
