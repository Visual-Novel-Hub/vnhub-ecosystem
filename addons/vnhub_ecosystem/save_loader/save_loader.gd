extends Node

@onready var _http_loader: HTTPRequest = $HTTPRequestLoader
@onready var _http_saver: HTTPRequest = $HTTPRequestSaver
@onready var _autosave_timer: Timer = $Timer

signal saves_loaded(ok: bool)

@export var game_name: String

var _save_queue: Array[Dictionary] = []
var _is_saving := false

func _ready() -> void:
	_http_loader.request_completed.connect(_on_load_request_completed)
	_http_saver.request_completed.connect(_on_save_request_completed)
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	Dialogic.Save.saved.connect(_on_saved)
	_fetch_saves_from_server()

func _process(_delta: float) -> void:
	# Отправляем следующий сейв, только когда свободны и игра в IDLE.
	# Поллинг каждый кадр заменяет рекурсию с await state_changed.
	if _is_saving or _save_queue.is_empty():
		return
	if Dialogic.current_state != Dialogic.States.IDLE:
		return
	_flush_queue()

func _on_autosave_timeout() -> void:
	print("_on_autosave_timeout tick")
	if Dialogic.current_state != Dialogic.States.IDLE:
		return
	_trigger_autosave.call_deferred()

func _trigger_autosave() -> void:
	print("_trigger_autosave tick")
	Dialogic.Save.save()  # вызовет saved → _on_saved → очередь

func enable_autosave() -> void:
	print("enable_autosave tick")
	_autosave_timer.start()

func disable_autosave() -> void:
	print("disable_autosave tick")
	_autosave_timer.stop()

# ── Очередь и отправка ────────────────────────────────────────────────────────

func _on_saved(e: Dictionary) -> void:
	print("_on_saved tick")
	_save_queue.push_back(e)

func _flush_queue() -> void:
	print("_flush_queue tick")
	_is_saving = true
	var e: Dictionary = _save_queue.pop_front()
	# Deferred: тяжёлый сбор состояния уходит в конец кадра, после рендера,
	# поэтому интерфейс не подвисает на сохранении.
	_collect_and_send.call_deferred(e)

func _collect_and_send(e: Dictionary) -> void:
	var slot_name: String = e.get("slot_name", "Default")
	var state: Dictionary = Dialogic.get_full_state()
	var safe_state = _sanitize_for_serialization(state)
	var payload = JSON.stringify({
		"game": game_name,
		"slot": slot_name,
		"state": var_to_str(safe_state)
	})
	var result = _http_saver.request(
		"https://vnhub.ru/api/save",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		payload
	)
	if result != OK:
		_is_saving = false  # запрос не ушёл — освобождаем для повторной попытки

func _on_save_request_completed(
	_result: int,
	_response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	_is_saving = false

# ── Загрузка с сервера ────────────────────────────────────────────────────────

func _fetch_saves_from_server() -> void:
	var url = "https://vnhub.ru/api/save?game=" + game_name
	_http_loader.request(url, ["Accept: application/json"], HTTPClient.METHOD_GET)

func _on_load_request_completed(
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if response_code != 200:
		push_warning("SaveLoader: сервер вернул код %d" % response_code)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_warning("SaveLoader: ошибка парсинга JSON")
		return

	var saves = json.get_data().get("saves", [])
	if typeof(saves) != TYPE_ARRAY:
		push_warning("SaveLoader: ожидался массив saves")
		return

	for item in saves:
		if item is Dictionary and item.has("slot") and item.has("state"):
			var state = str_to_var(item["state"])
			if state is Dictionary:
				_inject_save_to_dialogic(item["slot"], state)
			else:
				push_warning("SaveLoader: не удалось распарсить state для слота %s" % item["slot"])

	saves_loaded.emit(true)

func _inject_save_to_dialogic(slot_name: String, state_obj: Dictionary) -> void:
	var err = Dialogic.Save.save_file(slot_name, "state.txt", state_obj)
	if err != OK:
		push_warning("SaveLoader: ошибка инжекта сохранения в слот %s" % slot_name)

# ── Утилиты ───────────────────────────────────────────────────────────────────

func _sanitize_for_serialization(value) -> Variant:
	match typeof(value):
		TYPE_OBJECT:
			return null
		TYPE_DICTIONARY:
			var result := {}
			for key in value:
				result[key] = _sanitize_for_serialization(value[key])
			return result
		TYPE_ARRAY:
			var result := []
			for item in value:
				result.append(_sanitize_for_serialization(item))
			return result
		_:
			return value
