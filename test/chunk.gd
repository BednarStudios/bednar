extends Node3D
class_name Chunk

const CHUNK_SIZE = Vector3i(16, 256, 16)

var global_block_data: Array
var global_world_block_map: Dictionary
var world

var block_meshes: Dictionary = {}        # block type -> ArrayMesh (base, se necessário)
var block_uv_regions: Dictionary = {}      # block type -> Rect2, usado para UV mapping
var mesh_instances: Dictionary = {}        # block type -> MultiMeshInstance3D
var grouped_blocks: Dictionary = {}
var parent_node: Node3D                    # nó pai (instanciado via World.gd)
var chunk_tools

func _init(_parent_node: Node3D, _block_meshes: Dictionary, _block_uv_regions: Dictionary, _world):
	parent_node = _parent_node
	block_meshes = _block_meshes
	block_uv_regions = _block_uv_regions
	world = _world

func _ready() -> void:
	chunk_tools = ChunkTools.new(self, world)

#region Collision
func generate_collision_shape_from_mesh(mesh: ArrayMesh) -> ConcavePolygonShape3D:
	var shape = ConcavePolygonShape3D.new()
	var faces = []
	
	for i in range(mesh.get_surface_count()):
		var arrays = mesh.surface_get_arrays(i)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		
		for j in range(0, indices.size(), 3):
			faces.append(vertices[indices[j]])
			faces.append(vertices[indices[j + 1]])
			faces.append(vertices[indices[j + 2]])
	
	shape.set_faces(faces)
	return shape
#endregion

func _get_face_uv(face_index: int, uv_data_dict: Dictionary, face_size: Vector2 = Vector2(1, 1)) -> Array:
	var uv_info = uv_data_dict.get("all", {"P": Vector2(0, 0), "S": Vector2(1, 1)})
	
	if uv_data_dict.has("side") and face_index in [0,1,2,3]:
		uv_info = uv_data_dict["side"]
	elif uv_data_dict.has("top") and face_index == 4:
		uv_info = uv_data_dict["top"]
	elif uv_data_dict.has("bottom") and face_index == 5:
		uv_info = uv_data_dict["bottom"]
	elif uv_data_dict.has("front") and face_index == 0:
		uv_info = uv_data_dict["front"]
	elif uv_data_dict.has("back") and face_index == 1:
		uv_info = uv_data_dict["back"]
	elif uv_data_dict.has("left") and face_index == 2:
		uv_info = uv_data_dict["left"]
	elif uv_data_dict.has("right") and face_index == 3:
		uv_info = uv_data_dict["right"]

	var pos
	var size_val
	
	if uv_info is Dictionary:
		pos = uv_info.get("P", uv_info.get("position", Vector2.ZERO))
		size_val = uv_info.get("S", uv_info.get("size", Vector2.ONE))
	elif uv_info is Rect2:
		pos = uv_info.position
		size_val = uv_info.size
	
	# Ajustar os UVs com base no tamanho da face
	var uv0 = pos + Vector2(0, size_val.y * face_size.y)
	var uv1 = pos + Vector2(size_val.x * face_size.x, size_val.y * face_size.y)
	var uv2 = pos + Vector2(size_val.x * face_size.x, 0)
	var uv3 = pos
	return [uv0, uv1, uv2, uv3]

func merge_multiple_meshes(meshes: Dictionary) -> ArrayMesh:
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for mesh in meshes.values():
		if mesh is ArrayMesh and mesh.get_surface_count() > 0:
			var arrays = mesh.surface_get_arrays(0)
			if not arrays.is_empty():
				surface_tool.append_from(mesh, 0, Transform3D.IDENTITY)

	var merged_mesh = surface_tool.commit()
	return merged_mesh

