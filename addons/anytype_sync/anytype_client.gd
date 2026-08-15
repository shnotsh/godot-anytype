@icon("res://addons/anytype_sync/anytype_node.svg")
class_name AnytypeClient
extends Node

## Small, dependency-free Anytype API client for Godot 4.
##
## Anytype's local API uses bearer API keys. Create one in Anytype's
## Settings > API Keys, then call configure() before making requests.

const DEFAULT_BASE_URL := "http://127.0.0.1:31009"
const API_VERSION := "2025-11-08"
const DEFAULT_TIMEOUT := 30.0

signal request_started(method: String, path: String)
signal request_finished(method: String, path: String, status_code: int, data: Variant)
signal sync_finished(result: Dictionary)

var base_url := DEFAULT_BASE_URL
var api_key := ""
var api_version := API_VERSION
var timeout_seconds := DEFAULT_TIMEOUT

func configure(new_api_key: String, new_base_url: String = DEFAULT_BASE_URL, new_api_version: String = API_VERSION) -> void:
	api_key = new_api_key.strip_edges()
	base_url = new_base_url.strip_edges().trim_suffix("/")
	api_version = new_api_version.strip_edges()

func is_configured() -> bool:
	return not api_key.is_empty()

func request_async(method: String, path: String, body: Variant = null, query: Dictionary = {}) -> Dictionary:
	var normalized_path := path
	if not normalized_path.begins_with("/"):
		normalized_path = "/" + normalized_path
	var url := base_url + normalized_path + _query_string(query)
	var headers := PackedStringArray([
		"Accept: application/json",
		"Anytype-Version: " + api_version,
	])
	if not api_key.is_empty():
		headers.append("Authorization: Bearer " + api_key)
	if body != null:
		headers.append("Content-Type: application/json")

	var http := HTTPRequest.new()
	http.timeout = timeout_seconds
	add_child(http)
	request_started.emit(method, normalized_path)
	var request_error := http.request(url, headers, _method_to_enum(method), _json_encode(body))
	if request_error != OK:
		http.queue_free()
		return _failure(request_error, "Could not start HTTP request: " + error_string(request_error))

	var completed: Array = await http.request_completed
	var result := _parse_response(completed)
	http.queue_free()
	request_finished.emit(method, normalized_path, result.status_code, result.data)
	return result

func create_challenge(app_name: String) -> Dictionary:
	return await request_async("POST", "/v1/auth/challenges", {"app_name": app_name})

func exchange_challenge(challenge_id: String, code: String) -> Dictionary:
	var result: Dictionary = await request_async("POST", "/v1/auth/api_keys", {
		"challenge_id": challenge_id,
		"code": code,
	})
	if result.ok and result.data is Dictionary and result.data.has("api_key"):
		api_key = str(result.data.api_key)
	return result

func list_spaces(offset: int = 0, limit: int = 100, filters: Dictionary = {}) -> Dictionary:
	return await request_async("GET", "/v1/spaces", null, _pagination(offset, limit, filters))

func get_space(space_id: String) -> Dictionary:
	return await request_async("GET", "/v1/spaces/" + _segment(space_id))

func list_objects(space_id: String, offset: int = 0, limit: int = 100, filters: Dictionary = {}) -> Dictionary:
	return await request_async("GET", "/v1/spaces/%s/objects" % _segment(space_id), null, _pagination(offset, limit, filters))

func get_object(space_id: String, object_id: String) -> Dictionary:
	return await request_async("GET", "/v1/spaces/%s/objects/%s" % [_segment(space_id), _segment(object_id)])

func create_object(space_id: String, object_data: Dictionary) -> Dictionary:
	return await request_async("POST", "/v1/spaces/%s/objects" % _segment(space_id), object_data)

func update_object(space_id: String, object_id: String, object_data: Dictionary) -> Dictionary:
	return await request_async("PATCH", "/v1/spaces/%s/objects/%s" % [_segment(space_id), _segment(object_id)], object_data)

func archive_object(space_id: String, object_id: String) -> Dictionary:
	return await request_async("DELETE", "/v1/spaces/%s/objects/%s" % [_segment(space_id), _segment(object_id)])

