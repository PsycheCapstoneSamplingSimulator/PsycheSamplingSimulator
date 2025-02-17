extends HSlider

@onready var canvas_modulate: CanvasModulate = $CanvasModulate
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
	
#brightness slider
func _on_value_changed(value: float) -> void:
	pass # Replace with function body.
	
	GlobalWorldEnvironment.environment.adjustment_brightness = value - 10
	print(value)

#back button
func _on_back_button_pressed() -> void:
	pass # Replace with function body.
	get_tree().change_scene_to_file("res://node_2dMainMenu.tscn")
