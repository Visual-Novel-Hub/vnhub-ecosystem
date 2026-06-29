@tool
class_name VNHubResourceManagerConfig
extends Resource
## Конфиг ResourceManager: список контент-паков + общие параметры загрузки.
## Сохрани как .tres в своём проекте и укажи путь в
## Project Settings > vnhub_ecosystem/resource_manager/config.
## Аддон сам подхватит его при старте.

## База для скачивания паков на вебе. Если задана — должна заканчиваться на "/".
## Итоговый URL = base_url + <pack_name> + ".pck".
## Пусто или относительный путь => пак качается относительно текущей страницы.
## На десктопе паки не качаются — ищутся локально относительно текущей директории.
@export var base_url: String = ""

## Доля прогресса (0..100) под скачивание+монтирование пака.
## Остаток уходит на предзагрузку ассетов.
@export_range(0.0, 100.0) var pack_weight: float = 40.0

## Контент-паки проекта.
@export var packs: Array[VNHubContentPack] = []
