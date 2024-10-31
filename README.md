# `coro_diff`

This Lite XL library uses the Myers algorithm to obtain the differences between two tables of strings in an asynchronous way.

## Example

```lua
local coro_diff = require "libraries.coro_diff"

local diff_getter = coro_diff.get_diff({ "Hello", "world" }, { "Hi", "world" })
local solution
repeat
  local done
  done, solution = diff_getter()
  -- coroutine.yield()
until done

for _, d in ipairs(solution) do
  print(string.format("%s %s", d.direction, table.concat(d.values)))
end
-- Output:
-- - Hello
-- + Hi
-- = world
```
