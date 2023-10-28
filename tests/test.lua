local _require = require
function require(modname, ...)
  modname = string.gsub(modname, "^libraries.coro_diff.", "")
  return _require(modname, ...)
end

---@type libraries.coro_diff
---@diagnostic disable-next-line: assign-type-mismatch
local coro_diff = require "init"

local function compare_solutions(sol_a, sol_b)
  if #sol_a ~= #sol_b then error(string.format("Different number of solutions")) end
  for i=1,#sol_a do
    local s_a = sol_a[i]
    local s_b = sol_b[i]
    for _, key in ipairs({ "a_index", "a_len", "b_index", "b_len", "direction" }) do
      if s_a[key] ~= s_b[key] then
        error(string.format("Different solution a_index: %d/%d b_index: %d/%d a_len: %d/%d b_len: %d/%d direction: %s/%s at index %d",
                            s_a.a_index, s_b.a_index,
                            s_a.b_index, s_b.b_index,
                            s_a.a_len, s_b.a_len,
                            s_a.b_len, s_b.b_len,
                            s_a.direction, s_b.direction, i))
      end
    end
    if #s_a.values ~= #s_b.values then
      error(string.format("Different number of values %d/%d", #s_a.values, #s_b.values))
    end
    for j=1,#s_a.values do
      if s_a.values[j] ~= s_b.values[j] then
        error(string.format("Different solution values [%s] / [%s] at solution %d index %d", s_a.values[j], s_b.values[j], i, j))
      end
    end
  end
end

local function test(a, b, expected)
  local native_differ_getter = coro_diff.get_diff(a, b, true, false)
  local native_done, native_solution
  repeat
    native_done, native_solution = native_differ_getter(math.maxinteger)
  until native_done
  assert(native_solution)

  local native_uncached_differ_getter = coro_diff.get_diff(a, b, false, false)
  local native_uncached_done, native_uncached_solution
  repeat
    native_uncached_done, native_uncached_solution = native_uncached_differ_getter(math.maxinteger)
  until native_uncached_done
  assert(native_uncached_solution)

  local lua_differ_getter = coro_diff.get_diff(a, b, true, true)
  local lua_done, lua_solution
  repeat
    lua_done, lua_solution = lua_differ_getter(math.maxinteger)
  until lua_done
  assert(lua_solution)

  compare_solutions(native_solution, native_uncached_solution)
  compare_solutions(native_solution, lua_solution)
  compare_solutions(native_solution, expected)
end

local tests = {
  {
    description = "Simple",
    a = "ABCABBA",
    b = "CBABAC",
    expected = {
      {
        a_index = 1,
        a_len = 2,
        b_index = 1,
        b_len = 0,
        direction = "-",
        values = { "A", "B" }
      },
      {
        a_index = 3,
        a_len = 1,
        b_index = 1,
        b_len = 1,
        direction = "=",
        values = { "C" }
      },
      {
        a_index = 4,
        a_len = 1,
        b_index = 2,
        b_len = 0,
        direction = "-",
        values = { "A" }
      },
      {
        a_index = 5,
        a_len = 1,
        b_index = 2,
        b_len = 1,
        direction = "=",
        values = { "B" }
      },
      {
        a_index = 6,
        a_len = 0,
        b_index = 3,
        b_len = 1,
        direction = "+",
        values = { "A" }
      },
      {
        a_index = 6,
        a_len = 2,
        b_index = 4,
        b_len = 2,
        direction = "=",
        values = { "B", "A" }
      },
      {
        a_index = 8,
        a_len = 0,
        b_index = 6,
        b_len = 1,
        direction = "+",
        values = { "C" }
      },
    },
  },
  {
    description = "Empty",
    a = "",
    b = "",
    expected = {
    },
  },
  {
    description = "Addition only",
    a = "",
    b = "CBABAC",
    expected = {
      {
        a_index = 1,
        a_len = 0,
        b_index = 1,
        b_len = 6,
        direction = "+",
        values = { "C", "B", "A", "B", "A", "C" }
      },
    },
  },
  {
    description = "Removal only",
    a = "ABCABBA",
    b = "",
    expected = {
      {
        a_index = 1,
        a_len = 7,
        b_index = 1,
        b_len = 0,
        direction = "-",
        values = { "A", "B", "C", "A", "B", "B", "A" }
      },
    },
  },
  {
    description = "Same",
    a = "ABCABBA",
    b = "ABCABBA",
    expected = {
      {
        a_index = 1,
        a_len = 7,
        b_index = 1,
        b_len = 7,
        direction = "=",
        values = { "A", "B", "C", "A", "B", "B", "A" }
      },
    },
  },
}

print(string.format("1..%d", #tests))
for i, t in ipairs(tests) do
  local ok, err = pcall(test, t.a, t.b, t.expected)
  print(string.format("%sok %d - %s", not ok and "not " or "", i, t.description))
  if not ok then io.stderr:write(string.format("%s\n", err)) end
end
