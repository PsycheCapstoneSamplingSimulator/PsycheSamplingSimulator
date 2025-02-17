extends CanvasLayer  # Assuming this script is attached to a CanvasLayer

func _ready():
	# Hide the menu and resume label initially
	$Control.visible = false
	$Control/ResumeButton.visible = false

func _process(delta):
	if Input.is_action_just_pressed("ui_cancel"):  # Check for Escape key press
		toggle_menu()

func toggle_menu():
	var menu = $Control
	menu.visible = not menu.visible  # Toggle the visibility of the Control node
	$Control/ResumeButton.visible = menu.visible  # Toggle the visibility of the ResumeLabel
	get_tree().paused = menu.visible  # Pause/unpause the game
	print("hello worl;ddddd")


func _on_resume_button_pressed() -> void:
	pass
	$Control.visible = false  # Hide the menu (including the ResumeButton)
	get_tree().paused = false  # Unpause the game
	print("Resume button pressed")
