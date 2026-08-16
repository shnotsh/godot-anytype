<p align="center">
  <img src="repo_img.png" width="660" >
</p>

# Anytype Sync for Godot

An editor addon and runtime GDScript client for Anytype's local HTTP API with no third-party dependencies.


## Install

1. Enable **Anytype Sync** in `Project > Project Settings > Plugins`.
2. In Anytype, open `Settings > API Keys`, create a key, and copy it.
3. Add an `AnytypeClient` node to a scene, or instantiate it from code.

```gdscript
var anytype := AnytypeClient.new()
add_child(anytype)
anytype.configure("YOUR_API_KEY")

var spaces: Dictionary = await anytype.list_spaces()
if spaces.ok:
    print(spaces.data)
```

The default endpoint is `http://127.0.0.1:31009`. For a different Anytype instance:

```gdscript
anytype.configure(api_key, "http://localhost:31009")
```

## Common operations

```gdscript
var created := await anytype.create_object(space_id, {
    "name": "From Godot",
    "icon": {"emoji": "🎮", "format": "emoji"},
    "body": "Created by a Godot game.",
    "type_key": "page",
})

var results := await anytype.search("Godot", ["page"])
var all_objects := await anytype.sync_space(space_id)
```

Every method returns a dictionary shaped like:

```gdscript
{"ok": true, "status_code": 200, "data": ...}
```

Failures include `error`; the original API error is retained in `data` when Anytype returns JSON. `archive_object()` uses Anytype's delete endpoint, which archives the object rather than immediately destroying it.

## API coverage

The client includes challenge authentication, spaces, objects, global search, types, properties, pagination, and a complete space pull helper. Use `request_async()` for endpoints not wrapped yet. The API version is configurable and defaults to `2025-11-08`.

API reference: https://developers.anytype.io/docs/reference/2025-11-08/anytype-api/
