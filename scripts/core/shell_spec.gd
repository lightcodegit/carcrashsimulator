class_name ShellSpec
extends RefCounted
var points: Array[Vector3] = []
var zones: Array[int] = []
var springs: Array = []            # Spring[]
var triangles := PackedInt32Array()
var chassis_nodes: Array[Vector3] = []
var zone_spring_totals: Array[int] = [0, 0, 0, 0, 0]
