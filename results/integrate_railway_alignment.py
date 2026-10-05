from pathlib import Path
p=Path('godot_project/scripts/terrain/railway_world_manager.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('var landmarks: Node3D','const Alignment = preload("res://scripts/terrain/railway_alignment_catalog.gd")\nconst Tunnels = preload("res://scripts/terrain/railway_tunnel_world_manager.gd")\nvar _alignment: RefCounted\nvar landmarks: Node3D');s=s.replace('\tvar profiles := {}','\t_alignment = Alignment.new()\n\tif _alignment.data.is_empty():\n\t\tload_error = "철도 종단 및 터널 배치 자산을 읽지 못했습니다."\n\t\treturn\n\tvar profiles := {}',1);s=s.replace('\tfor data in network.routes:','\tvar tunnels := Tunnels.new()\n\ttunnels.name = "RailwayTunnels"\n\tadd_child(tunnels)\n\ttunnels.configure(_alignment,player)\n\tfor data in network.routes:',1);a=s.index('\tvar original := PackedVector3Array()',s.index('func _project_track'));b=s.index('\nfunc _project_route',a);s=s[:a]+'''\tvar record: Dictionary = _alignment.tracks.get(int(track.osm_id),{})
\tvar points: PackedVector3Array = _alignment.projected(record)
\tvar indices: Array = record.get("original_indices",[])
\tfor i in range(indices.size()):
\t\t_elevations[_key(track.points[i])] = points[int(indices[i])].y
\t\tif i>0:
\t\t\t_segments[_key(track.points[i-1])+"|"+_key(track.points[i])] = points.slice(int(indices[i-1]),int(indices[i])+1)
\treturn points
''' +s[b:];p.write_text(s,encoding='utf-8')
p=Path('godot_project/scripts/terrain/terrain_chunk_manager.gd');s=p.read_text(encoding='utf-8-sig');s=s.replace('\tif FileAccess.file_exists(raw_path):\n\t\t_full_heightmap_image', '\tif raw_path.contains("ulsan_metro_80km") and FileAccess.file_exists("res://assets/generated/railway/graded_heightmap_16bit.png"):\n\t\traw_path = "res://assets/generated/railway/graded_heightmap_16bit.png"\n\tif FileAccess.file_exists(raw_path):\n\t\t_full_heightmap_image',1);s=s.replace('_full_heightmap_image = MapImages.read(raw_path)','_full_heightmap_image = MapImages.read(raw_path).duplicate()');p.write_text(s,encoding='utf-8')
