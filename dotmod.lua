local orig_require = _G.require
local orig_lua_searcher = package.searchers[2]

local dirsep = package.config:sub(1, 1)


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


local function expand_package_modname(modname)
  local path = package.searchpath(modname, package.path)
  if path then
    local package_path_endswith = ('%s%sinit.lua'):format(modname:gsub('%.', dirsep), dirsep)
    local _, stop = path:find(package_path_endswith, 1, true)
    if stop and stop == #path then
      modname = modname .. '.init'
    end
  end
  return modname
end


local function dotmod_lua_searcher(modname)
  local path, err
  path, err = package.searchpath(modname, package.path)
  if not path then
    return err
  end

  local file = assert(io.open(path, 'rb'))
  local code = file:read('a')
  local injected_vars = ('local __name, __file = %q, %q\n\n'):format(modname, path)

  local loader
  loader, err = load(injected_vars .. code, '@' .. path)
  if not loader then
    error(("error loading module '%s' from file '%s':\n\t%s"):format(modname, path, err))
  end

  return loader, path
end


local function dotmod_require(modname)
  local abs_modname, err = build_absolute_modname(modname)
  if not abs_modname then
    error(("error loading module '%s':\n\t%s"):format(modname, err))
  end
  abs_modname = expand_package_modname(abs_modname)
  return orig_require(abs_modname)
end


local _M = {}

function _M.enable()
  _G.require = dotmod_require
  package.searchers[2] = dotmod_lua_searcher
end

function _M.disable()
  _G.require = orig_require
  package.searchers[2] = orig_lua_searcher
end

return _M
