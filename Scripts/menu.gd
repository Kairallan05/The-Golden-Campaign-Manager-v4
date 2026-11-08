extends Control

# Accepted files
const NOTE_EXTENSIONS: Array[String] = ["md", "txt"]

# How many folders deep you can go
const MAX_DEPTH: int = 10
# how many notes can be open at once
const MAX_EDITORS: int = 5

const NOTE_TAB: PackedScene = preload("res://Scene/note_tab.tscn")

@onready var open_universe_button: Button = $bars/HSplitContainer/Sidebar/OpenUniverseButton
@onready var file_tree: Tree = $bars/HSplitContainer/Sidebar/FileTree
@onready var file_dialog: FileDialog = $FileDialog
@onready var note_area: HSplitContainer = $bars/HSplitContainer/NoteArea
@onready var editor_limit: AcceptDialog = $Editor_Limit
@onready var writenoise: AudioStreamPlayer = $Writenoise

# The path of the universe (folder) chosen
var universe_path: String = ""
# the currently open note's path
var current_note: String = ""
# the focused note
var note: TextEdit
# Array of textedits in the note_tabs
var editors: Array[TextEdit] = []

func _ready() -> void:
	note = _create_editor() # open a note and focus it

func _create_editor() -> TextEdit:
	if editors.size() >= MAX_EDITORS:
		editor_limit.dialog_text = "Maximum number of notes open!"
		editor_limit.popup_centered()
		return null
	var tab: Control = NOTE_TAB.instantiate()
	var editor: TextEdit = tab.get_node("Editor") # find the TextEdit inside it
	
	# settings
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.editable = false # locked until a note is loaded into it
	editor.set_meta("title_label", tab.get_node("Upper_Tab/FileName")) # so _open_note can find the label
	
	editor.focus_entered.connect(_on_editor_focused.bind(editor))
	editor.gui_input.connect(_key_press.bind(editor))
	tab.get_node("Upper_Tab/Close_editor").pressed.connect(_close_editor.bind(tab, editor))
	
	note_area.add_child(tab) # put the whole tab in the scene
	editors.append(editor) # add to our list of editors
	return editor

func _key_press(event: InputEvent, editor: TextEdit) -> void:
	#only play when typing in active note.
	if not editor.editable:
		return
	
	if event is InputEventKey and event.pressed and event.unicode != 0 and not event.is_command_or_control_pressed():
		writenoise.pitch_scale = randf_range(0.9,1.1)
		writenoise.play()
func _close_editor(tab: Control, editor: TextEdit) -> void:
	editors.erase(editor) # delete from note array
	
	# unfocus the note if it was before
	if note == editor:
		note = null
		current_note = ""
	
	tab.queue_free()

func _on_editor_focused(editor: TextEdit) -> void:
	note = editor # make note the last selected editor
	current_note = editor.get_meta("path", "") # make path current note


# Opens the folder picker in the middle of the window
func _on_open_universe_button_pressed() -> void:
	file_dialog.popup_centered()

# Runs when the user selects a universe folder
func _on_file_dialog_dir_selected(dir: String) -> void:
	universe_path = dir
	current_note = ""
	
	# reset editors
	for editor in editors:
		editor.text = ""
		editor.clear_undo_history()
		editor.editable = false
		editor.get_meta("title_label").text = "No note open"
		if editor.has_meta("path"): # only remove a path if one was stored
			editor.remove_meta("path")
		
	_refresh_tree()

# open a note, or don't if its not a note
func _on_file_tree_item_selected() -> void:
	var item: TreeItem = file_tree.get_selected()
	if item == null:
		return # if nothing is selected, stop
	
	var data = item.get_metadata(0)
	
	# if nothing to read or is a folder then stop
	if data == null or data["is_folder"]:
		return 
	
	# open note
	_open_note(data["path"])

# loads a note
func _open_note(path: String) -> void:
	if note == null:
		return
	
	# Open's file and reads it if not null.
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file == null:
		print("Failed to open note: " + path)
		return
	
	note.text = file.get_as_text() # put read text into editor.
	note.clear_undo_history() # just so you can't Ctrl+Z the note away
	note.editable = true # can type
	note.set_meta("path", path) # link file to editor
	note.get_meta("title_label").text = path.get_file() # show the file's name
	current_note = path # to save note later

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("save"):
		_save_note()
		get_viewport().set_input_as_handled() # stop repeat actions

func _save_note() -> void:
	# if nothings open then stop
	if current_note == "":
		return
	
	# Open's file to write in it if not null.
	var file: FileAccess = FileAccess.open(current_note, FileAccess.WRITE)
	if file == null:
		print("failed to save note: " + current_note)
		return
	
	file.store_string(note.text) # write from editor to the file
	file.close() # finish writing
	print("saved: " + current_note)

# Wipes the tree and builds it again from scratch for the current universe
func _refresh_tree() -> void:
	file_tree.clear()  
	var root: TreeItem = file_tree.create_item()
	root.set_text(0, universe_path.get_file())   
	_populate_tree(root, universe_path, 0)   

# Scans a folder and adds its subfolders and notes to the tree under "parent"
# Calls itself to repeat on another folder
func _populate_tree(parent: TreeItem, dir_path: String, depth: int) -> void:
	if depth > MAX_DEPTH:
		return

	# Open the folder
	var dir: DirAccess = DirAccess.open(dir_path)

	# if error
	if dir == null:
		print("failed to load folder: " + dir_path)
		return

	# lists to put names into, to sort them before showing.
	var folders: Array[String] = []
	var files: Array[String] = []

	# Scan the folder
	dir.list_dir_begin()                  
	var entry: String = dir.get_next()    
	while entry != "":
		if dir.current_is_dir():
			folders.append(entry) # it's a folder
		elif entry.get_extension().to_lower() in NOTE_EXTENSIONS: # valid filetype?
			files.append(entry) # it's a valid file
		entry = dir.get_next()       
	dir.list_dir_end()

	# Alphabetical order.
	folders.sort()
	files.sort()

	# Add folders to the tree first, so they appear above the notes 
	for folder_name in folders:
		var folder_path: String = dir_path.path_join(folder_name)       
		var folder_item: TreeItem = file_tree.create_item(parent)       
		folder_item.set_text(0, folder_name)                            
		folder_item.set_metadata(0, {"path": folder_path, "is_folder": true})
		folder_item.collapsed = true                                    
		_populate_tree(folder_item, folder_path, depth + 1)             

	# Then add the notes 
	for file_name in files:
		var file_item: TreeItem = file_tree.create_item(parent)        
		file_item.set_text(0, file_name)                                
		file_item.set_metadata(0, {"path": dir_path.path_join(file_name), "is_folder": false})


func _on_volume_value_changed(value: float) -> void:
	writenoise.volume_db = value