# Função para mesclar os cubos de um mesmo tipo em uma única ArrayMesh
func merge_cubes(blocks: Array, uv_region: Dictionary, chunk_origin: Vector3, size: Vector3) -> ArrayMesh:
	# Função auxiliar que retorna as 4 coordenadas UV para a face corrente,
	# conforme os dados passados no uv_region.
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	var vertex_offset = 0
	var half = size * 0.5
	
	# Definição das direções normais para cada face
	var face_dirs = [
		Vector3(0, 0, -1), # frente
		Vector3(0, 0, 1),  # trás
		Vector3(-1, 0, 0), # esquerda
		Vector3(1, 0, 0),  # direita
		Vector3(0, 1, 0),  # cima
		Vector3(0, -1, 0), # baixo
	]
	
	# Definição dos vértices de um cubo centrado na origem
	var face_vertices = [
		[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],   # frente
		[Vector3(1, -1, 1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(1, 1, 1)],       # trás
		[Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, 1, 1)],     # esquerda
		[Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)],         # direita
		[Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],         # cima
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(-1, -1, -1)],     # baixo
	]
	
	# Para cada bloco do grupo, aplica o offset e inclui somente as faces visíveis
	for block in blocks:
		var local_pos: Vector3i = block[0]      # posição do bloco
		var visible_faces: Array = block[1]       # face indices visíveis
		
		# Calcula o deslocamento relativo (posição do bloco dentro do chunk)
		var offset = Vector3(local_pos.x, local_pos.y, local_pos.z) - chunk_origin
		for face in visible_faces:
			# Obtém os UVs correspondentes para a face corrente
			var current_face_uvs = _get_face_uv(face, uv_region)
			# Para cada um dos 4 vértices da face:
			for j in range(4):
				var vert = face_vertices[face][j] * half + offset
				vertices.append(vert)
				normals.append(face_dirs[face])
				uvs.append(current_face_uvs[j])
			# Adiciona os índices para os dois triângulos dessa face
			indices.append(vertex_offset + 0)
			indices.append(vertex_offset + 1)
			indices.append(vertex_offset + 2)
			indices.append(vertex_offset + 2)
			indices.append(vertex_offset + 3)
			indices.append(vertex_offset + 0)
			vertex_offset += 4
	
	if vertices.is_empty() or indices.is_empty():
		return ArrayMesh.new()
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var merged_mesh = ArrayMesh.new()
	merged_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return merged_mesh

@warning_ignore("unused_parameter")
func merge_cubes_custom(
	geo_json: Dictionary,
	blocks: Array,
	block_type: String,
	uv_region: Dictionary,
	chunk_origin: Vector3,
	size: Vector3,
	build_unique_model := false
) -> ArrayMesh:
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	var vertex_offset = 0

	var face_dirs = [
		Vector3(0, 0, -1),
		Vector3(0, 0, 1),
		Vector3(-1, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0, 1, 0),
		Vector3(0, -1, 0)
	]

	var face_vertices = [
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
		[Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)],
		[Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1)],
		[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)]
	]

	var bones = geo_json.get("minecraft:geometry", {}).get("bones", [])

	for block in blocks:
		var local_pos: Vector3i = block[0]
		var visible_faces = block[1]
		var meta = block[2]
		var rotation_deg = meta.get("rotation", 0)

		var offset = Vector3(local_pos) - chunk_origin
		offset = offset.round()
		offset.x -= 1.0
		offset.y -= 0.5
		var rot_basis = Basis(Vector3.UP, deg_to_rad(rotation_deg))

		# 🧩 Caso seja bloco com build_unique_model ativado
		if build_unique_model:
			var mesh: ArrayMesh = world.block_meshes.get(block_type, null)
			if mesh != null and mesh.get_surface_count() > 0:
				var arr = mesh.surface_get_arrays(0)
				var mesh_verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var mesh_normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var mesh_uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
				var mesh_indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX]

				for i in mesh_verts.size():
					var transformed_vert = rot_basis * mesh_verts[i] + offset
					var transformed_normal = rot_basis * mesh_normals[i]
					vertices.append(transformed_vert)
					normals.append(transformed_normal)
					if i < mesh_uvs.size():
						uvs.append(mesh_uvs[i])
					else:
						uvs.append(Vector2.ZERO)

				for idx in mesh_indices:
					indices.append(vertex_offset + idx)

				vertex_offset += mesh_verts.size()
			continue  # Pula para o próximo bloco

		# 🔶 Bloco padrão (usa geo_json)
		for bone in bones:
			var cubes = bone.get("cubes", [])
			for cube in cubes:
				var origin = Vector3(
					cube["origin"][0] / 16.0,
					cube["origin"][1] / 16.0,
					cube["origin"][2] / 16.0
				)
				var size_val = Vector3(
					cube["size"][0],
					cube["size"][1],
					cube["size"][2]
				)

				for face_index in range(6):
					if face_index in visible_faces:
						var face_size: Vector2
						match face_index:
							0, 1: face_size = Vector2(size_val.x, size_val.y)
							2, 3: face_size = Vector2(size_val.z, size_val.y)
							4, 5: face_size = Vector2(size_val.x, size_val.z)

						var current_face_uvs = _get_face_uv(face_index, uv_region, face_size)
						var face_dir = face_dirs[face_index]
						var face_verts = face_vertices[face_index]

						for j in range(4):
							var vert = face_verts[j] * size_val + origin
							vert = rot_basis * vert + offset
							vertices.append(vert)
							normals.append((rot_basis * face_dir).normalized())
							uvs.append(current_face_uvs[j])

						indices.append(vertex_offset + 0)
						indices.append(vertex_offset + 1)
						indices.append(vertex_offset + 2)
						indices.append(vertex_offset + 2)
						indices.append(vertex_offset + 3)
						indices.append(vertex_offset + 0)
						vertex_offset += 4

	# Finalização da mesh
	if vertices.is_empty() or indices.is_empty():
		return ArrayMesh.new()

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var merged_mesh = ArrayMesh.new()
	merged_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return merged_mesh

