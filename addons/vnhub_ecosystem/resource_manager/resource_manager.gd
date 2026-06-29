extends Node
## ResourceManager
## Универсальный менеджер контент-паков для Godot-проекта (веб и десктоп).
## Скачивает/монтирует .pck (контент-пак), предзагружает его ассеты в фоне
## (threaded), отдаёт процент загрузки и опционально реагирует на Dialogic-сигналы
## для авто-предзагрузки наперёд.
##
## Регистрируется автоматически как Autoload под именем ResourceManager, когда
## включён плагин VNHub Ecosystem. Карта паков задаётся НЕ в этом скрипте, а в
## проекте — через VNHubResourceManagerConfig (.tres) или register_pack() в коде.
## Тогда отовсюду доступно: ResourceManager.load_pack(&"chapter_6")

# --- Сигналы -----------------------------------------------------------------

## Прогресс загрузки пака: id — ключ пака, percent — 0.0..100.0
signal load_progress(id: StringName, percent: float)
## Пак полностью готов (pck смонтирован + ассеты предзагружены)
signal load_completed(id: StringName)
## Загрузка не удалась (не скачался/не смонтировался pck и т.п.)
signal load_failed(id: StringName, reason: String)

# --- Где лежит конфиг ---------------------------------------------------------

## Project Setting с путём к .tres VNHubResourceManagerConfig.
## Регистрируется плагином (plugin.gd) при включении аддона.
const CONFIG_SETTING := "vnhub_ecosystem/resource_manager/config"

# --- Конфигурация (заполняется из VNHubResourceManagerConfig / register_*) ----

## База, откуда качаются паки на вебе. Должна заканчиваться на "/".
var base_url: String = ""

## Доля прогресса (0..100), отводимая под скачивание+монтирование пака.
var pack_weight: float = 40.0

# --- Внутреннее состояние ----------------------------------------------------

var _packs := {}            # StringName id -> VNHubContentPack
var _signal_to_pack := {}   # String signal arg -> StringName id
var _loaded := {}           # id -> true (готов)
var _mounted := {}          # имя пака -> true (смонтирован)
var _cache := {}            # path -> Resource (держим ссылки, чтобы предзагруженное не выгрузилось)
var _active: StringName = &""   # пак, который грузится прямо сейчас (&"" = простой)
var _queue: Array[StringName] = []

# --- Инициализация -----------------------------------------------------------

func _ready() -> void:
	_load_config_from_settings()

	var dlg := get_node_or_null("/root/Dialogic")
	if dlg and dlg.has_signal("signal_event"):
		dlg.signal_event.connect(_on_dialogic_signal)
	else:
		push_warning("ResourceManager: Dialogic.signal_event не найден — авто-предзагрузка по сигналам отключена.")


func _load_config_from_settings() -> void:
	if not ProjectSettings.has_setting(CONFIG_SETTING):
		return
	var path := String(ProjectSettings.get_setting(CONFIG_SETTING, ""))
	if path == "":
		return
	if not ResourceLoader.exists(path):
		push_warning("ResourceManager: конфиг не найден по пути %s" % path)
		return
	var cfg = load(path)
	if cfg is VNHubResourceManagerConfig:
		register_config(cfg)
	else:
		push_error("ResourceManager: %s не является VNHubResourceManagerConfig." % path)

# =============================================================================
# РЕГИСТРАЦИЯ ПАКОВ
# =============================================================================

## Применить конфиг целиком: общие параметры + все паки из него.
func register_config(config: VNHubResourceManagerConfig) -> void:
	if config == null:
		return
	base_url = config.base_url
	pack_weight = config.pack_weight
	for pack in config.packs:
		register_pack(pack)

## Зарегистрировать один пак (из инспектора или собранный в коде).
func register_pack(pack: VNHubContentPack) -> void:
	if pack == null or pack.id == &"":
		push_error("ResourceManager: register_pack — у пака пустой id.")
		return
	_packs[pack.id] = pack
	_signal_to_pack[pack.resolved_signal()] = pack.id

## (удобство) Зарегистрировать пак без создания ресурса вручную.
func register_pack_data(id: StringName, pack_name: String = "", assets: Array[String] = [], preload_signal: StringName = &"") -> void:
	var pack := VNHubContentPack.new()
	pack.id = id
	pack.pack_name = pack_name
	pack.assets = assets
	pack.preload_signal = preload_signal
	register_pack(pack)

## Список зарегистрированных id (для UI/отладки).
func get_pack_ids() -> Array:
	return _packs.keys()

# =============================================================================
# ПУБЛИЧНЫЙ API
# =============================================================================

## Загрузить пак по id. Прогресс — через сигнал load_progress,
## завершение — load_completed / load_failed. Можно и await-ить:
##     await ResourceManager.load_pack(&"chapter_6")
## Параллельные вызовы ставятся в очередь.
func load_pack(id: StringName) -> void:
	if not _packs.has(id):
		push_error("ResourceManager: неизвестный пак %s (не зарегистрирован)." % id)
		load_failed.emit(id, "Пак не зарегистрирован.")
		return
	if is_pack_loaded(id):
		load_progress.emit(id, 100.0)
		load_completed.emit(id)
		return
	if id != _active and not _queue.has(id):
		_queue.append(id)
	await _process_queue()

