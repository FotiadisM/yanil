local api = vim.api
local loop = vim.loop
local git = require("yanil.git")

local section = require("yanil.section")
local nodelib = require("yanil.node")
local utils = require("yanil.utils")

local Job = require("plenary.job")

local M = section:new({
	name = "Tree",
})

function M:setup(opts)
	opts = opts or {}

	local default_keymaps = {
		["<CR>"] = self.open_node,
		["<BS>"] = self.close_node,

		l = self.open_node,
		h = self.close_node,
		v = self:gen_open_file_node("vsplit"),
		s = self:gen_open_file_node("split"),

		a = self.create_node,
		d = self.delete_node,
		r = self.rename_node,

		["]c"] = git.jump_next,
		["[c"] = git.jump_prev,

		C = self.cd_to_node,
		U = self.cd_to_parent,
		K = self.go_to_first_child,
		J = self.go_to_last_child,

		R = self.force_refresh_tree,
		q = function()
			vim.fn.execute("quit")
		end,
	}

	self.draw_opts = opts.draw_opts
	self.filters = opts.filters
	self.keymaps = opts.keymaps or {}
end

function M:set_cwd(cwd)
	cwd = cwd or loop.cwd()
	if not vim.endswith(cwd, utils.path_sep) then
		cwd = cwd .. utils.path_sep
	end
	if self.cwd == cwd then
		return
	end
	self.cwd = cwd

	self.root = nodelib.Dir:new({
		name = cwd,
		abs_path = cwd,
		filters = self.filters,
	})

	self.root:open()
end

function M:force_refresh_node(node)
	if not node then
		return
	end
	if not node:is_dir() then
		node = node.parent
	end
	self:refresh(node, {}, function()
		local dir_state = node:dump_state()
		node:load(true)
		node:load_state(dir_state)
	end)
end

function M:force_refresh_tree()
	self:force_refresh_node(self.root)
end

function M:refresh(node, opts, action)
	node = node or self.root
	local index = self.root:find_node(node)
	if not index then
		return
	end
	local changes = self:draw_node(node, opts, action)
	self:post_changes(changes, index)
end

function M:iter(loaded)
	if not self.root then
		return function() end
	end
	return self.root:iter(loaded)
end

function M:draw_node(node, opts, action)
	opts = opts or {}
	node = node or self.root
	if not node then
		return
	end

	local total_lines = node:total_lines()

	if action then
		action(node)
	end

	local lines, highlights = node:draw(vim.tbl_deep_extend("force", self.draw_opts, opts))
	if not lines then
		return
	end

	return {
		texts = {
			{
				line_start = 0,
				line_end = opts.non_recursive and #lines or total_lines,
				lines = lines,
			},
		},
		highlights = highlights,
	}
end

function M:draw()
	if self.dir_state then
		self.root:load_state(self.dir_state)
	end
	return self:draw_node(self.root)
end

-- straightforward but slow
function M:find_neighbor(node, n)
	if not node.parent then
		return
	end
	for neighbor, index in self:iter() do
		if self.root:get_node_by_index(index - n) == node then
			return neighbor
		end
	end
end

function M:total_lines()
	return self.root:total_lines()
end

function M:on_open(cwd)
	if not self.cwd or cwd then
		self:set_cwd(cwd)
	end
end

function M:on_exit()
	self.dir_state = self.root:dump_state()
end

function M:on_key(linenr, key)
	local node = self.root:get_node_by_index(linenr)
	if not node then
		return
	end

	local action = self.keymaps[key]
	if not action then
		return
	end

	return action(self, node, key, linenr)
end

-- key handlers
function M:open_file_node(node, cmd)
	cmd = cmd or "e"
	if node:is_dir() then
		return
	end

	api.nvim_command("wincmd p")
	api.nvim_command(cmd .. " " .. node.abs_path)
end

function M:gen_open_file_node(cmd)
	return function(_, node)
		return self:open_file_node(node, cmd)
	end
end

function M:open_node(node)
	if not node:is_dir() then
		return self:open_file_node(node)
	end

	local total_lines = node:total_lines()

	node:toggle()

	local lines, highlights = node:draw(self.draw_opts)
	return {
		texts = {
			line_start = 0,
			line_end = total_lines,
			lines = lines,
		},
		highlights = highlights,
	}
end

function M:close_node(node)
	node = node:is_dir() and node or node.parent
	node = node.is_open and node or node.parent

	self:refresh(node, {}, function()
		node:close()
	end)

	self:go_to_node(node)
end

function M:cd_to_node(node)
	if not node:is_dir() then
		return
	end

	self:cd_to_path(node.abs_path)
end

