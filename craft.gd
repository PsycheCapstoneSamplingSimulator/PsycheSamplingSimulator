extends RigidBody3D

@export var lateralThrust: float = 1 # in m/s^2
@export var lateralUpwardThrust: float = 1.25 # in m/s^2
@export var angularThrust: float = 1 # in m/s^2

@export_range(0.0, 100.0) var fuel = 100.0
@export var fuelConsumption: float = 0.1 # fuel:dv ratio


signal fuelUpdate(fuel: float, dv: float)

var alignTarget: Vector3 = Vector3.ZERO

#Testing
var crashTimer: float = 0.0
@export var crashTimeout: float = 10.0
var controlsEnabled: bool = true
var previousVelocity: Vector3 = Vector3.ZERO
@export var velocityChangeThreshold: float = 7

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#Testing
	previousVelocity = linear_velocity
	#pass
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var lateralAccel = Vector3.ZERO
	
	#Testing
	var velocityChange = (previousVelocity - linear_velocity).length()
	
	if (velocityChange > velocityChangeThreshold) && (controlsEnabled == true):
		print("You crashed! The mission will close in 10 seconds.")
		controlsEnabled = false
		crashTimer = crashTimeout
	previousVelocity = linear_velocity
	
	var angularAccel = Vector3.ZERO
	
	if controlsEnabled:
		if Input.is_action_pressed("craft_lateral_up"):
			lateralAccel += transform.basis.y * (lateralUpwardThrust / 100.0)
		if Input.is_action_pressed("craft_lateral_down"):
			lateralAccel += -transform.basis.y * (lateralUpwardThrust / 100.0)
		if Input.is_action_pressed("craft_lateral_forward"):
			lateralAccel += -transform.basis.x * (lateralThrust / 100.0)
		if Input.is_action_pressed("craft_lateral_backward"):
			lateralAccel += transform.basis.x * (lateralThrust / 100.0)
		if Input.is_action_pressed("craft_lateral_left"):
			lateralAccel += transform.basis.z * (lateralThrust / 100.0)
		if Input.is_action_pressed("craft_lateral_right"):
			lateralAccel += -transform.basis.z * (lateralThrust / 100.0)
		if Input.is_action_pressed("craft_lateral_cancel"):
			lateralAccel += -linear_velocity * (lateralThrust / 100.0)
			
		if Input.is_action_pressed("craft_angular_roll_cw"):
			angularAccel += -transform.basis.y * (angularThrust / 100.0)
		if Input.is_action_pressed("craft_angular_roll_ccw"):
			angularAccel += transform.basis.y * (angularThrust / 100.0)
		if Input.is_action_pressed("craft_angular_forward"):
			angularAccel += transform.basis.z * (angularThrust / 100.0)
		if Input.is_action_pressed("craft_angular_backward"):
			angularAccel += -transform.basis.z * (angularThrust / 100.0)
		if Input.is_action_pressed("craft_angular_left"):
			angularAccel += transform.basis.x * (angularThrust / 100.0)
		if Input.is_action_pressed("craft_angular_right"):
			angularAccel += -transform.basis.x * (angularThrust / 100.0)
		if Input.is_action_pressed("craft_angular_cancel"):
			angularAccel += -angular_velocity * (angularThrust / 100.0)
			
	if crashTimer > 0:
		crashTimer -= delta
		if crashTimer <= 0:
			get_tree().quit()
			
	if alignTarget != Vector3.ZERO:
		if (alignTarget - rotation).length() < 0.1 and angular_velocity.length() < 0.1:
			alignTarget = Vector3.ZERO
		else:
			angularAccel += (alignTarget - rotation) * (angularThrust / 200.0)
			
	var consumption = fuelConsumption * (lateralAccel.length() + angularAccel.length())
	if(fuel - consumption < 0):
		var amt = fuel / consumption
		lateralAccel *= amt
		angularAccel *= amt
		fuel = 0
	else:
		fuel -= consumption
		
	fuelUpdate.emit(fuel, fuel / fuelConsumption)
	
	self.apply_force(mass * lateralAccel / delta)
	self.apply_torque(mass * angularAccel / delta)
	
	if popUpTime > 0:
		popUpTime -= delta
		$"../SamplePopup".visible = true
	else:
		$"../SamplePopup".visible = false
		
		
		
		
func _on_prograde_pressed() -> void:
	rotation = -linear_velocity.normalized()
	
func _on_retrograde_pressed() -> void:
	rotation = linear_velocity.normalized()
	
func _on_radial_out_pressed() -> void:
	rotation = Vector3.UP
	
func _on_stabilize_pressed() -> void:
	rotation = rotation
	
var popUpTime = 0.0

func _on_sample_button_pressed() -> void:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,                    # from
		global_position + Vector3.DOWN * 2,  # to (10 units down)
		1,                     # collision mask (optional)
		[self]                             # array of objects to exclude
	)
	var result = space_state.intersect_ray(query)
	
	print(result)
	
	if result and (linear_velocity + angular_velocity).length() < 0.05:
		popUpTime = 5