# Em Chunk.gd
func generate_chunk(block_data: Array, global_block_map: Dictionary):
	# Definindo as direções das 6 faces
	var directions = [
		Vector3i(0, 0, -1), # frente
		Vector3i(0, 0, 1),  # trás
		Vector3i(-1, 0, 0), # esquerda
		Vector3i(1, 0, 0),  # direita
		Vector3i(0, 1, 0),  # cima
		Vector3i(0, -1, 0), # baixo
	]

	global_block_data = block_data
	global_world_block_map = global_block_map

	# Agrupar blocos por tipo, salvando também as faces que devem ser desenhadas
	grouped_blocks = {}
	var all_meshes := {}

	for b in block_data:
		var local_rot: float = b.get("rotation", 0.0)
		var local_pos: Vector3i = b["position"]
		var block_type: String = b["block_id"]
		var block_info = world.world_loader.blocks_data.get(block_type, {})
		var block_custom_data = block_info.custom_data
		var visible_faces = []
		
		if not block_info.linked_blocks.is_empty():
			set_block_linked_blocks(
				block_info.linked_blocks,
				local_pos,
				grouped_blocks,
				global_world_block_map,
			)
		
		var occluding_settings = block_info.occluding_settings if block_info.occluding_settings else {}
		for i in range(directions.size()):
			var neighbor_pos = local_pos + directions[i]
			var direction_key = ["front", "back", "left", "right", "top", "bottom"][i]
			var this_block_occludes = chunk_tools.get_occlusion_for(direction_key, occluding_settings)
			if not global_world_block_map.has(neighbor_pos):
				visible_faces.append(i)
			else:
				var neighbor_block_type = global_world_block_map[neighbor_pos]["block_id"]
				var neighbor_block_info = world.world_loader.blocks_data.get(neighbor_block_type, {})
				var neighbor_occlusion = neighbor_block_info.occluding_settings if neighbor_block_info.occluding_settings else {}
				var neighbor_occludes = chunk_tools.get_occlusion_for(direction_key, neighbor_occlusion)
				
				if not this_block_occludes or not neighbor_occludes:
					visible_faces.append(i)
		
		if not grouped_blocks.has(block_type):
			grouped_blocks[block_type] = []

		grouped_blocks[block_type].append([local_pos, visible_faces, {"rotation": local_rot, "custom_data": block_custom_data}])
		global_world_block_map[local_pos] = {"block_id": block_type, "visible_faces": visible_faces}

	# Para cada tipo de bloco, gera a malha combinada e cria o MultiMeshInstance3D com instance_count 1
	for block_type in grouped_blocks.keys():
		var uv_region = block_uv_regions[block_type]
		var block_inherit = world.world_loader.blocks_data[block_type].inherit
		var block_info = world.world_loader.blocks_data[block_type]

		# Aqui chamamos a função de merge para criar a ArrayMesh com os blocos desse grupo.
		var merged_mesh
		
		if chunk_tools.is_custom_block(block_inherit):
			var geo_json = chunk_tools.load_custom_block_geometry(block_inherit)
			merged_mesh = merge_cubes_custom(
				geo_json,
				grouped_blocks[block_type],
				block_type,
				uv_region,
				self.position,
				Vector3.ONE,
				block_info.build_unique_model
			)
		else:
			merged_mesh = merge_cubes(
				grouped_blocks[block_type],
				uv_region,
				self.position,
				Vector3.ONE
			)
			
		if merged_mesh.get_surface_count() > 0:
			all_meshes.set(block_type, merged_mesh)
		
	if not all_meshes.is_empty():
		var final_mesh = merge_multiple_meshes(all_meshes)
		
		var mmi = MultiMeshInstance3D.new()
		mmi.name = "chunk_mesh"

		var mm = MultiMesh.new()
		mm.mesh = final_mesh
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)

		mmi.multimesh = mm
		add_child(mmi)
		for block_type in all_meshes.values():
			mesh_instances[block_type] = mmi

	update_collider()

