@tool
extends EditorPlugin

## Entry point for the VNHub Ecosystem editor plugin.
## Registers autoloads, custom types, docks, and inspector plugins here.

const RESOURCE_MANAGER_AUTOLOAD := "ResourceManager"
const RESOURCE_MANAGER_SCENE := "res://addons/vnhub_ecosystem/resource_manager/resource_manager.tscn"

## Project Setting holding the path to a VNHubResourceManagerConfig (.tres).
## Set this to your project's pack config; ResourceManager loads it on startup.
const CONFIG_SETTING := "vnhub_ecosystem/resource_manager/config"


func _enter_tree() -> void:
	# Called when the plugin is enabled in the editor.
	_register_config_setting()
	add_autoload_singleton(RESOURCE_MANAGER_AUTOLOAD, RESOURCE_MANAGER_SCENE)


func _exit_tree() -> void:
	# Called when the plugin is disabled. Clean up anything registered above.
	remove_autoload_singleton(RESOURCE_MANAGER_AUTOLOAD)


func _register_config_setting() -> void:
	if not ProjectSettings.has_setting(CONFIG_SETTING):
		ProjectSettings.set_setting(CONFIG_SETTING, "")
	ProjectSettings.set_initial_value(CONFIG_SETTING, "")
	ProjectSettings.add_property_info({
		"name": CONFIG_SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tres,*.res",
	})
	ProjectSettings.set_as_basic(CONFIG_SETTING, true)
