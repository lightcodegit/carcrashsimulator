import io

p = 'scripts/core/dent_body.gd'
s = io.open(p, encoding='utf-8').read()

# 1) удар возвращается к сплошному проходу, но без вызова функции на вершину
a = '''	var moved_v := PackedInt32Array()
	# Ячейки обходятся напрямую: собирать список кандидатов — это ещё один проход
	# и аллокация на ~10 тысяч индексов.
	var center := _cell_key(lp)
	var span := int(ceilf(rl / _cell))
	for cx in range(-span, span + 1):
		for cy in range(-span, span + 1):
			for cz in range(-span, span + 1):
				var key := center + Vector3i(cx, cy, cz)
				if not _grid.has(key): continue
				for i in (_grid[key] as Array):
					if _push_vertex(i, lp, ld, rl, dl, cap_l):
						moved_v.append(i)
	if moved_v.is_empty(): return'''
b = '''	var moved_v := PackedInt32Array()
	# Сплошной проход по вершинам: сетка Tried-а не помогла — максимальный радиус
	# вмятины сопоставим с размером кузова, кандидатов выходило ~85 % меша, а
	# обход по ячейкам с вызовом функции на вершину оказался дороже простого
	# цикла (замер: 5.7 мс против 2.6).
	for i in _verts.size():
		var d := _verts[i].distance_to(lp)
		if d > rl: continue
		var t := d / rl
		var push: float
		if t <= RIM_START:
			var f := 1.0 - t / RIM_START
			push = dl * f * f
		else:
			var r := (t - RIM_START) / (1.0 - RIM_START)
			push = -dl * RIM_RATIO * sin(r * PI)
		# Смещение НАКАПЛИВАЕТСЯ, поэтому потолок нужен именно накопленному
		# отклонению: иначе шкала «КУЗОВ» врёт на повторных вмятинах в одном месте.
		var np: Vector3 = _verts[i] + ld * push
		var off := _pristine[i].distance_to(np)
		if off > cap_l:
			np = _pristine[i] + _pristine[i].direction_to(np) * cap_l
			off = cap_l
		_shift = maxf(_shift, off / _scale)
		_verts[i] = np
		var sc := clampf(absf(push) / maxf(1e-6, dl), 0.0, 1.0)
		_colors[i] = _colors[i].lerp(SCUFF, sc * 0.75)
		moved_v.append(i)
	if moved_v.is_empty(): return'''
assert a in s, 'impact loop'
s = s.replace(a, b, 1)

# 2) helper больше не нужен
c = '''
# Смещение одной вершины: профиль «чаша + валик», потолок на накопленное
# отклонение и след потёртости. Возвращает true, если вершина попала в зону.
func _push_vertex(i: int, lp: Vector3, ld: Vector3, rl: float, dl: float, cap_l: float) -> bool:
	var d := _verts[i].distance_to(lp)
	if d > rl: return false
	var t := d / rl
	var push: float
	if t <= RIM_START:
		var f := 1.0 - t / RIM_START
		push = dl * f * f
	else:
		var r := (t - RIM_START) / (1.0 - RIM_START)
		push = -dl * RIM_RATIO * sin(r * PI)
	# Смещение НАКАПЛИВАЕТСЯ, поэтому потолок нужен именно накопленному отклонению:
	# вторая и третья вмятина в том же месте иначе уводят вершину за предельные
	# 30% высоты (кузов схлопывается внутрь), а шкала «КУЗОВ» этого не видит.
	var np: Vector3 = _verts[i] + ld * push
	var off := _pristine[i].distance_to(np)
	if off > cap_l:
		np = _pristine[i] + _pristine[i].direction_to(np) * cap_l
		off = cap_l
	_shift = maxf(_shift, off / _scale)
	_verts[i] = np
	var sc := clampf(absf(push) / maxf(1e-6, dl), 0.0, 1.0)
	_colors[i] = _colors[i].lerp(SCUFF, sc * 0.75)
	return true
'''
assert c in s, 'helper'
s = s.replace(c, '\n', 1)

# 3) сетка убирается из полей и постройки
d = '''var _shift := 0.0
var rebuild_count := 0'''
e = '''var _shift := 0.0
var rebuild_count := 0'''
s = s.replace("""var _cell := 0.5
var _grid := {}""", "", 1)
s = s.replace("""# Сетка вершин кузова: вмятина ищет вершины в своём радиусе, а не перебором
# всех 11 632 — этот скан и был главной ценой удара внутри физического тика.
""", "", 1)
s = s.replace("\t_build_incidence()\n\t_build_grid()", "\t_build_incidence()", 1)
i = s.index('func _build_grid()')
j = s.index('func _cell_key', i)
k = s.index('# Треугольники вершины', j)
s = s[:i] + s[k:]

io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('grid reverted')
