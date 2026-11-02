extends Node
var car_id := "sedan"
var map_id := "arena"
# id проверяются по БД: случайная/устаревшая строка не должна доживать до сборки
# заезда, где null-параметры от VehicleDB уронят car.build
func select(c: String, m: String) -> void:
	if c in VehicleDB.ids(): car_id = c
	if m in MapDB.ids(): map_id = m