func search(query_text: String, types: Array[String] = [], offset: int = 0, limit: int = 100) -> Dictionary:
	var payload: Dictionary = {"query": query_text}
	if not types.is_empty():
		payload["types"] = types
	return await request_async("POST", "/v1/search", payload, {"offset": offset, "limit": limit})

func list_types(space_id: String, offset: int = 0, limit: int = 100, filters: Dictionary = {}) -> Dictionary:
	return await request_async("GET", "/v1/spaces/%s/types" % _segment(space_id), null, _pagination(offset, limit, filters))

func list_properties(space_id: String, offset: int = 0, limit: int = 100, filters: Dictionary = {}) -> Dictionary:
	return await request_async("GET", "/v1/spaces/%s/properties" % _segment(space_id), null, _pagination(offset, limit, filters))

## Pulls every active object page-by-page. It emits sync_finished when complete.
## The result contains {ok, objects, pages, errors}.
func sync_space(space_id: String, page_size: int = 100) -> Dictionary:
	var objects: Array = []
	var errors: Array = []
	var offset := 0
	var pages := 0
	while true:
		var response: Dictionary = await list_objects(space_id, offset, page_size)
		pages += 1
		if not response.ok:
			errors.append(response)
			break
		var page: Array = _extract_items(response.data)
		objects.append_array(page)
		if page.size() < page_size:
			break
		offset += page.size()
	var result := {"ok": errors.is_empty(), "objects": objects, "pages": pages, "errors": errors}
	sync_finished.emit(result)
	return result

func _pagination(offset: int, limit: int, extra: Dictionary) -> Dictionary:
	var result := {"offset": maxi(offset, 0), "limit": clampi(limit, 1, 100)}
	for key in extra:
		result[key] = extra[key]
	return result

func _query_string(query: Dictionary) -> String:
	if query.is_empty():
		return ""
	var parts: PackedStringArray = []
	for key in query:
		var value = query[key]
		if value is Array:
			var array_values: PackedStringArray = []
			for item in value:
				array_values.append(str(item))
			value = ",".join(array_values)
		parts.append(str(key).uri_encode() + "=" + str(value).uri_encode())
	return "?" + "&".join(parts)

func _segment(value: String) -> String:
	return value.uri_encode()

func _method_to_enum(method: String) -> HTTPClient.Method:
	match method.to_upper():
		"GET": return HTTPClient.METHOD_GET
		"POST": return HTTPClient.METHOD_POST
		"PUT": return HTTPClient.METHOD_PUT
		"PATCH": return HTTPClient.METHOD_PATCH
		"DELETE": return HTTPClient.METHOD_DELETE
		_: return HTTPClient.METHOD_GET

func _json_encode(value: Variant) -> String:
	if value == null:
		return ""
	return JSON.stringify(value)

func _parse_response(completed: Array) -> Dictionary:
	var result := {"ok": false, "status_code": -1, "data": null, "error": ""}
	if completed.size() < 4:
		result.error = "Malformed HTTP response"
		return result
	var transport_result: int = completed[0]
	var status_code: int = completed[1]
	var raw_body: PackedByteArray = completed[3]
	result.status_code = status_code
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		result.error = "Network error: " + str(transport_result)
		return result
	var text_body := raw_body.get_string_from_utf8()
	var parsed = JSON.parse_string(text_body)
	result.data = parsed if parsed != null else text_body
	result.ok = status_code >= 200 and status_code < 300
	if not result.ok:
		result.error = _error_message(result.data, "Anytype returned HTTP %d" % status_code)
	return result

func _failure(code: int, message: String) -> Dictionary:
	return {"ok": false, "status_code": -1, "data": null, "error": message, "code": code}

func _error_message(data: Variant, fallback: String) -> String:
	if data is Dictionary and data.has("message"):
		return str(data.message)
	return fallback

func _extract_items(data: Variant) -> Array:
	if data is Array:
		return data
	if data is Dictionary:
		for key in ["objects", "spaces", "items", "types", "properties"]:
			if data.get(key) is Array:
				return data[key]
	return []
