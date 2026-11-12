extends Node2D

const WORLD := Vector2(2400, 1500)
const PLAYER_SPEED := 255.0
const ENEMY_COUNT := 12
const SAVE_PATH := "user://nocturne_save.cfg"

enum Mode { MENU, PLAYING, PAUSED, GAME_OVER, VICTORY }
var mode: Mode = Mode.MENU
var player := Vector2(420, 760)
var aim := Vector2(1, 0)
var hp := 100.0
var ammo := 24
var reserve_ammo := 96
var magazine := 24
var score := 0
var mission_time := 0.0
var shots_cooldown := 0.0
var reload_time := 0.0
var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var joystick_id := -1
var joystick_origin := Vector2.ZERO
var joystick_vector := Vector2.ZERO
var fire_touch := false
var fire_button := Rect2()
var reload_button := Rect2()
var pause_button := Rect2()
var settings := {"music": 0.7, "sfx": 0.8, "vibration": true, "quality": 1}
var mission_text := "ATTEIGNEZ LE POINT D'EXTRACTION"
var extraction := Vector2(2070, 760)
var camera := Vector2.ZERO
var menu_selection := 0
var hit_flash := 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	_load_settings()
	get_viewport().size_changed.connect(queue_redraw)
	set_process(true)
	_spawn_enemies()

func _process(delta: float) -> void:
	if mode == Mode.PLAYING:
		_update_game(delta)
	elif mode == Mode.MENU:
		pass
	queue_redraw()

func _update_game(delta: float) -> void:
	mission_time += delta
	shots_cooldown = maxf(0.0, shots_cooldown - delta)
	reload_time = maxf(0.0, reload_time - delta)
	hit_flash = maxf(0.0, hit_flash - delta * 2.5)

	var direction := _get_move_input()
	if direction.length() > 1.0:
		direction = direction.normalized()
	player += direction * PLAYER_SPEED * delta
	player.x = clampf(player.x, 55, WORLD.x - 55)
	player.y = clampf(player.y, 55, WORLD.y - 55)
	camera = player - get_viewport_rect().size * 0.5
	camera.x = clampf(camera.x, 0, WORLD.x - get_viewport_rect().size.x)
	camera.y = clampf(camera.y, 0, WORLD.y - get_viewport_rect().size.y)

	if Input.is_action_pressed("fire") and shots_cooldown <= 0.0:
		_fire()
	if fire_touch and shots_cooldown <= 0.0:
		_fire()

	for enemy in enemies:
		if not enemy.alive:
			continue
		var to_player: Vector2 = player - enemy.pos
		var distance := to_player.length()
		if distance < 560.0:
			enemy.alert = minf(1.0, enemy.alert + delta * 1.8)
			if distance > 180.0:
				enemy.pos += to_player.normalized() * enemy.speed * delta
			elif distance < 145.0:
				enemy.pos -= to_player.normalized() * enemy.speed * 0.4 * delta
			if distance < 330.0:
				enemy.cooldown -= delta
				if enemy.cooldown <= 0.0:
					enemy.cooldown = rng.randf_range(0.9, 1.8)
					if rng.randf() < 0.68:
						hp -= rng.randf_range(4.0, 9.0)
						hit_flash = 0.8
						_spawn_particles(player, Color(0.8, 0.12, 0.1), 5)
		else:
			enemy.patrol += delta
			enemy.pos += Vector2(sin(enemy.patrol), cos(enemy.patrol * 0.7)) * 12.0 * delta

	for bullet in bullets:
		bullet.pos += bullet.dir * bullet.speed * delta
		bullet.life -= delta
		for enemy in enemies:
			if enemy.alive and bullet.pos.distance_to(enemy.pos) < 28:
				enemy.hp -= bullet.damage
				bullet.life = 0
				_spawn_particles(enemy.pos, Color(1.0, 0.55, 0.25), 7)
				if enemy.hp <= 0:
					enemy.alive = false
					score += 100
					_spawn_particles(enemy.pos, Color(0.9, 0.2, 0.12), 14)
				break
	bullets = bullets.filter(func(b): return b.life > 0.0)
	for p in particles:
		p.pos += p.vel * delta
		p.life -= delta
	particles = particles.filter(func(p): return p.life > 0.0)

	if hp <= 0:
		hp = 0
		mode = Mode.GAME_OVER
	elif player.distance_to(extraction) < 75:
		mode = Mode.VICTORY
		_save_progress()

