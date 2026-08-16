extends Node

func _ready() -> void:
	var anytype := AnytypeClient.new()
	add_child(anytype)
	anytype.configure("YOUR_API_KEY")

	var spaces: Dictionary = await anytype.list_spaces()
	if spaces.ok:
		print(spaces.data)
