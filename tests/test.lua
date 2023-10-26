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
    if s_a.start_index ~= s_b.start_index or s_a.end_index ~= s_b.end_index or s_a.direction ~= s_b.direction then
      error(string.format("Different solution start_index: %d/%d end_index: %d/%d direction: %s/%s at index %d", s_a.start_index, s_b.start_index, s_a.end_index, s_b.end_index, s_a.direction, s_b.direction, i))
    end
    for j=s_a.start_index,s_a.end_index do
      if s_a.values[j - s_a.start_index + 1] ~= s_b.values[j - s_b.start_index + 1] then
        error(string.format("Different solution values [%s] / [%s] at solution %d index %d", s_a.values[j - s_a.start_index + 1], s_b.values[j - s_b.start_index + 1], i, j))
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
        start_index = 1,
        end_index = 2,
        direction = "-",
        values = { "A", "B" }
      },
      {
        start_index = 3,
        end_index = 3,
        direction = "=",
        values = { "C" }
      },
      {
        start_index = 4,
        end_index = 4,
        direction = "-",
        values = { "A" }
      },
      {
        start_index = 5,
        end_index = 5,
        direction = "=",
        values = { "B" }
      },
      {
        start_index = 3,
        end_index = 3,
        direction = "+",
        values = { "A" }
      },
      {
        start_index = 6,
        end_index = 7,
        direction = "=",
        values = { "B", "A" }
      },
      {
        start_index = 6,
        end_index = 6,
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
        start_index = 1,
        end_index = 6,
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
        start_index = 1,
        end_index = 7,
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
        start_index = 1,
        end_index = 7,
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
