local M = {}

function M.setup(opts)
	opts = opts or {}

	if not opts.enabled then
		vim.o.tabline = ""
		vim.g.ui_modern_tabline_enabled = false
		return
	end

	local ok, components = pcall(require, "tabline.components")
	if not ok then
		vim.notify("tabline: Failed to load components: " .. tostring(components), vim.log.levels.ERROR)
		vim.g.ui_modern_tabline_enabled = false
		return
	end

	components.set(opts)
	vim.g.ui_modern_tabline_enabled = true
end

-- Optional: expose components for advanced use
M.components = function()
	return require("tabline.components")
end

return M