#region Collider
func update_collider() -> void:
	# 1. Remove o colisor antigo
	var old_collider = get_node_or_null("chunk_collision")
	if old_collider:
		remove_child(old_collider)
		old_collider.queue_free()

	# 2. Prepara para agregar as faces de todas as malhas da chunk
	var all_faces = PackedVector3Array()

	# 3. Itera sobre as malhas visuais que já foram geradas
	for mmi in mesh_instances.values():
		# Pega a ArrayMesh associada a este MultiMeshInstance
		var mesh: ArrayMesh = mmi.multimesh.mesh
		if not mesh:
			continue

		# Extrai os dados da superfície da malha
		# Assumindo que cada malha tem apenas uma superfície (índice 0)
		if not mesh.get_surface_count() > 0:
			continue
		
		var surface_arrays = mesh.surface_get_arrays(0)
		
		if surface_arrays.is_empty():
			continue
		
		var vertices = surface_arrays[Mesh.ARRAY_VERTEX]
		var indices = surface_arrays[Mesh.ARRAY_INDEX]

		if vertices.is_empty() or indices.is_empty():
			continue

		# 4. Adiciona as faces (triângulos) desta malha à lista geral
		for i in range(0, indices.size(), 3):
			all_faces.append(vertices[indices[i]])
			all_faces.append(vertices[indices[i + 1]])
			all_faces.append(vertices[indices[i + 2]])

	# Se não houver faces visíveis, não há por que criar um colisor
	if all_faces.is_empty():
		return

	# 5. Cria a forma de colisão a partir das faces agregadas
	var final_shape = ConcavePolygonShape3D.new()
	final_shape.set_faces(all_faces)
	
	# --- APLICAR AO COLLIDER ---
	var static_body = ChunkCollision.new() # Supondo que ChunkCollision herde de StaticBody3D
	static_body.collision_layer = 2
	static_body.collision_mask = 0
	static_body.name = "chunk_collision"
	
	var collider = CollisionShape3D.new()
	collider.shape = final_shape
	static_body.add_child(collider)
	
	add_child(static_body)
#endregion

#region Update
# Função para recalcular faces visíveis de um bloco específico no chunk
func recalculate_block_face_visibility(block_local_pos: Vector3i, block_type: String, current_global_block_map: Dictionary):
	var block_entry_index = -1
	if not grouped_blocks.has(block_type):
		return

	# Encontra o bloco específico na lista do seu tipo
	for i in range(grouped_blocks[block_type].size()):
		var entry = grouped_blocks[block_type][i] # entry é [Vector3i_pos, Array_visible_faces]
		if entry[0] == block_local_pos:
			block_entry_index = i
			break
	
	if block_entry_index == -1:
		return

	var new_visible_faces = []
	var directions = [
		Vector3i(0,  0, -1),
		Vector3i(0,  0,  1),
		Vector3i(-1,  0,  0),
		Vector3i(1,  0,  0),
		Vector3i(0,  1,  0),
		Vector3i(0, -1,  0)
	]
	var block_info = world.world_loader.blocks_data.get(block_type, {})
	var occluding_settings = block_info.occluding_settings if block_info.occluding_settings else {}
	for i in range(directions.size()):
		# Posição global do vizinho a ser verificado no mapa
		var neighbor_to_check_global_pos = block_local_pos + directions[i]
		var direction_key = ["front", "back", "left", "right", "top", "bottom"][i]
		var this_block_occludes = chunk_tools.get_occlusion_for(direction_key, occluding_settings)
		
		if not current_global_block_map.has(neighbor_to_check_global_pos):
			new_visible_faces.append(i)
		else:
			var neighbor_block_type = global_world_block_map[neighbor_to_check_global_pos]["block_id"]
			var neighbor_block_info = world.world_loader.blocks_data.get(neighbor_block_type, {})
			var neighbor_occlusion = neighbor_block_info.occluding_settings if neighbor_block_info.occluding_settings else {}
			var neighbor_occludes = chunk_tools.get_occlusion_for(direction_key, neighbor_occlusion)
				
			if not this_block_occludes or not neighbor_occludes:
				new_visible_faces.append(i)
	
	# Atualiza a lista de faces visíveis para este bloco específico
	grouped_blocks[block_type][block_entry_index][1] = new_visible_faces
	
	if current_global_block_map.has(block_local_pos):
		current_global_block_map[block_local_pos]["visible_faces"] = new_visible_faces

