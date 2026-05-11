-- Merge per-PID luacov stats files into a single luacov.stats.out.
-- Plenary's PlenaryBustedDirectory forks a subprocess per spec; without
-- per-PID statsfiles those writes race and clobber each other on exit.

local home = os.getenv("HOME") or ""
local lr_share = home .. "/.luarocks/share/lua/5.1"
package.path = lr_share .. "/?.lua;" .. lr_share .. "/?/init.lua;" .. package.path

local ok, stats = pcall(require, "luacov.stats")
if not ok then
  io.stderr:write("luacov.stats not available: " .. tostring(stats) .. "\n")
  os.exit(1)
end

local handle = io.popen("ls .luacov.stats.*.out 2>/dev/null")
if not handle then
  os.exit(0)
end
local files = {}
for line in handle:lines() do
  table.insert(files, line)
end
handle:close()

if #files == 0 then
  io.stderr:write("no per-pid stats files found\n")
  os.exit(0)
end

local merged = {}
for _, f in ipairs(files) do
  local data = stats.load(f)
  if data then
    for src, src_stats in pairs(data) do
      local dest = merged[src] or { max = 0 }
      for k, v in pairs(src_stats) do
        if k == "max" then
          dest.max = math.max(dest.max, v)
        elseif type(k) == "number" then
          dest[k] = (dest[k] or 0) + v
        end
      end
      merged[src] = dest
    end
  end
end

stats.save("luacov.stats.out", merged)

for _, f in ipairs(files) do
  os.remove(f)
end

print(string.format("merged %d per-pid stats file(s) into luacov.stats.out", #files))