func _get_move_input() -> Vector2:
	var d := Vector2.ZERO
	d.x = float(Input.is_action_pressed("move_right")) - float(Input.is_action_pressed("move_left"))
	d.y = float(Input.is_action_pressed("move_down")) - float(Input.is_action_pressed("move_up"))
	return d + joystick_vector

func _fire() -> void:
	if ammo <= 0 or reload_time > 0:
		return
	ammo -= 1
	shots_cooldown = 0.19
	var direction := aim.normalized()
	bullets.append({"pos": player + direction * 34, "dir": direction, "speed": 920.0, "life": 1.1, "damage": 34.0})
	_spawn_particles(player + direction * 34, Color(1.0, 0.75, 0.3), 3)

func _reload() -> void:
	if reload_time > 0 or ammo >= magazine or reserve_ammo <= 0:
		return
	reload_time = 1.35
	await get_tree().create_timer(1.35).timeout
	if mode == Mode.PLAYING:
		var amount: int = mini(magazine - ammo, reserve_ammo)
		ammo += amount
		reserve_ammo -= amount

func _spawn_enemies() -> void:
	enemies.clear()
	for i in range(ENEMY_COUNT):
		var p := Vector2(rng.randf_range(850, 1900), rng.randf_range(180, 1320))
		enemies.append({"pos": p, "hp": 68.0, "alive": true, "speed": rng.randf_range(48, 78), "alert": 0.0, "cooldown": rng.randf_range(0.5, 2.0), "patrol": rng.randf_range(0, 10)})

func _spawn_particles(at: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		var a := rng.randf_range(0, TAU)
		particles.append({"pos": at, "vel": Vector2.RIGHT.rotated(a) * rng.randf_range(35, 190), "life": rng.randf_range(0.12, 0.38), "color": color})

func _draw() -> void:
	var screen := get_viewport_rect().size
	if mode == Mode.MENU:
		_draw_menu(screen)
		return
	if mode == Mode.PLAYING or mode == Mode.PAUSED or mode == Mode.GAME_OVER or mode == Mode.VICTORY:
		_draw_world(screen)
		_draw_hud(screen)
	if mode == Mode.PAUSED:
		_draw_overlay(screen, "PAUSE", "Reprendre     |     Menu principal")
	elif mode == Mode.GAME_OVER:
		_draw_overlay(screen, "MISSION ÉCHOUÉE", "Toucher pour recommencer")
	elif mode == Mode.VICTORY:
		_draw_overlay(screen, "EXTRACTION RÉUSSIE", "ZONE SÉCURISÉE  •  Toucher pour rejouer")

func _draw_menu(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color("#081018"))
	for i in range(18):
		var x := fposmod(float(i) * 137.0, s.x)
		draw_line(Vector2(x, 0), Vector2(x - 160, s.y), Color(0.12, 0.19, 0.22, 0.25), 1)
	draw_circle(Vector2(s.x * 0.72, s.y * 0.48), s.y * 0.34, Color("#101e26"))
	draw_string(ThemeDB.fallback_font, Vector2(s.x * 0.09, s.y * 0.29), "NOCTURNE", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color("#e8edf0"))
	draw_string(ThemeDB.fallback_font, Vector2(s.x * 0.095, s.y * 0.36), "PROTOCOLE ZÉRO  /  OPÉRATION 001", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#df6b48"))
	draw_string(ThemeDB.fallback_font, Vector2(s.x * 0.095, s.y * 0.52), "UNE VILLE. UN SECRET. AUCUNE EXTRACTION GARANTIE.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#9baab1"))
	_draw_button(Rect2(s.x * 0.095, s.y * 0.64, 260, 58), "NOUVELLE OPÉRATION", Color("#b74e35"))
	_draw_button(Rect2(s.x * 0.095, s.y * 0.75, 260, 48), "PARAMÈTRES", Color("#263640"))
	draw_string(ThemeDB.fallback_font, Vector2(s.x * 0.095, s.y * 0.92), "BUILD 0.1.0  •  MOBILE / PC  •  18+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#657780"))

