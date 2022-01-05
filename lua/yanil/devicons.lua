local ok, icons = pcall(require, "nvim-web-devicons")

if ok then
	if not icons.has_loaded() then
		icons.setup()
	end
end

local M = {}

function M.decorator()
	return function(node)
		if not node.parent then
			local text = "פּ"
			return text, "YanilTreeDirectory"
		end
		if node:is_dir() then
			local icon = node.is_open and "" or ""
			local hl = node:is_link() and "YanilTreeLink" or "YanilTreeDirectory"
			return icon, hl
		end

		if ok then
			local icon, hl = icons.get_icon(node.name, node.extension)

			if icon then
				return icon, hl
			end
		end

		return "", "Normal"
	end
end

return M
