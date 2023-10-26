#define LITE_XL_PLUGIN_ENTRYPOINT
#include <lite_xl_plugin_api.h>

#include <stdbool.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

// Code with strong inspiration from https://blog.jcoglan.com/2017/04/25/myers-diff-in-linear-space-implementation/

typedef struct {
	lua_Integer x1, y1, x2, y2;
} Box;

typedef struct Resumable {
	bool is_cached;
	lua_Integer d;
	lua_Integer n_done;
	bool fwd;
	Box b;
	lua_Integer max;
	lua_Integer v[];
} Resumable;

#define MYERS_CACHE_META "MYERS_CACHE_STRING"
#define STRING_CACHE_SIZE 32
typedef struct {
	size_t len;
	char string[STRING_CACHE_SIZE];
} SizedPartString;

typedef struct {
	int index;
	SizedPartString* sps;
} SizedPartStringContainer;


static int f_get_string_cache(lua_State* L) {
	luaL_checktype(L, 1, LUA_TTABLE);
	lua_Integer len = luaL_len(L, 1);
	size_t size = sizeof(SizedPartString) * len;
	SizedPartString *sps = lua_newuserdatauv(L, size, 1);
	luaL_setmetatable(L, MYERS_CACHE_META);
	lua_pushvalue(L, 1);
	lua_setiuservalue(L, -2, 1);

	for (lua_Integer i = 0; i < len; i++) {
		lua_geti(L, 1, i +1);
		size_t len = 0;
		const char* string = luaL_tolstring(L, -1, &len);
		sps[i].len = len > STRING_CACHE_SIZE ? STRING_CACHE_SIZE : len;
		memcpy(&sps[i].string, string, sps[i].len);
		lua_pop(L, 2);
	}

	return 1;
}

#define FORWARDS(variant, comparator)                                          \
	static bool forwards_##variant(lua_State* L, void* src, void* dst, lua_Integer d, lua_Integer k_init, lua_Integer k_fin, lua_Integer *vf, lua_Integer *vb, const Box *b, Box *result) {\
		lua_Integer width = b->x2 - b->x1;                                         \
		lua_Integer height = b->y2 - b->y1;                                        \
		lua_Integer delta = width - height;                                        \
                                                                               \
		for(lua_Integer k = k_init; k >= k_fin; k-=2) {                            \
			lua_Integer c = k - delta;                                               \
			lua_Integer x, y, px, py;                                                \
			if (k == -d || (k != d && vf[k - 1] < vf[k + 1])) {                      \
				px = vf[k + 1];                                                        \
				x = px;                                                                \
			} else {                                                                 \
				px = vf[k - 1];                                                        \
				x = px + 1;                                                            \
			}                                                                        \
                                                                               \
			y = b->y1 + (x - b->x1) - k;                                             \
			py = (d == 0 || x != px) ? y : y - 1;                                    \
                                                                               \
			while(x < b->x2 && y < b->y2) {                                          \
				comparator                                                             \
			}                                                                        \
                                                                               \
			vf[k] = x;                                                               \
                                                                               \
			if(delta % 2 != 0 && (c >= -(d - 1) && c <= d - 1) && y >= vb[c]) {      \
				result->x1 = px;                                                       \
				result->y1 = py;                                                       \
				result->x2 = x;                                                        \
				result->y2 = y;                                                        \
				return true;                                                           \
			}                                                                        \
		}                                                                          \
		return false;                                                              \
	}

#define BACKWARDS(variant, comparator)                                         \
	static bool backwards_##variant(lua_State* L, void* src, void* dst, lua_Integer d, lua_Integer c_init, lua_Integer c_fin, lua_Integer *vf, lua_Integer *vb, const Box *b, Box *result) {\
		lua_Integer width = b->x2 - b->x1;                                         \
		lua_Integer height = b->y2 - b->y1;                                        \
		lua_Integer delta = width - height;                                        \
                                                                               \
		for (lua_Integer c = c_init; c >= c_fin; c-=2) {                           \
			lua_Integer k = c + delta;                                               \
			lua_Integer x, y, px, py;                                                \
			if (c == -d || (c != d && vb[c - 1] > vb[c + 1])) {                      \
				py = vb[c + 1];                                                        \
				y = py;                                                                \
			} else {                                                                 \
				py = vb[c - 1];                                                        \
				y = py - 1;                                                            \
			}                                                                        \
                                                                               \
			x = b->x1 + (y - b->y1) + k;                                             \
			px = (d == 0 || y != py) ? x : x + 1;                                    \
                                                                               \
			while (x > b->x1 && y > b->y1) {                                         \
				comparator                                                             \
			}                                                                        \
                                                                               \
			vb[c] = y;                                                               \
                                                                               \
			if (delta % 2 == 0 && (k >= -d && k <= d) && x <= vf[k]) {               \
				result->x1 = x;                                                        \
				result->y1 = y;                                                        \
				result->x2 = px;                                                       \
				result->y2 = py;                                                       \
				return true;                                                           \
			}                                                                        \
		}                                                                          \
		return false;                                                              \
	}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpointer-to-int-cast"