func _draw_world(s: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color("#10191d"))
	var tile := 120
	for x in range(int(camera.x / tile) * tile, int(camera.x + s.x) + tile, tile):
		for y in range(int(camera.y / tile) * tile, int(camera.y + s.y) + tile, tile):
			var rect := Rect2(Vector2(x, y) - camera, Vector2(tile - 5, tile - 5))
			draw_rect(rect, Color("#172327") if ((x / tile + y / tile) % 2 == 0) else Color("#1b292d"))
			draw_rect(Rect2(rect.position + Vector2(9, 9), rect.size - Vector2(18, 18)), Color("#1c2b30"), false, 1)
	# Obstacles and ruined structures
	for i in range(16):
		var ox := 250 + i * 137
		var oy := 180 + (i % 5) * 245
		var r := Rect2(Vector2(ox, oy) - camera, Vector2(76, 90))
		draw_rect(r, Color("#344247"))
		draw_rect(r, Color("#566166"), false, 2)
	# Extraction zone
	var ex := extraction - camera
	draw_circle(ex, 78, Color(0.1, 0.8, 0.55, 0.10))
	draw_arc(ex, 78, 0, TAU, 48, Color("#45d6a2"), 3)
	draw_string(ThemeDB.fallback_font, ex + Vector2(-50, -92), "EXTRACTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#45d6a2"))
	for enemy in enemies:
		if enemy.alive:
			var p: Vector2 = enemy.pos - camera
			draw_circle(p, 17, Color("#9f4238"))
			draw_circle(p + Vector2(0, -3), 7, Color("#e7b4a0"))
			draw_arc(p, 23, 0, TAU, 24, Color(0.9, 0.25, 0.2, 0.65), 2)
	for bullet in bullets:
		draw_circle(bullet.pos - camera, 4, Color("#ffd27a"))
	for p in particles:
		draw_circle(p.pos - camera, 3, p.color)
	var pp := player - camera
	draw_circle(pp, 20, Color("#d5d9d5"))
	draw_circle(pp + aim.normalized() * 13, 7, Color("#df754e"))
	draw_arc(pp, 25, 0, TAU, 24, Color("#f0eee8"), 2)
	if hit_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.8, 0.05, 0.03, hit_flash * 0.13))

func _draw_hud(s: Vector2) -> void:
	draw_rect(Rect2(16, 16, 250, 78), Color(0.02, 0.04, 0.05, 0.82))
	draw_string(ThemeDB.fallback_font, Vector2(30, 43), "OPÉRATION 001  /  ZONE ROUGE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e7ecec"))
	draw_rect(Rect2(30, 55, 210, 13), Color("#422d2c"))
	draw_rect(Rect2(30, 55, 210 * hp / 100.0, 13), Color("#d35c49"))
	draw_string(ThemeDB.fallback_font, Vector2(30, 116), "MENACES : %d   •   SCORE : %d" % [_alive_enemies(), score], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#d6dfdf"))
	draw_rect(Rect2(s.x - 210, 16, 194, 76), Color(0.02, 0.04, 0.05, 0.82))
	draw_string(ThemeDB.fallback_font, Vector2(s.x - 192, 48), "%02d / %03d" % [ammo, reserve_ammo], HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color("#f1eee4"))
	draw_string(ThemeDB.fallback_font, Vector2(s.x - 192, 72), "MUNITIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#91a1a5"))
	# Mobile touch controls
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		draw_circle(Vector2(112, s.y - 115), 66, Color(0.1, 0.16, 0.18, 0.65))
		draw_circle(Vector2(112, s.y - 115) + joystick_vector * 37, 25, Color(0.75, 0.82, 0.82, 0.7))
		fire_button = Rect2(s.x - 145, s.y - 155, 112, 112)
		reload_button = Rect2(s.x - 270, s.y - 100, 95, 65)
		pause_button = Rect2(s.x - 68, 105, 52, 48)
		draw_circle(fire_button.get_center(), 49, Color(0.7, 0.2, 0.13, 0.72))
		draw_string(ThemeDB.fallback_font, fire_button.get_center() + Vector2(-23, 6), "TIR", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color.WHITE)
		_draw_button(reload_button, "RECHARGE", Color("#384b50"))
		_draw_button(pause_button, "Ⅱ", Color("#384b50"))

