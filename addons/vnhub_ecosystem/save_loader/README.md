# SaveLoader — README

Серверная синхронизация сохранений Dialogic для Godot-проекта (Godot 4.6+,
Dialogic 2.x). Подтягивает сейвы с бэкенда **VNHub** (`vnhub.ru`) при старте и
загоняет их в слоты Dialogic, а каждое локальное сохранение Dialogic
отправляет обратно на сервер. Есть автосейв по таймеру.

Часть аддона **VNHub Ecosystem**.
Файлы: `save_loader.gd`, `save_loader.tscn`.

> **Зависимость:** Dialogic 2.x (автозагрузка `Dialogic`). Скрипт жёстко
> обращается к `Dialogic.Save`, `Dialogic.current_state`, `Dialogic.get_full_state()`.
> Без Dialogic в проекте `_ready` упадёт с ошибкой.

---

## Что делает

- **При старте** запрашивает `GET https://vnhub.ru/api/save?game=<game_name>` и
  раскладывает полученные сейвы по слотам Dialogic (`Dialogic.Save.save_file`).
  По завершении эмитит сигнал `saves_loaded`.
- **При сохранении** ловит `Dialogic.Save.saved`, кладёт событие в очередь и,
  как только игра в состоянии `IDLE`, отправляет
  `POST https://vnhub.ru/api/save` с полным состоянием (`Dialogic.get_full_state()`).
- **Автосейв:** `Timer` (по умолчанию 10 с) дёргает `Dialogic.Save.save()` —
  дальше срабатывает та же цепочка очереди и отправки.

Состояние перед отправкой проходит `_sanitize_for_serialization` — все `Object`
вырезаются (→ `null`), затем сериализуется через `var_to_str` (на сервере
лежит строкой, обратно читается `str_to_var`).

---

## Структура сцены

`save_loader.tscn` — это узел `SaveLoader` (тип `Node`) с тремя детьми, которые
скрипт ждёт по именам:

```
SaveLoader (Node)               # script = save_loader.gd, @export game_name
├── HTTPRequestLoader (HTTPRequest)   # GET сейвов с сервера
├── HTTPRequestSaver  (HTTPRequest)   # POST сейвов на сервер
└── Timer                              # автосейв, wait_time = 10.0
```

Меняешь сцену — сохраняй имена детей, иначе `@onready`-ссылки будут `null`.

---

## Установка

1. Включи плагин **VNHub Ecosystem** (см. корневой README) и поставь Dialogic 2.x.
2. Добавь сцену как **Autoload**:
   `Project > Project Settings > Globals > Autoload` → выбери
   `res://addons/vnhub_ecosystem/save_loader/save_loader.tscn`, имя — `SaveLoader`.
   > Автоматически плагином он **не** регистрируется (в отличие от ResourceManager):
   > ему нужен заданный `game_name` и присутствие Dialogic, поэтому подключение
   > осознанно оставлено за тобой.
3. Задай **`game_name`** — это ключ игры на сервере. Либо в инспекторе на корневом
   узле сцены, либо из кода (см. ниже). Пустой `game_name` => загрузка уйдёт на
   `?game=` и вернёт пусто.
4. (Веб) убедись, что `vnhub.ru` доступен с твоего домена (CORS на стороне бэкенда).

---

## Использование

### Задать game_name из кода

Если используешь как автозагрузку и хочешь выставить имя на старте:

```gdscript
# где-то в bootstrap, до того как SaveLoader._ready() сделает первый запрос,
# проще всего — прямо в инспекторе сцены. Из кода — через инстанс:
var loader := preload("res://addons/vnhub_ecosystem/save_loader/save_loader.tscn").instantiate()
loader.game_name = "my-game"
add_child(loader)
```

### Реакция на загруженные сейвы

```gdscript
SaveLoader.saves_loaded.connect(func():
    # сейвы уже разложены по слотам Dialogic — можно строить меню «Продолжить»
    _refresh_load_menu()
)
```

### Автосейв

```gdscript
SaveLoader.enable_autosave()    # запустить Timer (тик каждые 10 с)
SaveLoader.disable_autosave()   # остановить
```

Автосейв срабатывает только когда `Dialogic.current_state == IDLE` — посреди
анимаций/выборов сохранение не дёргается.

### Ручное сохранение

Отдельного метода нет — сохраняй штатно через Dialogic, SaveLoader подхватит сам:

```gdscript
Dialogic.Save.save("MySlot")   # → saved → очередь → POST на сервер
```

---

## Контракт с сервером

**Загрузка** — `GET /api/save?game=<game_name>`, ответ:

```json
{
  "saves": [
    { "slot": "Autosave", "state": "<var_to_str-строка состояния>" },
    { "slot": "Slot1",    "state": "..." }
  ]
}
```

Каждый `state` парсится `str_to_var` и должен дать `Dictionary`.

**Сохранение** — `POST /api/save`, тело:

```json
{
  "game": "<game_name>",
  "slot": "<slot_name>",
  "state": "<var_to_str-строка состояния>"
}
```

---

## Публичный API

```gdscript
signal saves_loaded                 # сейвы с сервера разложены по слотам Dialogic

@export var game_name: String       # ключ игры на сервере

func enable_autosave() -> void      # запустить таймер автосейва
func disable_autosave() -> void     # остановить
```

---

## Поведение и ограничения

- **Одна отправка за раз.** `_is_saving` держит единственный POST в полёте;
  остальные ждут в очереди и уходят по одному, когда игра в `IDLE`.
- **Сбор состояния — deferred.** Тяжёлый `get_full_state()` уходит в конец кадра
  (после рендера), чтобы не фризить UI.
- **Object'ы не сериализуются.** `_sanitize_for_serialization` заменяет любые
  `Object` на `null`. Если в стейте есть ссылки на ноды/ресурсы — они потеряются.
- **Отладочные `print()`.** В коде остались служебные `print(... "tick")` — убери
  перед релизом или замени на свой логгер.
