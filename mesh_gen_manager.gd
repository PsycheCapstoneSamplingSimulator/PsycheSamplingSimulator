extends Node3D

const MESH_SIZE = 64  # Size of each mesh_gen
const MESH_SEGMENTS = 64  # Number of segments in each direction
const VIEW_DISTANCE = 32  # How many meshes to load in each direction

var mesh_scene = preload("res://scene/prefab/mesh_gen.tscn")

@export var noise_amplitude: float
@export var noise_scale: float
# the real amount is 6250
@export var psyche_radius = MESH_SIZE * 100

var current_meshes = {}
var player: Node3D

var max_queued_generations = 250
var max_instantiations_per_frame = 4

var generation_queue = []
var finished_meshes = {}

var generation_mutex: Mutex
var finished_mutex: Mutex
var exit_mutex: Mutex

var generation_thread: Thread
var exit_thread: bool = false

@onready var base_noise: FastNoiseLite = FastNoiseLite.new()
@onready var detail_noise: FastNoiseLite = FastNoiseLite.new()
@onready var warping_noise: FastNoiseLite = FastNoiseLite.new()
@onready var crater_noise: FastNoiseLite = FastNoiseLite.new()
@onready var crag_noise: FastNoiseLite = FastNoiseLite.new()

func setup_noise() -> void:
	var size_setting = Globals.asteroid_scale
	if size_setting == 0:
		self.psyche_radius = MESH_SIZE * 20
	elif size_setting == 1:
		self.psyche_radius = MESH_SIZE * 100
	else:
		self.psyche_radius = MESH_SIZE * 62500
	
	# Base terrain noise
	base_noise.seed = 6408
	base_noise.frequency = 0.0005
	base_noise.fractal_octaves = 5
	base_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	base_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# Detail noise for smaller features
	detail_noise.seed = 6409
	detail_noise.frequency = 0.002
	detail_noise.fractal_octaves = 3
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# Warping noise for terrain variation
	warping_noise.seed = 6410
	warping_noise.frequency = 0.0003
	warping_noise.fractal_octaves = 2
	warping_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# Crater noise for impact features
	crater_noise.seed = 6411
	crater_noise.frequency = 0.0001  # Large sparse craters
	crater_noise.fractal_octaves = 1
	crater_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	crater_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	crater_noise.cellular_jitter = 1.0
	
	# Crag noise for sharp rocky features
	crag_noise.seed = 6412
	crag_noise.frequency = 0.0008
	crag_noise.fractal_octaves = 2
	crag_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	crag_noise.noise_type = FastNoiseLite.TYPE_PERLIN

func get_height(world_x: float, world_z: float) -> float:
	# Apply domain warping for more natural-looking terrain
	var warp_x = warping_noise.get_noise_2d(world_x * 0.5, world_z * 0.5) * 100.0
	var warp_z = warping_noise.get_noise_2d(world_x * 0.5 + 1000.0, world_z * 0.5) * 100.0
	
	# Get base terrain
	var base = base_noise.get_noise_2d(world_x + warp_x, world_z + warp_z) * noise_amplitude
	var detail = detail_noise.get_noise_2d(world_x, world_z) * (noise_amplitude * 0.3)
	
	# Generate crater features
	var crater = crater_noise.get_noise_2d(world_x, world_z)
	crater = 1.0 - abs(crater)  # Invert and make positive
	crater = pow(crater, 3.0)   # Sharpen crater edges
	crater *= noise_amplitude * 0.8  # Scale crater depth
	
	# Generate sharp crag features
	var crag = crag_noise.get_noise_2d(world_x, world_z)
	crag = pow(max(crag, 0.0), 2.0)  # Sharpen positive values
	crag *= noise_amplitude * 0.5
	
	# Combine all features
	var combined = base
	combined += detail * (abs(base) * 0.3 + 0.7)  # Detail varies with elevation
	combined -= crater  # Subtract craters
	combined += crag    # Add sharp features
	
	return combined