FORWARDS(table,
	lua_geti(L, (int)src, x +1);
	lua_geti(L, (int)dst, y +1);
	bool ok = lua_compare(L, -2, -1, LUA_OPEQ);
	lua_pop(L, 2);
	if (!ok) break;
	x++;
	y++;
)

BACKWARDS(table,
	lua_geti(L, (int)src, x - 1 +1);
	lua_geti(L, (int)dst, y - 1 +1);
	bool ok = lua_compare(L, -2, -1, LUA_OPEQ);
	lua_pop(L, 2);
	if (!ok) break;
	x--;
	y--;
)
#pragma GCC diagnostic pop

FORWARDS(cached,
	SizedPartStringContainer* src_sps_c = ((SizedPartStringContainer*)src);
	SizedPartStringContainer* dst_sps_c = ((SizedPartStringContainer*)dst);
	SizedPartString src_sps = src_sps_c->sps[x];
	SizedPartString dst_sps = dst_sps_c->sps[y];
	bool ok = false;
	if (src_sps.len == dst_sps.len && memcmp(src_sps.string, dst_sps.string, src_sps.len) == 0) {
		// If the string is long 32 bytes or more, check it in full
		ok = src_sps.len < STRING_CACHE_SIZE;
		if (!ok) {
			lua_geti(L, src_sps_c->index, x +1);
			lua_geti(L, dst_sps_c->index, y +1);
			ok = lua_compare(L, -2, -1, LUA_OPEQ);
			lua_pop(L, 2);
		}
	}
	if (!ok) break;
	x++;
	y++;
)

BACKWARDS(cached,
	SizedPartStringContainer* src_sps_c = ((SizedPartStringContainer*)src);
	SizedPartStringContainer* dst_sps_c = ((SizedPartStringContainer*)dst);
	SizedPartString src_sps = src_sps_c->sps[x - 1];
	SizedPartString dst_sps = dst_sps_c->sps[y - 1];
	bool ok = false;
	if (src_sps.len == dst_sps.len && memcmp(src_sps.string, dst_sps.string, src_sps.len) == 0) {
		// If the string is long 32 bytes or more, check it in full
		ok = src_sps.len < STRING_CACHE_SIZE;
		if (!ok) {
			lua_geti(L, src_sps_c->index, x - 1 +1);
			lua_geti(L, dst_sps_c->index, y - 1 +1);
			ok = lua_compare(L, -2, -1, LUA_OPEQ);
			lua_pop(L, 2);
		}
	}
	if (!ok) break;
	x--;
	y--;
)