func _draw_button(r: Rect2, label: String, color: Color) -> void:
	draw_rect(r, color, true, 8)
	draw_rect(r, Color(0.8, 0.85, 0.85, 0.45), false, 2, 8)
	draw_string(ThemeDB.fallback_font, r.position + Vector2(13, r.size.y * 0.58), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func _draw_overlay(s: Vector2, title: String, subtitle: String) -> void:
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.02, 0.025, 0.78))
	draw_string(ThemeDB.fallback_font, Vector2(s.x * 0.5 - 190, s.y * 0.46), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color("#f1eee8"))
	draw_string(ThemeDB.fallback_font, Vector2(s.x * 0.5 - 190, s.y * 0.56), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#bdc9ca"))

func _alive_enemies() -> int:
	var count := 0
	for e in enemies:
		if e.alive:
			count += 1
	return count

func _start_game() -> void:
	player = Vector2(420, 760)
	hp = 100
	ammo = magazine
	reserve_ammo = 96
	score = 0
	mission_time = 0
	bullets.clear()
	particles.clear()
	_spawn_enemies()
	mode = Mode.PLAYING

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mode == Mode.PLAYING:
		aim = (event.position + camera - player).normalized()
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_touch_start(event.index, event.position)
		else:
			_handle_touch_end(event.index)
	if event is InputEventScreenDrag and mode == Mode.PLAYING:
		if event.index == joystick_id:
			joystick_vector = ((event.position - joystick_origin) / 55.0).limit_length(1.0)
		else:
			aim = (event.position + camera - player).normalized()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			mode = Mode.PAUSED if mode == Mode.PLAYING else Mode.PLAYING if mode == Mode.PAUSED else mode
		elif event.keycode == KEY_R and mode == Mode.PLAYING:
			_reload()
		elif event.keycode == KEY_ENTER and mode in [Mode.GAME_OVER, Mode.VICTORY]:
			_start_game()
		elif event.keycode == KEY_ENTER and mode == Mode.MENU:
			_start_game()
	if event is InputEventMouseButton and event.pressed:
		if mode == Mode.MENU:
			_start_game()
		elif mode in [Mode.GAME_OVER, Mode.VICTORY]:
			_start_game()
		elif mode == Mode.PAUSED:
			mode = Mode.PLAYING

func _handle_touch_start(index: int, pos: Vector2) -> void:
	var s := get_viewport_rect().size
	if mode == Mode.MENU:
		_start_game()
		return
	if mode in [Mode.GAME_OVER, Mode.VICTORY]:
		_start_game()
		return
	if mode == Mode.PAUSED:
		mode = Mode.PLAYING
		return
	if pos.x < s.x * 0.42 and pos.y > s.y * 0.55:
		joystick_id = index
		joystick_origin = Vector2(112, s.y - 115)
		joystick_vector = ((pos - joystick_origin) / 55.0).limit_length(1.0)
	elif fire_button.has_point(pos):
		fire_touch = true
		aim = (pos + camera - player).normalized()
	elif reload_button.has_point(pos):
		_reload()
	elif pause_button.has_point(pos):
		mode = Mode.PAUSED
	else:
		aim = (pos + camera - player).normalized()

func _handle_touch_end(index: int) -> void:
	if index == joystick_id:
		joystick_id = -1
		joystick_vector = Vector2.ZERO
	fire_touch = false

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		settings.music = cfg.get_value("audio", "music", 0.7)
		settings.sfx = cfg.get_value("audio", "sfx", 0.8)
		settings.vibration = cfg.get_value("game", "vibration", true)
		settings.quality = cfg.get_value("graphics", "quality", 1)

func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "best_score", maxi(score, int(cfg.get_value("progress", "best_score", 0))))
	cfg.set_value("progress", "completed", true)
	cfg.set_value("audio", "music", settings.music)
	cfg.set_value("audio", "sfx", settings.sfx)
	cfg.set_value("game", "vibration", settings.vibration)
	cfg.set_value("graphics", "quality", settings.quality)
	cfg.save(SAVE_PATH)

func _draw_settings() -> void:
	pass
