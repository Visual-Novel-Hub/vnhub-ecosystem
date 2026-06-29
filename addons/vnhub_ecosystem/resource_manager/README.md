# ResourceManager — README

Универсальный менеджер контент-паков для Godot-проекта (Godot 4.6+, веб и десктоп).
Скачивает и монтирует `.pck` контент-пака, предзагружает его ассеты в фоне, отдаёт
процент загрузки и (опционально) сам реагирует на Dialogic-сигналы для предзагрузки
наперёд.

Часть аддона **VNHub Ecosystem**. Карта паков задаётся **в проекте**, а не в коде
аддона — через ресурс-конфиг (`.tres`) или регистрацию в рантайме.

Файлы:
- `resource_manager.gd` / `resource_manager.tscn` — сам менеджер (Autoload).
- `resource_manager_config.gd` — `VNHubResourceManagerConfig` (общие настройки + список паков).
- `content_pack.gd` — `VNHubContentPack` (один пак: id, имя файла, ассеты, сигнал).

> Терминология: «пак» (`VNHubContentPack`) — единица контента: `.pck` + список
> ассетов под ним. Идентифицируется ключом `StringName` (`&"chapter_6"`,
> `&"level_2"`, `&"dlc_winter"` — что угодно). Никаких enum'ов и правок скрипта.

---

## Что делает

- Хранит карту `id => VNHubContentPack`, заполняемую проектом (конфиг или `register_*`).
- По запросу достаёт пак и монтирует его: на вебе качает в `user://` (с кэшем в IndexedDB) с `base_url` или, если он пуст/относителен, относительно текущей страницы; на десктопе берёт локальный `.pck` относительно текущей рабочей директории (без скачивания). Затем предзагружает тяжёлые ассеты через `ResourceLoader.load_threaded_request` (не морозит UI, если включены потоки).
- Сообщает прогресс одним сигналом `load_progress` (0..100).
- Ловит Dialogic Signal-события и стартует фоновую загрузку нужного пака заранее.

---

## Установка

1. Скопируй папку `addons/vnhub_ecosystem` в свой проект и включи плагин
   **VNHub Ecosystem** в `Project > Project Settings > Plugins`.
2. Плагин сам регистрирует Autoload `ResourceManager` — глобальный доступ
   `ResourceManager.load_pack(...)` появляется сразу. (В скрипте намеренно нет
   `class_name`, чтобы имя не конфликтовало с автозагрузкой.)
3. Опиши свои паки — **способ A (конфиг)** или **способ B (рантайм)** ниже.
4. Для веб-сборки поставь заголовки COOP/COEP (для SharedArrayBuffer + потоков) —
   без них предзагрузка станет однопоточной и будет фризить.

---

## Описание паков

### Способ A — ресурс-конфиг (.tres), редактируется в инспекторе

1. Создай ресурс `VNHubResourceManagerConfig` (`Create Resource > VNHubResourceManagerConfig`),
   сохрани в проекте, например `res://content_packs.tres`.
2. Заполни в инспекторе:
   - `base_url` — база скачивания на вебе (заканчивается на `/`); пусто/относительный путь => качается относительно текущей страницы; на десктопе не используется;
   - `pack_weight` — доля прогресса под скачивание+монтирование (по умолчанию `40`);
   - `packs` — массив `VNHubContentPack`, у каждого:
     - `id` — `StringName`-ключ (например `&"chapter_6"`);
     - `pack_name` — имя `.pck` без расширения (пусто => равно `id`);
     - `assets` — `res://`-пути для предзагрузки;
     - `preload_signal` — (опц.) аргумент Dialogic-сигнала (пусто => равно `id`).
3. Укажи путь к конфигу в
   `Project Settings > vnhub_ecosystem/resource_manager/config` (поле появляется,
   когда плагин включён). Менеджер подхватит его на старте автоматически.

### Способ B — регистрация в рантайме

Из своего bootstrap-скрипта (например, собственного автозагрузчика), до первой загрузки:

```gdscript
func _ready() -> void:
    ResourceManager.base_url = "https://cdn.example.com/packs/"

    # вариант 1: готовый ресурс
    var pack := VNHubContentPack.new()
    pack.id = &"level_2"
    pack.assets = ["res://environments/cave.tres", "res://music/level2.ogg"]
    ResourceManager.register_pack(pack)

    # вариант 2: короткий хелпер
    ResourceManager.register_pack_data(
        &"level_3", "level_3",
        ["res://environments/bridge.tres"])

    # вариант 3: применить целый конфиг (например, скачанный с сервера)
    ResourceManager.register_config(my_config)
```

Способы можно смешивать: подгрузить конфиг из файла и дорегистрировать паки кодом.

### Связь с паками

`pack_name` (или `id`, если `pack_name` пуст) должно совпадать с реально собранным паком:

```bash
godot --headless --export-pack "Web" builds/web/level_2.pck
```

На вебе этот `level_2.pck` должен быть доступен по `base_url + "level_2.pck"`
(или, если `base_url` пуст/относителен, относительно текущей страницы).
На десктопе `level_2.pck` должен лежать в текущей рабочей директории игры —
менеджер его не качает, а монтирует локально.
Держи паки 10–20 МБ — запись большого буфера в `user://` спайкает WASM-кучу.

