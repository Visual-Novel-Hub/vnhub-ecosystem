# VNHub Ecosystem

A Godot toolkit/ecosystem for building visual novels.

- **Engine:** Godot 4.6+
- **Type:** Editor plugin (`addons/vnhub_ecosystem`)

## Installation

Copy the `addons/vnhub_ecosystem` folder into your project's `addons/` directory,
then enable **VNHub Ecosystem** under **Project → Project Settings → Plugins**.

## Development

Open this folder as a project in Godot 4.6+. The plugin is enabled by default
via `project.godot`. Plugin entry point: `addons/vnhub_ecosystem/plugin.gd`.

## Layout

```
project.godot                          # Demo/dev project, enables the plugin
icon.svg                               # Project icon
addons/vnhub_ecosystem/
├── plugin.cfg                         # Plugin manifest
├── plugin.gd                          # EditorPlugin entry point (registers autoloads)
├── resource_manager/                  # ResourceManager component
│   ├── README.md                      # Component docs
│   ├── resource_manager.gd            # Content-pack manager (autoload: ResourceManager)
│   ├── resource_manager.tscn
│   ├── resource_manager_config.gd     # VNHubResourceManagerConfig (settings + pack list)
│   └── content_pack.gd                # VNHubContentPack (id, pack name, assets, signal)
└── save_loader/                       # SaveLoader component
    ├── README.md                      # Component docs
    ├── save_loader.gd                 # Dialogic save sync with the VNHub backend
    └── save_loader.tscn
```

## Components

- **ResourceManager** — universal content-pack manager (downloads/mounts `.pck`,
  threaded asset preloading, progress reporting, optional Dialogic auto-preload).
  Auto-registered as the `ResourceManager` autoload when the plugin is enabled.
  Packs are defined per-project via a `VNHubResourceManagerConfig` resource
  (path set in `Project Settings → vnhub_ecosystem/resource_manager/config`) or
  at runtime via `register_pack()`. Keyed by `StringName` — no enum/script edits.
  See [`addons/vnhub_ecosystem/resource_manager/README.md`](addons/vnhub_ecosystem/resource_manager/README.md).
- **SaveLoader** — server-side save sync for Dialogic 2.x against the VNHub
  backend (`vnhub.ru`): pulls saves into Dialogic slots on start, pushes each
  save back, with timer-based autosave. Add as an autoload yourself and set
  `game_name` (requires Dialogic).
  See [`addons/vnhub_ecosystem/save_loader/README.md`](addons/vnhub_ecosystem/save_loader/README.md).