# Helper function for smooth interpolation
func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func generate_mesh(chunk_position: Vector2i) -> Array:
	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	
	base_noise.seed = 6408
	detail_noise.seed = 6409
	warping_noise.seed = 6410
	crater_noise.seed = 6411
	crag_noise.seed = 6412
	
	var verts = PackedVector3Array()
	var uvs = PackedVector2Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()

	# Create vertices
	for i in range(MESH_SEGMENTS + 1):
		for j in range(MESH_SEGMENTS + 1):
			# Calculate exact positions at chunk boundaries
			var x = (float(j) * MESH_SIZE / MESH_SEGMENTS) - (MESH_SIZE / 2.0)
			var z = (float(i) * MESH_SIZE / MESH_SEGMENTS) - (MESH_SIZE / 2.0)
			
			var world_x = x + (chunk_position.x * MESH_SIZE)
			var world_z = z + (chunk_position.y * MESH_SIZE)
			
			var height = get_height(world_x, world_z)

			var flat_distance = sqrt(world_x * world_x + world_z * world_z) + 0.0001 # avoid division by zero
			var theta = flat_distance / psyche_radius
			var phi = atan2(world_z, world_x)

			var point_on_sphere = Vector3(
				cos(phi) * sin(theta),
				cos(theta),
				sin(phi) * sin(theta)
			) * psyche_radius
			
			var normal = point_on_sphere.normalized()
			
			var vert = point_on_sphere + (normal * height) - Vector3(chunk_position.x * MESH_SIZE, 0, chunk_position.y * MESH_SIZE)
			verts.append(vert)
			uvs.append(Vector2(world_x * noise_scale, world_z * noise_scale))
			normals.append(normal)

	# Create triangles
	for i in range(MESH_SEGMENTS):
		for j in range(MESH_SEGMENTS):
			var current = i * (MESH_SEGMENTS + 1) + j
			var next = current + 1
			var bottom = current + (MESH_SEGMENTS + 1)
			var bottom_next = bottom + 1

			# First triangle
			indices.append(current)
			indices.append(next)
			indices.append(bottom)

			# Second triangle
			indices.append(next)
			indices.append(bottom_next)
			indices.append(bottom)

	surface_array[Mesh.ARRAY_VERTEX] = verts
	surface_array[Mesh.ARRAY_TEX_UV] = uvs
	surface_array[Mesh.ARRAY_NORMAL] = normals
	surface_array[Mesh.ARRAY_INDEX] = indices

	return surface_array

func _ready() -> void:
	setup_noise()
	player = get_parent().get_node("Craft")
	if not player:
		push_error("Player node not found!")
	
	player.position = Vector3(0.1, psyche_radius + 100, 0.1)
	
	generation_mutex = Mutex.new()
	finished_mutex = Mutex.new()
	exit_mutex = Mutex.new()

	generation_thread = Thread.new()
	generation_thread.start(generation_main)

func _process(_delta: float) -> void:
	update_meshes()

func generation_main() -> void:
	while true:
		exit_mutex.lock()
		if exit_thread:
			exit_mutex.unlock()
			break
		exit_mutex.unlock()

		generation_mutex.lock()
		if generation_queue.size() == 0:
			generation_mutex.unlock()
			continue
		
		var chunk_position = generation_queue.pop_front()
		generation_mutex.unlock()

		var surface = generate_mesh(chunk_position)
		finished_mutex.lock()
		finished_meshes[chunk_position] = surface
		finished_mutex.unlock()