function M:cd_to_parent()
	if self.cwd == utils.path_sep then
		return
	end -- TODO: check root path for windows
	local old_cwd = self.cwd
	local parent = vim.fn.fnamemodify(self.cwd, ":h:h")
	self:cd_to_path(parent)

	for node, index in self:iter() do
		if node.abs_path == old_cwd then
			self:post_changes({
				cursor = {
					line = index,
				},
			})
			return
		end
	end
end

function M:cd_to_path(path)
	local total_lines = self:total_lines()
	self:set_cwd(path)
	local lines, highlights = self.root:draw(self.draw_opts)
	local texts = { {
		line_start = 0,
		line_end = total_lines,
		lines = lines,
	} }
	self:post_changes({
		texts = texts,
		highlights = highlights,
	})
end

function M:go_to_node(node)
	local closed_parents = {}
	local parent = node.parent
	while parent do
		if not parent.is_open then
			table.insert(closed_parents, parent)
		end
		parent = parent.parent
	end
	if #closed_parents > 0 then
		self:refresh(closed_parents[#closed_parents], nil, function()
			for _, n in ipairs(closed_parents) do
				n:open()
			end
		end)
	end
	local index = self.root:find_node(node)
	if not index then
		return
	end
	self:post_changes({
		cursor = {
			line = index,
		},
	})
end

function M:go_to_last_child(node)
	if not node.parent then
		return
	end

	local parent = node.parent
	local last_child = parent:get_last_entry()
	if node == last_child then
		return
	end

	return self:go_to_node(last_child)
end

function M:go_to_first_child(node)
	if not node.parent then
		return
	end

	local parent = node.parent
	local first_child = parent.entries[1]
	if node == first_child then
		return
	end

	return self:go_to_node(first_child)
end

---Generate go_to_sibling function
---@param n number
function M:gen_go_to_sibling(n)
	return function(_, node)
		return self:go_to_sibling(node, n)
	end
end

function M:go_to_sibling(node, n)
	local sibling = node:find_sibling(n)
	if not sibling then
		return
	end

	return self:go_to_node(sibling)
end

function M:create_node(node)
	node = node:is_dir() and node or node.parent
	node = node.is_open and node or node.parent

	vim.ui.input({ prompt = "Name" }, function(input)
		if not input or input == "" then
			return
		end

		local path = node.abs_path .. input
		if self.root:find_node_by_path(path) then
			vim.notify(path .. "already exists", "WARN")
			return
		end

		local dir = vim.fn.fnamemodify(path, ":h")
		local _, code = Job:new({ command = "mkdir", args = { "-p", dir } }):sync()
		if code ~= 0 then
			vim.notify("mkdir -p " .. dir .. " failed", "ERROR")
			return
		end

		if vim.endswith(path, "/") then
			local _, code = Job:new({ command = "mkdir", args = { "-p", path } }):sync()
			if code ~= 0 then
				vim.notify("mkdir -p " .. path .. " failed", "ERROR")
				return
			end
		else
			local _, code = Job:new({ command = "touch", args = { path } }):sync()
			if code ~= 0 then
				vim.notify("touch " .. path .. " failed", "ERROR")
				return
			end
		end

		self:force_refresh_node(node)
		git.update(self.cwd)

		local new_node = self.root:find_node_by_path(path)
		if not new_node then
			vim.notify("create_node failed", "WARN")
			return
		end

		self:go_to_node(new_node)
	end)
end

function M:delete_node(node)
	vim.ui.select({ "no", "yes" }, { prompt = "Are you sure?" }, function(input)
		if input ~= "yes" then
			return
		end

		if node:is_dir() then
			local _, code = Job:new({ command = "rm", args = { "-r", node.abs_path } }):sync()
			if code ~= 0 then
				vim.notify("rm -r " .. node.abs_path(" failed"), "ERROR")
				return
			end
		else
			local _, code = Job:new({ command = "rm", args = { node.abs_path } }):sync()
			if code ~= 0 then
				vim.notify("rm " .. node.abs_path(" failed"), "ERROR")
				return
			end
		end

		self:force_refresh_node(node.parent)
		git.update(self.cwd)
	end)
end

function M:rename_node(node)
	vim.ui.input({ prompt = "New name" }, function(input)
		if not input or input == "" then
			return
		end

		local _, code = Job:new({ command = "mv", args = { node.abs_path, node.parent.abs_path .. input } }):sync()
		if code ~= 0 then
			vim.notify("mv " .. node.abs_path .. " " .. node.parent.abs_path .. input .. " failed", "ERROR")
			return
		end

		self:force_refresh_node(node)
		git.update(self.cwd)
	end)
end

return M
