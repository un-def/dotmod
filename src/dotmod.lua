local dirsep = package.config:sub(1, 1)
-- LuaJIT compat
local searchers = package.searchers or package.loaders

local orig_require = _G.require
local orig_lua_searcher = searchers[2]

-- a set of modnames that seem to be packages,
-- that is, if `foo.bar` resolves to `foo/bar/init.lua`,
-- then this table will contain `["foo.bar"] = true` entry
local package_modnames = {}


local function get_requiring_modname()
  local level = 4
  while true do
    local ok, lname, lvalue = pcall(debug.getlocal, level, 1)
    if not ok then
      return nil, 'failed to find __name variable in call stack'
    end
    if lname == '__name' then
      return lvalue
    end
    level = level + 1
  end
end


local function build_absolute_modname(modname)
  local dots, rel_modname = modname:match('^(%.+)(.*)')
  if not dots then
    return modname
  end

  local req_modname, err = get_requiring_modname()
  if not req_modname then
    return nil, err
  end

  local req_modname_table = {}
  for part in req_modname:gmatch('[^.]+') do
    table.insert(req_modname_table, part)
  end

  local root_parts_count = #req_modname_table - #dots
  if root_parts_count < 0 then
    return nil, 'outside of root'
  elseif root_parts_count == 0 then
    return rel_modname
  else
    modname = table.concat(req_modname_table, '.', 1, root_parts_count)
    if rel_modname == '' then
      return modname
    end
    return modname .. '.' .. rel_modname
  end
end


local function is_package_modname(modname)
  -- maybe we already know that modname is a package?
  if package_modnames[modname] then
    return true
  end
  -- try to resolve modname to file path using Lua standard library function
  local path = package.searchpath(modname, package.path)
  if not path then
    return false
  end
  -- if package.searchpath has resolved `foo.bar` to `foo/bar/init.lua`,
  -- then we assume that `foo.bar` is a package
  local package_path_endswith = ('%s%sinit.lua'):format(modname:gsub('%.', dirsep), dirsep)
  local _, stop = path:find(package_path_endswith, 1, true)
  if stop and stop == #path then
    -- cache the result of this check to avoid future checks
    package_modnames[modname] = true
    return true
  end
  return false
end


local function dotmod_lua_searcher(modname)
  local path, err
  path, err = package.searchpath(modname, package.path)
  if not path then
    return err
  end

  local file = assert(io.open(path, 'rb'))
  local code = file:read('*a')
  local injected_vars = ('local __name, __file = %q, %q\n\n'):format(modname, path)

  local loader
  loader, err = load(injected_vars .. code, '@' .. path)
  if not loader then
    error(("error loading module '%s' from file '%s':\n\t%s"):format(modname, path, err))
  end

  return loader, path
end


local function dotmod_require(modname)
  -- expand relative modname to absolute
  -- or do nothing if it is already absolute
  local abs_modname, err = build_absolute_modname(modname)
  if not abs_modname then
    error(("error loading module '%s':\n\t%s"):format(modname, err))
  end
  -- maybe modname is already loaded?
  local loaded = package.loaded[abs_modname]
  if loaded ~= nil then
    return loaded
  end
  -- maybe modname is a package?
  if is_package_modname(abs_modname) then
    abs_modname = abs_modname .. '.init'
    -- maybe modname.init is already loaded?
    loaded = package.loaded[abs_modname]
    if loaded ~= nil then
      return loaded
    end
  end
  return orig_require(abs_modname)
end


local _M = {}

function _M.enable()
  _G.require = dotmod_require
  searchers[2] = dotmod_lua_searcher
  -- XXX: normalize path
  local path = debug.getinfo(2, 'S').source:match('^@?(.+)')
  local name = path:match('^%.*' .. dirsep .. '?([^.]+)')
  if not name then
    return nil, path
  end
  return name:gsub(dirsep, '.'), path
end

function _M.disable()
  _G.require = orig_require
  searchers[2] = orig_lua_searcher
end

return _M