static int f_get_midpoint(lua_State* L) {
	luaL_checktype(L, lua_upvalueindex(1), LUA_TUSERDATA);
	lua_Integer max_iterations = luaL_checkinteger(L, 1);
	Resumable *r = lua_touserdata(L, lua_upvalueindex(1));
	lua_Integer *vf = &r->v[r->max];
	lua_Integer *vb = &r->v[r->max * 2 + 1 + r->max];

	lua_Integer width = r->b.x2 - r->b.x1;
	lua_Integer height = r->b.y2 - r->b.y1;

	lua_Integer size = width + height;
	if(size == 0) return 0;

	lua_getiuservalue(L, lua_upvalueindex(1), 1);
	int a_index = lua_gettop(L);
	lua_getiuservalue(L, lua_upvalueindex(1), 2);
	int b_index = a_index + 1;

	SizedPartStringContainer sps_a = { 0 };
	SizedPartStringContainer sps_b = { 0 };

	if (r->is_cached) {
		sps_a.sps = lua_touserdata(L, a_index);
		lua_getiuservalue(L, a_index, 1);
		sps_a.index = lua_gettop(L);

		sps_b.sps = lua_touserdata(L, b_index);
		lua_getiuservalue(L, b_index, 1);
		sps_b.index = sps_a.index + 1;
	}

	Box result;
	lua_Integer iterations = 0;
	while(r->d <= r->max) {
		lua_Integer kc_n = max_iterations - iterations;
		if(kc_n > r->d + 1 - r->n_done)
			kc_n = r->d + 1 - r->n_done;
		lua_Integer kc_init = r->d - r->n_done * 2;
		lua_Integer kc_fin = kc_init - (2 * (kc_n - 1));

		// Optimization from https://blog.robertelder.org/diff-algorithm/ (myers_diff_length_half_memory)
		lua_Integer limit_h = r->d - (r->fwd ? height : width);
		lua_Integer limit_w = r->d - (r->fwd ? width : height);
		if (limit_h < 0) limit_h = 0;
		if (limit_w < 0) limit_w = 0;

		if (kc_init > r->d - 2*limit_w) {
			kc_init = r->d - 2*limit_w;
		}
		if (kc_fin < -(r->d - 2*limit_h)) {
			kc_fin = -(r->d - 2*limit_h);
		}

		bool found = false;
		if (kc_init >= kc_fin) {
			#pragma GCC diagnostic push
			#pragma GCC diagnostic ignored "-Wint-to-pointer-cast"
			if(r->fwd) {
				if (r->is_cached)
					found = forwards_cached(L, (void*)&sps_a, (void*)&sps_b, r->d, kc_init, kc_fin, vf, vb, &r->b, &result);
				else
					found = forwards_table(L, (void*)a_index, (void*)b_index, r->d, kc_init, kc_fin, vf, vb, &r->b, &result);
			} else {
				if (r->is_cached)
					found = backwards_cached(L, (void*)&sps_a, (void*)&sps_b, r->d, kc_init, kc_fin, vf, vb, &r->b, &result);
				else
					found = backwards_table(L, (void*)a_index, (void*)b_index, r->d, kc_init, kc_fin, vf, vb, &r->b, &result);
			}
			#pragma GCC diagnostic pop
			iterations += (kc_init - kc_fin) / 2 + 1;
		}
		r->n_done += kc_n;
		if(r->n_done > r->d) {
			r->n_done = 0;
			r->fwd = !r->fwd;
			if(r->fwd) {
				r->d++;
			}
		}
		if(found) {
			lua_pushboolean(L, true);
			lua_pushinteger(L, iterations);
			lua_pushinteger(L, result.x1);
			lua_pushinteger(L, result.y1);
			lua_pushinteger(L, result.x2);
			lua_pushinteger(L, result.y2);
			return 6;
		}
		if(iterations >= max_iterations) {
			lua_pushboolean(L, false);
			lua_pushinteger(L, iterations);
			return 2;
		}
	}
	lua_pushboolean(L, true);
	lua_pushinteger(L, iterations);
	lua_pushnil(L);
	lua_pushnil(L);
	lua_pushnil(L);
	lua_pushnil(L);
	return 6;
}

static int f_get_midpoint_resumable(lua_State* L) {
	bool is_cached = false;
	if (luaL_testudata(L, 1, MYERS_CACHE_META) != NULL) {
		luaL_checkudata(L, 2, MYERS_CACHE_META); // If one of the tables is cached, the other one must be too
		is_cached = true;
	} else {
		luaL_checktype(L, 1, LUA_TTABLE); // TODO: maybe it's enough to have a metatable with __index
		luaL_checktype(L, 2, LUA_TTABLE); // TODO: maybe it's enough to have a metatable with __index
	}

	Box b;
	b.x1 = luaL_checkinteger(L, 3);
	b.y1 = luaL_checkinteger(L, 4);
	b.x2 = luaL_checkinteger(L, 5);
	b.y2 = luaL_checkinteger(L, 6);

	lua_Integer width = b.x2 - b.x1;
	lua_Integer height = b.y2 - b.y1;

	lua_Integer size = width + height;
	if(size == 0) return 0;

	lua_Integer max = ceilf(((float)width + height) / 2);

	size_t v_size = 2 * (sizeof(lua_Integer) * (max * 2 + 1));

	Resumable *r = lua_newuserdatauv(L, sizeof(Resumable) + v_size, 2);
	lua_pushvalue(L, 1);
	lua_setiuservalue(L, -2, 1);
	lua_pushvalue(L, 2);
	lua_setiuservalue(L, -2, 2);

	lua_pushcclosure(L, f_get_midpoint, 1);

	r->is_cached = is_cached;
	r->d = 0;
	r->n_done = 0;
	r->fwd = true;
	r->b = b;
	r->max = max;

	lua_Integer *vf = r->v;
	lua_Integer *vb = &r->v[max * 2 + 1];
	vf[max+1] = b.x1;
	vb[max+1] = b.y2;

	return 1;
}

static const luaL_Reg myers_midpoint_lib[] = {
	{ "get_midpoint_resumable", f_get_midpoint_resumable },
	{ "get_string_cache", f_get_string_cache },
	{ NULL, NULL }
};

int luaopen_myers_midpoint(lua_State* L) {
	luaL_newmetatable(L, MYERS_CACHE_META);
	lua_pop(L, 1);
	luaL_newlib(L, myers_midpoint_lib);
	return 1;
}

int luaopen_lite_xl_myers_midpoint(lua_State* L, void* XL) {
	lite_xl_plugin_init(XL);
	return luaopen_myers_midpoint(L);
}
