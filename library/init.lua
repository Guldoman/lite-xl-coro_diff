---Uses the Myers linear algorithm to calculate the diff between two tables.
---
---Doesn't take any shortcuts, unlike git's implementation, to deal with slow
---cases, so it's not as fast as it could be.
---This is why this implementation splits the computation between multiple calls
---to the function returned by `coro_diff.get_diff`, so that the computations is
---non-blocking.
---
---The native module is heavily suggested.
---
---If the elements of the two tables are all strings and the native module is
---used, setting the `cache_strings` parameter of `coro_diff.get_diff` is strongly
---recommended, as it'll avoid many calls to the Lua API which would slow down
---the computation.
---
---@class libraries.coro_diff
local coro_diff = {}

local has_native_midpoint, native_midpoint = pcall(require, "libraries.coro_diff.native.myers_midpoint")
local lua_midpoint = require("libraries.coro_diff.myers_midpoint")

local myers_midpoint = has_native_midpoint and native_midpoint or lua_midpoint

coro_diff.default_implementation = has_native_midpoint and "native" or "lua"

-- Code with strong inspiration from https://blog.jcoglan.com/2017/04/25/myers-diff-in-linear-space-implementation/

---@alias libraries.coro_diff.direction
---| '"+"' Added from `b`
---| '"-"' Removed from `a`
---| '"="' Same in `a` and `b`
---@alias libraries.coro_diff.solution_item {a_index: integer, a_len: integer, b_index: integer, b_len: integer, direction: libraries.coro_diff.direction, values: any[]}
---@alias libraries.coro_diff.solution libraries.coro_diff.solution_item[]

---Get diff between a and b.
---
---Returns a function that will need to be called multiple times, until its first
---returned value is true.
---When it returns true, the second returned value is a table with the resulting diff.
---
---The returned function accepts an optional integer that limits the number of
---iterations that will be done at most, each time.
---
---DO NOT change the content of `a` and `b` until the diff has been returned.
---
---@param a any[]|string
---@param b any[]|string
---@param cache_strings boolean? Creates a cache to use for comparisons, to
---reduce calls to the Lua API.
---Works only if the tables are made up of strings.
---This is ignored when using the Lua implementation.
---@param force_lua boolean? Force the usage of the Lua implementation
---@return fun(iterations: integer?): done: boolean, solution: libraries.coro_diff.solution?
function coro_diff.get_diff(a, b, cache_strings, force_lua)
  local myers_impl = force_lua and lua_midpoint or myers_midpoint
  if type(a) == "string" then
    local tabled_a = {}
    for char in string.gmatch(a, utf8.charpattern) do
      table.insert(tabled_a, char)
    end
    a = tabled_a
  end
  if type(b) == "string" then
    local tabled_b = {}
    for char in string.gmatch(b, utf8.charpattern) do
      table.insert(tabled_b, char)
    end
    b = tabled_b
  end

  return coroutine.wrap(function(iterations)
    iterations = iterations or 1000
    local a_len, b_len = #a, #b
    local a_orig, b_orig = a, b
    if cache_strings then
      a = myers_impl.get_string_cache(a)
      b = myers_impl.get_string_cache(b)
    end

    local iterations_count = 0
    local find_midpoint = function(x1, y1, x2, y2)
      local midpoint_resumable = myers_impl.get_midpoint_resumable(a, b, x1, y1, x2, y2)
      if not midpoint_resumable then return end
      local done, iterations_done, n_x1, n_y1, n_x2, n_y2
      while not done do
        done, iterations_done, n_x1, n_y1, n_x2, n_y2 = midpoint_resumable(iterations - iterations_count)
        iterations_count = iterations_count + iterations_done
        if iterations_count >= iterations then
          iterations_count = 0
          iterations = coroutine.yield(false) or iterations
        end
      end
      return n_x1, n_y1, n_x2, n_y2
    end

    local path = {}
    local function find_path(x1, y1, x2, y2)
      local mid_x1, mid_y1, mid_x2, mid_y2 = find_midpoint(x1, y1, x2, y2)
      if not mid_x1 then return false end

      if not find_path(x1, y1, mid_x1, mid_y1) then
        table.insert(path, {mid_x1, mid_y1})
      end
      if not find_path(mid_x2, mid_y2, x2, y2) then
        table.insert(path, {mid_x2, mid_y2})
      end
      return true
    end

    find_path(0, 0, a_len, b_len)

    local solution = { }
    local function push_to_solution(direction, a_index, b_index, value)
      local a_offset, b_offset = (direction == "+" and 0 or 1), (direction == "-" and 0 or 1)
      if not solution[#solution] or solution[#solution].direction ~= direction then
        table.insert(solution, {
          a_index = a_index, a_len = a_offset,
          b_index = b_index, b_len = b_offset,
          direction = direction, values = { value }
        })
      else
        solution[#solution].a_len = a_index - solution[#solution].a_index + a_offset
        solution[#solution].b_len = b_index - solution[#solution].b_index + b_offset
        table.insert(solution[#solution].values, value)
      end
    end
    local function walk_diagonal(x1, y1, x2, y2)
      while x1 < x2 and y1 < y2 and a_orig[x1+1] == b_orig[y1+1] do
        push_to_solution("=", x1 + 1, y1 + 1, b_orig[y1 + 1])
        x1, y1 = x1 + 1, y1 + 1
      end
      return x1, y1
    end

    for i=1,#path-1 do
      local x1, y1 = table.unpack(path[i])
      local x2, y2 = table.unpack(path[i + 1])
      x1, y1 = walk_diagonal(x1, y1, x2, y2)

      local diff = (x2 - x1) - (y2 - y1)
      if diff > 0 then
        push_to_solution("-", x1 + 1, y1 + 1, a_orig[x1 + 1])
        x1 = x1 + 1
      elseif diff < 0 then
        push_to_solution("+", x1 + 1, y1 + 1, b_orig[y1 + 1])
        y1 = y1 + 1
      end

      walk_diagonal(x1, y1, x2, y2)
    end

    return true, solution
  end)
end

return coro_diff
