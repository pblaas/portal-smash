class_name AppLog
extends Logger

const DEFAULT_PATH := "user://steamframe.log"
const MAX_BYTES := 512 * 1024
const TRIM_NOTICE := "-- earlier entries trimmed --"

static var _installed := false
static var _path := DEFAULT_PATH

var _file: FileAccess
var _written := 0
var _capped := false


static func install() -> bool:
	if _installed:
		return true
	_installed = true
	var logger := AppLog.new()
	if not logger._open():
		push_warning("AppLog: cannot open %s" % _path)
		return false
	OS.add_logger(logger)
	logger._write("=== %s · pid %d ===" % [Time.get_datetime_string_from_system(), OS.get_process_id()])
	return true


static func log_path() -> String:
	return _path


static func global_path() -> String:
	return ProjectSettings.globalize_path(_path)


static func override_path(path: String) -> void:
	_path = path


static func reset_for_tests() -> void:
	_installed = false


func _log_message(message: String, error: bool) -> void:
	if error:
		_write("ERROR  %s" % message)
	else:
		_write(message)


func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		editor_notify: bool,
		error_type: int,
		script_backtraces: Array
) -> void:
	var head := "ERROR  %s  at %s:%d  [%s]" % [function, file, line, code]
	if not rationale.is_empty():
		head += "  %s" % rationale
	_write(head)
	for trace in script_backtraces:
		for frame in trace.get_frame_count():
			_write(
				"    -> %s:%d  (%s)"
				% [trace.get_frame_file(frame), trace.get_frame_line(frame), trace.get_frame_function(frame)]
			)


func _open() -> bool:
	if not FileAccess.file_exists(_path):
		var create := FileAccess.open(_path, FileAccess.WRITE_READ)
		if create == null:
			return false
		create.close()
	_file = FileAccess.open(_path, FileAccess.READ_WRITE)
	if _file == null:
		return false
	_file.seek_end()
	if _file.get_length() > MAX_BYTES:
		_trim()
	_file.seek_end()
	_written = _file.get_position()
	_capped = _written > MAX_BYTES
	return true


func _write(line: String) -> void:
	if _file == null or _capped:
		return
	var stamped := "%s  %s" % [Time.get_datetime_string_from_system(), line]
	_file.store_line(stamped)
	_file.flush()
	_written += stamped.length() + 1
	if _written > MAX_BYTES:
		_capped = true
		_file.store_line(
			"%s  -- log cap of %d bytes reached, further output dropped --"
			% [Time.get_datetime_string_from_system(), MAX_BYTES]
		)
		_file.flush()


func _trim() -> void:
	var length := _file.get_length()
	if length <= MAX_BYTES:
		return
	_file.seek(length - MAX_BYTES)
	var tail := _file.get_as_text()
	_file.close()
	var cut := tail.find("\n")
	if cut >= 0:
		tail = tail.substr(cut + 1)
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		return
	_file.store_line(TRIM_NOTICE)
	_file.store_string(tail)
	_file.seek_end()
