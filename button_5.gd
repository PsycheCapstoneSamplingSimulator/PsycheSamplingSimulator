extends Button



func _on_pressed() -> void:
	pass # Replace with function body.
	print("Exiting game...")
	get_tree().quit()
	


func _on_button_pressed():
	get_tree().change_scene_to_file("res://node_3d.tscn")# Replace with function body.
	

func _on_button_4_pressed() -> void:
	pass # Replace with function body.
	get_tree().change_scene_to_file("res://node_2dSettingsMenu.tscn")
