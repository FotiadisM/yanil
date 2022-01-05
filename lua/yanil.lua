local colors = require("yanil.colors")
local git = require("yanil.git")

local M = {}

function M.setup(opts)
	opts = opts or {}

	colors.setup()
	git.setup(opts.git)
end

return M
