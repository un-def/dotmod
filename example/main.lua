-- enable dotmod
require('dotmod').enable()

local inspect = require('inspect')

-- fix hererocks bug
package.path = package.path .. ';./?/init.lua'

-- relative imports in entry points not supported currently
require('example.module1')
require('example.module2')


print(inspect(package.loaded, {depth = 1}))
print(inspect(require('example.package')))