func _update_mesh_for_block_type(block_type: String) -> void:
	var uv_region = block_uv_regions[block_type]

	if not grouped_blocks.has(block_type) or grouped_blocks[block_type].is_empty():
		rebuild_merged_mesh()
		return
	
	var block_inherit = world.world_loader.blocks_data[block_type].inherit

	var new_mesh
	
	if chunk_tools.is_custom_block(block_inherit):
		var geo_json = chunk_tools.load_custom_block_geometry(block_inherit)
		new_mesh = merge_cubes_custom(
			geo_json,
			grouped_blocks[block_type],
			block_type,
			uv_region,
			self.position,
			Vector3.ONE,
			world.world_loader.blocks_data[block_type].build_unique_model
		)
	else:
		new_mesh = merge_cubes(
			grouped_blocks[block_type],
			uv_region,
			self.position,
			Vector3.ONE
		)
	
	var mmi: MultiMeshInstance3D
	if mesh_instances.has(block_type):
		mmi = mesh_instances[block_type]
	else:
		# Se não existia, cria um novo (para o caso de um tipo de bloco reaparecer)
		mmi = MultiMeshInstance3D.new()
		mmi.name = "chunk_%s" % block_type # Nome pode ser mais descritivo
		mesh_instances[block_type] = mmi
		
		var block_info = world.world_loader.blocks_data[block_type]
		
		if not block_info.texture_alpha:
			mmi.material_override = world.global_material
		else:
			mmi.material_override = world.global_alpha_material

	var mm = MultiMesh.new()
	mm.mesh = new_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	mmi.multimesh = mm
	rebuild_merged_mesh()

func rebuild_merged_mesh():
	var all_meshes := {}
	
	for block_type in grouped_blocks:
		var block_inherit = world.world_loader.blocks_data[block_type].inherit
		var uv_region = block_uv_regions[block_type]
		
		var merged_mesh
		if chunk_tools.is_custom_block(block_inherit):
			var geo_json = chunk_tools.load_custom_block_geometry(block_inherit)
			merged_mesh = merge_cubes_custom(
				geo_json,
				grouped_blocks[block_type],
				block_type,
				uv_region,
				self.position,
				Vector3.ONE,
				world.world_loader.blocks_data[block_type].build_unique_model
			)
		else:
			merged_mesh = merge_cubes(
				grouped_blocks[block_type],
				uv_region,
				self.position,
				Vector3.ONE
			)
		
		if merged_mesh.get_surface_count() > 0:
			all_meshes[block_type] = merged_mesh
	
	if not all_meshes.is_empty():
		var final_mesh = merge_multiple_meshes(all_meshes)
		
		var mmi = get_node_or_null("chunk_mesh")
		if not mmi:
			mmi = MultiMeshInstance3D.new()
			mmi.name = "chunk_mesh"
			add_child(mmi)
		
		var mm = MultiMesh.new()
		mm.mesh = final_mesh
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		
		mmi.multimesh = mm
		
		# Aplica o material correto
		for block_type in all_meshes:
			if world.world_loader.blocks_data[block_type].texture_alpha:
				mmi.material_override = world.global_alpha_material
				break
			else:
				mmi.material_override = world.global_material
		
			mesh_instances[block_type] = mmi

func global_to_local(g_pos: Vector3i) -> Vector3i:
	return g_pos - Vector3i(self.global_position)