## Проверка, что пак полностью загружен.
func is_pack_loaded(id: StringName) -> bool:
	return _loaded.get(id, false)

## Идёт ли сейчас загрузка какого-либо пака.
func is_busy() -> bool:
	return _active != &""

## Освободить ассеты пака из памяти (VRAM/RAM).
## На вебе сам pck не выгружается (нет unload_resource_pack), но ссылки на
## ресурсы снимаются и текстуры уходят из видеопамяти.
func unload_pack(id: StringName) -> void:
	var pack: VNHubContentPack = _packs.get(id)
	if pack:
		for p in pack.assets:
			_cache.erase(p)
	_loaded.erase(id)

# =============================================================================
# ВНУТРЕННЯЯ ЛОГИКА
# =============================================================================

func _process_queue() -> void:
	if _active != &"" or _queue.is_empty():
		return
	var id: StringName = _queue.pop_front()
	_active = id
	load_progress.emit(id, 0.0)

	if await _ensure_pack(id):
		await _preload_assets(id)
		_loaded[id] = true
		load_progress.emit(id, 100.0)
		load_completed.emit(id)
	else:
		load_failed.emit(id, "Не удалось скачать/смонтировать pck контент-пака.")

	_active = &""
	# обработать следующий в очереди, если есть
	if not _queue.is_empty():
		await _process_queue()

# --- Пак: скачать (web) + смонтировать --------------------------------------

func _ensure_pack(id: StringName) -> bool:
	var pack: VNHubContentPack = _packs[id]
	var pack_file := pack.resolved_pack_name()
	if _mounted.get(pack_file, false):
		load_progress.emit(id, pack_weight)
		return true

	var path := _pack_local_path(pack_file)

	# На вебе качаем в user:// (IndexedDB кэширует между сессиями).
	if OS.has_feature("web") and not FileAccess.file_exists(path):
		if not await _download_pack(pack_file, path, id):
			return false
	# На десктопе pck лежит рядом с исполняемым файлом (path уже указывает туда).

	load_progress.emit(id, pack_weight)

	if not ProjectSettings.load_resource_pack(path):
		push_error("ResourceManager: load_resource_pack провалился: %s" % path)
		return false
	_mounted[pack_file] = true
	return true

func _download_pack(pack_file: String, path: String, id: StringName) -> bool:
	if base_url == "":
		push_error("ResourceManager: base_url не задан — скачивание пака %s невозможно." % pack_file)
		return false

	var http := HTTPRequest.new()
	add_child(http)

	# Через словарь, чтобы лямбда могла записать результат (передаётся по ссылке).
	var done := {"finished": false, "code": 0, "body": PackedByteArray()}
	http.request_completed.connect(
		func(_result, code, _headers, body):
			done.code = code
			done.body = body
			done.finished = true
	)

	if http.request(base_url + pack_file + ".pck") != OK:
		http.queue_free()
		push_error("ResourceManager: не удалось начать запрос пака %s" % pack_file)
		return false

	# Поллим прогресс скачивания, пока запрос не завершится.
	while not done.finished:
		var total := http.get_body_size()
		var got := http.get_downloaded_bytes()
		if total > 0:
			load_progress.emit(id, (float(got) / float(total)) * pack_weight)
		await get_tree().process_frame

	http.queue_free()

	if done.code != 200:
		push_error("ResourceManager: пак %s -> HTTP %d" % [pack_file, done.code])
		return false

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ResourceManager: не открыть для записи %s" % path)
		return false
	f.store_buffer(done.body)
	f.close()
	return true

# --- Предзагрузка ассетов пака (threaded, с прогрессом) ---------------------

func _preload_assets(id: StringName) -> void:
	var assets: Array = _packs[id].assets
	if assets.is_empty():
		load_progress.emit(id, 100.0)
		return

	for p in assets:
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p)
		else:
			push_warning("ResourceManager: ассет не найден (нет в паке?): %s" % p)

	var all_done := false
	while not all_done:
		all_done = true
		var progress_sum := 0.0
		for p in assets:
			if not ResourceLoader.exists(p):
				progress_sum += 1.0   # считаем «обработанным», чтобы не зависнуть
				continue
			var prog: Array = []
			match ResourceLoader.load_threaded_get_status(p, prog):
				ResourceLoader.THREAD_LOAD_LOADED:
					progress_sum += 1.0
				ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					all_done = false
					progress_sum += (prog[0] if prog.size() > 0 else 0.0)
				ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					progress_sum += 1.0
					push_warning("ResourceManager: ошибка загрузки %s" % p)

		var frac := progress_sum / float(assets.size())
		load_progress.emit(id, pack_weight + frac * (100.0 - pack_weight))

		if not all_done:
			await get_tree().process_frame

	# Забираем готовые ресурсы и держим ссылки, иначе предзагруженное выгрузится.
	for p in assets:
		if ResourceLoader.exists(p):
			_cache[p] = ResourceLoader.load_threaded_get(p)

# --- Хелперы -----------------------------------------------------------------

func _pack_local_path(pack_file: String) -> String:
	if OS.has_feature("web"):
		return "user://%s.pck" % pack_file
	return OS.get_executable_path().get_base_dir().path_join("%s.pck" % pack_file)

func _on_dialogic_signal(argument) -> void:
	var key := str(argument)
	if _signal_to_pack.has(key):
		load_pack(_signal_to_pack[key])