func update_meshes() -> void:
	if not player:
		return
		
	var player_mesh_x = floor(player.global_position.x / MESH_SIZE)
	var player_mesh_z = floor(player.global_position.z / MESH_SIZE)
	
	# create list of chunks to generate
	var chunks_to_process = []
	for dx in range(-VIEW_DISTANCE, VIEW_DISTANCE + 1):
		for dz in range(-VIEW_DISTANCE, VIEW_DISTANCE + 1):
			var chunk_pos = Vector2i(player_mesh_x + dx, player_mesh_z + dz)
			
			# Calculate the center point of this chunk in world space
			var chunk_center_x = (chunk_pos.x * MESH_SIZE)
			var chunk_center_z = (chunk_pos.y * MESH_SIZE)
			
			# Calculate the angular distance from the center
			var flat_distance = sqrt(chunk_center_x * chunk_center_x + chunk_center_z * chunk_center_z)
			var theta = flat_distance / psyche_radius
			
			# Skip chunks that would wrap around the sphere (more than 180 degrees)
			if theta >= PI:
				continue
			
			# Calculate squared distance for sorting
			var dist_sq = dx*dx + dz*dz
			if dist_sq > VIEW_DISTANCE*VIEW_DISTANCE:
				continue
			
			chunks_to_process.append({"pos": chunk_pos, "dist": dist_sq})
	
	# sort chunks by distance from player
	chunks_to_process.sort_custom(func(a, b): return a["dist"] < b["dist"])
	
	# add to generation queue in order
	if generation_mutex.try_lock():
		for chunk in chunks_to_process:
			if generation_queue.size() >= max_queued_generations:
				break

			var mesh_key = chunk["pos"]
			if not current_meshes.has(mesh_key) and not generation_queue.has(mesh_key):
				generation_queue.append(mesh_key)
		generation_mutex.unlock()
	
	# add finished meshes to current meshes
	if finished_mutex.try_lock():
		var processed_this_frame = 0
		for chunk_position in finished_meshes.keys():
			if not current_meshes.has(chunk_position):
				current_meshes[chunk_position] = mesh_scene.instantiate()
				current_meshes[chunk_position].accept_mesh(finished_meshes[chunk_position])
				current_meshes[chunk_position].position = Vector3(chunk_position.x * MESH_SIZE, 0, chunk_position.y * MESH_SIZE)
				add_child(current_meshes[chunk_position])
				
				#spawn the gold, cobalt, and platinum
				spawn_resources(chunk_position, current_meshes[chunk_position])
				
				processed_this_frame += 1
				if processed_this_frame >= max_instantiations_per_frame:
					break

			finished_meshes.erase(chunk_position)
		
		finished_mutex.unlock()
	
	# unload meshes that are too far away
	for chunk_position in current_meshes.keys():
		if chunk_position.distance_to(Vector2i(player_mesh_x, player_mesh_z)) > VIEW_DISTANCE:
			current_meshes[chunk_position].queue_free()
			current_meshes.erase(chunk_position)

#importing dummy assets
var platinum_ore = preload("res://scene/resource/platinum_ore.glb")
var gold_ore = preload("res://scene/resource/simple_gold_ore.glb")
var cobalt_ore = preload("res://scene/resource/rock (1).glb")

var sample_scenes = [gold_ore, platinum_ore, cobalt_ore]

func spawn_resources(chunk_position: Vector2i, parent_node: Node3D) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(chunk_position)  #make chunks spawn in consistently

	for i in range(3):  #3 samples per chunk
		var sample_scene = sample_scenes[rng.randi_range(0, sample_scenes.size() - 1)]
		var instance = sample_scene.instantiate()

		#position logic
		var local_x = rng.randf_range(-MESH_SIZE/2, MESH_SIZE/2)
		var local_z = rng.randf_range(-MESH_SIZE/2, MESH_SIZE/2)
		var world_x = chunk_position.x * MESH_SIZE + local_x
		var world_z = chunk_position.y * MESH_SIZE + local_z
		var height = get_height(world_x, world_z)

		#convert spherical coordinates
		var flat_distance = sqrt(world_x * world_x + world_z * world_z)
		var theta = flat_distance / psyche_radius
		var phi = atan2(world_z, world_x)

		var point_on_sphere = Vector3(
			cos(phi) * sin(theta),
			cos(theta),
			sin(phi) * sin(theta)
		) * psyche_radius

		var normal = point_on_sphere.normalized()
		var position = point_on_sphere + (normal * height)

		instance.global_position = position
		parent_node.add_child(instance)



func _exit_tree():
	exit_mutex.lock()
	exit_thread = true
	exit_mutex.unlock()

	generation_thread.wait_to_finish()