#endregion

#region Linked Blocks
@warning_ignore("shadowed_variable")
func set_block_linked_blocks(linked_blocks: Dictionary, base_position: Vector3i, grouped_blocks: Dictionary, global_block_map: Dictionary):
	# Obter a rotação do bloco principal (em graus)
	var base_rotation = 0
	if global_block_map.has(base_position) and global_block_map[base_position].has("rotation"):
		base_rotation = global_block_map[base_position]["rotation"]
	
	# Converter para radianos e criar uma base de rotação
	var rotation_rad = deg_to_rad(base_rotation)
	var rot_basis = Basis(Vector3.UP, rotation_rad)

	for direction in linked_blocks.keys():
		var linked_block_str = str(linked_blocks[direction])
		var id_regex = RegEx.new()
		id_regex.compile(r"id=(.+)$")
		var result = id_regex.search(linked_block_str)
		if not result:
			continue
		var linked_block_id = result.get_string(1)

		# Determinar a posição relativa baseada na rotação
		var offset_local = Vector3i.ZERO
		match direction:
			"top": offset_local = Vector3i(0, 1, 0)
			"bottom": offset_local = Vector3i(0, -1, 0)
			"left": offset_local = Vector3i(-1, 0, 0)
			"right": offset_local = Vector3i(1, 0, 0)
			"front": offset_local = Vector3i(0, 0, 1)
			"back": offset_local = Vector3i(0, 0, -1)
		
		# Rotacionar o offset de acordo com a rotação do bloco principal
		var offset_rotated = rot_basis * Vector3(offset_local)
		var offset = Vector3i(
			round(offset_rotated.x),
			round(offset_rotated.y),
			round(offset_rotated.z)
		)

		var linked_pos = base_position + offset

		# Ignorar se já existe algo na posição
		if global_block_map.has(linked_pos):
			continue

		# Adicionar nos blocos agrupados
		if not grouped_blocks.has(linked_block_id):
			grouped_blocks[linked_block_id] = []
		
		# Manter a mesma rotação do bloco principal
		var block_info = world.world_loader.blocks_data[linked_block_id]
		grouped_blocks[linked_block_id].append([
			linked_pos, 
			[0, 1, 2, 3, 4, 5], # Todas faces visíveis inicialmente
			{
				"rotation": base_rotation, # Mesma rotação do principal
				"custom_data": block_info.custom_data
			}
		])
		
		# Atualiza o mapa global
		global_block_map[linked_pos] = {
			"block_id": linked_block_id, 
			"visible_faces": [],
			"rotation": base_rotation # Garantir que a rotação seja armazenada
		}

@warning_ignore("shadowed_variable")
func destroy_block_linked_blocks(linked_blocks: Dictionary, base_position: Vector3i, _grouped_blocks: Dictionary, global_block_map: Dictionary):
	for direction in linked_blocks.keys():
		var linked_block_str = str(linked_blocks[direction]) # Exemplo: "bednar:block.id=oak_door_top"

		# Extrair o ID do bloco vinculado
		var id_regex = RegEx.new()
		id_regex.compile(r"id=(.+)$")
		var result = id_regex.search(linked_block_str)
		if not result:
			continue
		var linked_block_id = result.get_string(1)

		# Calcular a posição relativa
		var offset
		match direction:
			"top": offset = Vector3i(0, 1, 0)
			"bottom": offset = Vector3i(0, -1, 0)
			"left": offset = Vector3i(-1, 0, 0)
			"right": offset = Vector3i(1, 0, 0)
			"front": offset = Vector3i(0, 0, -1)
			"back": offset = Vector3i(0, 0, 1)
			_: offset = Vector3i.ZERO

		var linked_pos = base_position + offset

		# Verificar se o bloco na posição é o que queremos remover
		if global_block_map.has(linked_pos):
			var data = global_block_map[linked_pos]
			if data.has("block_id") and data["block_id"] == linked_block_id:
				# Remover do mapa global
				global_block_map.erase(linked_pos)

		# Remover também do chunk local, se existir
		if _grouped_blocks.has(linked_block_id):
			# Procurar e remover a posição na lista
			var blocks = _grouped_blocks[linked_block_id]
			for i in range(blocks.size()):
				if blocks[i][0] == linked_pos:
					blocks.remove_at(i)
					break
#endregion