---

## Публичный API

### Регистрация

```gdscript
func register_config(config: VNHubResourceManagerConfig) -> void   # параметры + все паки
func register_pack(pack: VNHubContentPack) -> void                 # один пак-ресурс
func register_pack_data(id: StringName, pack_name := "", assets: Array[String] = [], preload_signal := &"") -> void
func get_pack_ids() -> Array                                       # зарегистрированные id
```

### Загрузка

```gdscript
## Загрузить пак. Прогресс — load_progress, итог — load_completed/load_failed.
## Можно await-ить. Параллельные вызовы ставятся в очередь.
func load_pack(id: StringName) -> void

## Готов ли пак (pck смонтирован + ассеты предзагружены).
func is_pack_loaded(id: StringName) -> bool

## Идёт ли сейчас загрузка какого-либо пака.
func is_busy() -> bool

## Снять ссылки на ассеты пака → освободить VRAM/RAM.
## На вебе сам pck не выгружается (нет unload_resource_pack), уходят только ресурсы.
func unload_pack(id: StringName) -> void
```

### Сигналы

```gdscript
signal load_progress(id: StringName, percent: float)   # percent: 0.0..100.0
signal load_completed(id: StringName)
signal load_failed(id: StringName, reason: String)
```

### Как считается процент

- `0 .. pack_weight` — получение пака (на вебе реальный прогресс по байтам при скачивании; на десктопе и при кэш-попадании — сразу `pack_weight`).
- `pack_weight .. 100` — предзагрузка ассетов, с под-прогрессом каждого ресурса.
- `100` + `load_completed` — пак готов.

---

## Интеграция с Dialogic (опционально)

Менеджер сам подключается к `Dialogic.signal_event` в `_ready`, если автозагрузка
`Dialogic` есть в проекте. Нет Dialogic — менеджер пишет одно предупреждение и
работает через прямые вызовы `load_pack(...)`.

Аргумент сигнала сопоставляется с `preload_signal` пака (по умолчанию — его `id`).
В timeline ставишь **Signal-событие** за несколько реплик до перехода:

```
[signal arg="chapter_6"]
```

Менеджер в фоне начнёт качать и греть пак `&"chapter_6"`. К моменту реального
перехода он уже готов — без лага.

> Под Dialogic 2.x проверь: сигнал называется `signal_event`, а его аргумент
> приходит строкой. Если иначе — поправь `str(argument)` в `_on_dialogic_signal`.

---

## Рецепты

### Прогресс-бар + переход после загрузки

```gdscript
func go_to_level_2() -> void:
    $LoadScreen.show()
    ResourceManager.load_progress.connect(_on_progress)
    await ResourceManager.load_pack(&"level_2")
    ResourceManager.load_progress.disconnect(_on_progress)
    $LoadScreen.hide()
    get_tree().change_scene_to_file("res://levels/level_2.tscn")

func _on_progress(_id: StringName, percent: float) -> void:
    $LoadScreen/Bar.value = percent
```

### Тихая предзагрузка наперёд (без экрана)

Поставь `[signal arg="level_2"]` заранее (через Dialogic) — менеджер всё сделает в
фоне. Перед реальным переходом можно подстраховаться:

```gdscript
if not ResourceManager.is_pack_loaded(&"level_2"):
    await ResourceManager.load_pack(&"level_2")
```

### Освобождение памяти

```gdscript
ResourceManager.unload_pack(&"level_1")
```

---

## Поведение и ограничения

- **Кэш паков.** На вебе пак пишется в `user://` (IndexedDB) и кэшируется между сессиями — повторно не качается.
- **Десктоп — только локально.** На десктопе менеджер ничего не качает: `.pck` должен лежать в текущей рабочей директории игры (относительный путь). Если файла нет — `load_failed`.
- **Пак не выгрузить.** В стабильной ветке нет `unload_resource_pack`. `unload_pack` освобождает только ресурсы (VRAM/RAM), но не байты пака.
- **Ссылки держатся.** Предзагруженные ассеты хранятся в `_cache`, иначе выгрузились бы сразу. Это и есть смысл «пак загружен». Освобождай через `unload_pack`.
- **Одна загрузка за раз.** Параллельные вызовы `load_pack` ставятся в очередь.
- **Потоки на вебе.** Без COOP/COEP + SharedArrayBuffer предзагрузка станет синхронной и будет фризить UI. На десктопе потоки доступны всегда.

---

## Чеклист подключения

- [ ] Папка `addons/vnhub_ecosystem` в проекте, плагин **VNHub Ecosystem** включён
- [ ] Autoload `ResourceManager` появился автоматически (Project Settings > Globals)
- [ ] Паки описаны: либо `.tres` указан в `vnhub_ecosystem/resource_manager/config`, либо `register_*` в bootstrap
- [ ] (Веб) задан `base_url` (в конфиге или `ResourceManager.base_url`), либо паки лежат рядом со страницей (относительный путь)
- [ ] Паки собраны (`--export-pack`); на вебе доступны по `base_url`/относительно страницы, на десктопе лежат в текущей рабочей директории
- [ ] (Dialogic) в timeline стоят `[signal arg="<id>"]` за несколько реплик до переходов
- [ ] (Веб) COOP/COEP-заголовки на хостинге стоят
