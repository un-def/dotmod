-- enable dotmod
local __name, __path = require('dotmod').enable()
print(__name, __path)

local inspect = require('inspect')

-- fix hererocks bug
package.path = package.path .. ';./?/init.lua'

require('.module1')
require('.module2')


print(inspect(package.loaded, {depth = 1}))
print(inspect(require('.package')))
