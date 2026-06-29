@tool
class_name VNHubContentPack
extends Resource
## Описание одного контент-пака для ResourceManager.
## Создаётся в инспекторе (как .tres внутри VNHubResourceManagerConfig)
## или собирается в коде и передаётся в ResourceManager.register_pack().

## Уникальный ключ пака. Им оперирует весь API: load_pack(&"chapter_6").
@export var id: StringName = &""

## Имя файла пака без расширения (<pack_name>.pck). Пусто => берётся id.
@export var pack_name: String = ""

## res://-пути ассетов, которые греются в фоне после монтирования пака.
@export var assets: Array[String] = []

## (опц.) Аргумент Dialogic-сигнала, по которому пак грузится наперёд.
## Пусто => используется id (т.е. [signal arg="<id>"]).
@export var preload_signal: StringName = &""


## Имя .pck-файла с фолбэком на id.
func resolved_pack_name() -> String:
	return pack_name if pack_name != "" else String(id)


## Аргумент сигнала авто-предзагрузки с фолбэком на id.
func resolved_signal() -> String:
	return String(preload_signal) if preload_signal != &"" else String(id)
