extends Control


func resume():
	get_tree().paused = false
	$AnimationPlayer.play_backwards("blur")
	
func pause():
	get_tree().paused = true
	$AnimationPlayer.play("blur")
	
func testEsc():
	if Input.is_action_just_pressed("esca") and get_tree().paused == false:
		pause()
	elif Input.is_action_just_pressed("esca") and get_tree().paused == true:
		resume()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
	$AnimationPlayer.play("RESET")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	testEsc()

func _on_resume_pressed() -> void:
	pass # Replace with function body.
	resume()

func _on_restart_pressed() -> void:
	pass # Replace with function body.
	resume()
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	pass # Replace with function body.
	get_tree().paused = false	#unpause game
	get_tree().change_scene_to_file("res://node_2dMainMenu.tscn")
	
