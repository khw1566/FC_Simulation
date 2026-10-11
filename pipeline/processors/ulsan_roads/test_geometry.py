"""경계 통과·재진입 및 속성 보존의 짧은 회귀 확인."""
import unittest
import sys
import ast
import json
import tempfile
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from ulsan_roads.geometry import clip_line, clip_segment, width, convert


class GeometryChecks(unittest.TestCase):
    def test_crossing_without_inside_nodes(self):
        self.assertEqual(clip_line([[-20,0,0],[20,0,0]],10),[[[-10.,0.,0.],[10.,0.,0.]]])

    def test_leaving_and_reentering_does_not_join_outside_gap(self):
        result=clip_line([[0,0,0],[20,0,0],[20,0,5],[0,0,5]],10)
        self.assertEqual(len(result),2)
        self.assertEqual(result[0][-1],[10.,0.,0.])
        self.assertEqual(result[1][0],[10.,0.,5.])

    def test_boundary_parallel_outside(self):
        self.assertIsNone(clip_segment([-20,0,11],[20,0,11],10))

    def test_width_tag_and_track_grade(self):
        self.assertEqual(width({"highway":"service","width":"4.5 m"}),(4.5,"osm_width"))
        self.assertEqual(width({"highway":"track","tracktype":"grade5"}),(1.8,"type_estimate"))

    def test_layers_and_original_identity(self):
        config={"bbox":{"west":0,"east":1,"south":0,"north":1},"world_size_meters":100}
        way={"id":11,"version":2,"nodes":[1,2],"geometry":[{"lon":.1,"lat":.5},{"lon":.9,"lat":.5}],
             "tags":{"highway":"secondary","bridge":"viaduct","layer":"2"}}
        roads,reason=convert(way,config)
        self.assertIsNone(reason)
        self.assertTrue(roads[0]["bridge"])
        self.assertEqual(roads[0]["layer"],"2")
        self.assertEqual(roads[0]["osm_id"],11)

    def test_missing_nodes_never_connected(self):
        config={"bbox":{"west":0,"east":1,"south":0,"north":1},"world_size_meters":100}
        roads,reason=convert({"nodes":[1,2],"geometry":[{"lon":.1,"lat":.5}],"tags":{"highway":"path"}},config)
        self.assertEqual((roads,reason),([],"invalid_geometry"))

    def test_building_merge_keeps_active_80km_road_coordinates(self):
        path=Path(__file__).resolve().parents[1]/"merge_ulsan_80km_buildings.py"
        tree=ast.parse(path.read_text(encoding="utf-8"))
        functions=[node for node in tree.body if isinstance(node,ast.FunctionDef) and node.name in ("_load_roads","_project_road_point")]
        namespace={"json":json}
        exec(compile(ast.Module(body=functions,type_ignores=[]),str(path),"exec"),namespace)
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parents[3]/"results/ulsan_80km_roads") as folder:
            active=Path(folder)/"active.json"
            roads=[{"id":"osm_way_11_0","points":[[35000,0,0],[36000,0,0]]}]
            active.write_text(json.dumps({"roads":roads,"tunnels":[],"road_source":{"coverage_complete":True}}),encoding="utf-8")
            result=namespace["_load_roads"]({}, {}, Path(folder)/"missing_core.json",active)
            self.assertEqual(result[0],roads)
            self.assertTrue(result[2]["coverage_complete"])


if __name__=="__main__":
    unittest.main()
