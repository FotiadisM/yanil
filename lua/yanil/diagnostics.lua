local api = vim.api

local M = {
	signs = {
		ERROR = "",
		WARN = "",
		INFO = "",
		HINT = "",
	},
	severity = {
		"ERROR",
		"WARN",
		"INFO",
		"HINT",
	},
	buffer_severity = {},
}

function M.setup(signs)
	signs = signs or {}
	M.signs = vim.tbl_deep_extend("keep", M.signs, signs)
end

function M.update()
	local buffer_severity = {}

	for _, diagnostic in ipairs(vim.diagnostic.get()) do
		local buf = diagnostic.bufnr
		if api.nvim_buf_is_valid(buf) then
			local bufname = api.nvim_buf_get_name(buf)
			local lowest_severity = buffer_severity[bufname]
			if not lowest_severity or diagnostic.severity < lowest_severity then
				buffer_severity[bufname] = diagnostic.severity
			end
		end
	end

	M.buffer_severity = buffer_severity
end

function M.refresh_tree(tree)
	for node in tree:iter() do
		tree:refresh(node, { non_recursive = true })
	end
end

function M.decorator()
	return function(node)
		if not node.parent then
			return
		end

		local lowest_severity = nil

		for bufname, severity in pairs(M.buffer_severity) do
			if node:is_dir() then -- find the lowest_severity inside the dir
				if string.find(bufname, node.abs_path) then
					if not lowest_severity or severity < lowest_severity then
						lowest_severity = severity
					end
				end
			end

			if bufname == node.abs_path then
				lowest_severity = severity
			end
		end

		if lowest_severity then
			return M.signs[M.severity[lowest_severity]], "Diagnostic" .. M.severity[lowest_severity]
		end
	end
end

return M
