local myers_midpoint = {}

function myers_midpoint.get_midpoint_resumable(a, b, x1, y1, x2, y2)
  local a_len, b_len = #a, #b
  local width = x2 - x1
  local height = y2 - y1
  if width + height == 0 then return end
  local delta = width - height
  local max = math.ceil((width + height) / 2)
  local vf = { x1 }
  local vb = { y2 }

  return function(iterations)
    local function forwards(d, k_init, k_fin)
      for k=k_init,k_fin,-2 do
        local c = k - delta
        local x, y, px, py
        if k == -d or (k ~= d and vf[k - 1] < vf[k + 1]) then
          px = vf[k + 1]
          x = px
        else
          px = vf[k - 1]
          x = px + 1
        end

        y = y1 + (x - x1) - k
        py = (d == 0 or x ~= px) and y or y - 1

        while x < x2 and y < y2 and a[x + 1] == b[y + 1] do
          x, y = x + 1, y + 1
        end

        vf[k] = x
        if delta % 2 ~= 0 and (c >= -(d - 1) and c <= d - 1) and y >= vb[c] then
          return px, py, x, y
        end
      end
    end

    local function backwards(d, c_init, c_fin)
      for c=c_init,c_fin,-2 do
        local k = c + delta
        local x, y, px, py
        if c == -d or (c ~= d and vb[c - 1] > vb[c + 1]) then
          py = vb[c + 1]
          y = py
        else
          py = vb[c - 1]
          y = py - 1
        end

        x = x1 + (y - y1) + k
        px = (d == 0 or y ~= py) and x or x + 1

        while x > x1 and y > y1 and a[x - 1 + 1] == b[y - 1 + 1] do
          x, y = x - 1, y - 1
        end

        vb[c] = y
        if delta % 2 == 0 and (k >= -d and k <= d) and x <= vf[k] then
          return x, y, px, py
        end
      end
    end

    local iterations_count = 0
    local m_x1, m_y1, m_x2, m_y2
    for d=0,max do
      -- Optimization from https://blog.robertelder.org/diff-algorithm/ (myers_diff_length_half_memory)
      local k_init = d - (2 * math.max(0, d - a_len))
      local k_fin = -(d - 2 * math.max(0, d - b_len))
      if k_init >= k_fin then
        m_x1, m_y1, m_x2, m_y2 = forwards(d, k_init, k_fin)
        iterations_count = iterations_count + (k_init - k_fin) // 2 + 1
        if m_x1 then break end
        if iterations_count >= iterations then
          iterations = coroutine.yield(false, iterations_count) or iterations
          iterations_count = 0
        end
      end

      local c_init = d - (2 * math.max(0, d - b_len))
      local c_fin = -(d - 2 * math.max(0, d - a_len))
      if c_init >= c_fin then
        m_x1, m_y1, m_x2, m_y2 = backwards(d, c_init, c_fin)
        iterations_count = iterations_count + (k_init - k_fin) // 2 + 1
        if m_x1 then break end
        if iterations_count >= iterations then
          iterations = coroutine.yield(false, iterations_count) or iterations
          iterations_count = 0
        end
      end
    end

    return true, iterations_count, m_x1, m_y1, m_x2, m_y2
  end
end

function myers_midpoint.get_string_cache(a)
  return a
end

return myers_midpoint
