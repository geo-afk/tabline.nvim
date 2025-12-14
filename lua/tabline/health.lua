local M = {}

---Perform health checks
M.check = function()
	vim.health.start("Tabline Configuration")

	-- Check if tabline is enabled
	if vim.g.ui_tabline_enabled then
		vim.health.ok("Tabline is enabled")
	else
		vim.health.warn("Tabline is not enabled", {
			'Call require("tabline").setup({enabled = true}) in your config',
		})
		return -- No point checking further if disabled
	end

	-- Check for icon providers
	vim.health.start("Icon Providers")
	local has_icons = false

	local ok_webdevicons, webdevicons = pcall(require, "nvim-web-devicons")
	if ok_webdevicons then
		vim.health.ok("nvim-web-devicons is installed")
		has_icons = true

		-- Check if setup was called
		if webdevicons.has_loaded and webdevicons.has_loaded() then
			vim.health.ok("nvim-web-devicons is properly loaded")
		else
			vim.health.warn("nvim-web-devicons might not be properly setup")
		end
	end

	local ok_miniicons, miniicons = pcall(require, "mini.icons")
	if ok_miniicons then
		vim.health.ok("mini.icons is installed")
		has_icons = true
	end

	if not has_icons then
		vim.health.warn("No icon provider found", {
			"Install nvim-web-devicons or mini.icons for file icons",
			"Icons will not be displayed without a provider",
		})
	end

	-- Check buffer status
	vim.health.start("Buffer Status")
	local ok_buffers, buffers = pcall(vim.api.nvim_list_bufs)
	if not ok_buffers then
		vim.health.error("Failed to list buffers")
		return
	end

	local listed = 0
	local valid = 0
	for _, buf in ipairs(buffers) do
		local ok_valid = pcall(vim.api.nvim_buf_is_valid, buf)
		if ok_valid and vim.api.nvim_buf_is_valid(buf) then
			valid = valid + 1
			local ok_listed = pcall(function()
				return vim.bo[buf].buflisted
			end)
			if ok_listed and vim.bo[buf].buflisted then
				listed = listed + 1
			end
		end
	end

	vim.health.info(string.format("Total valid buffers: %d", valid))
	vim.health.info(string.format("Listed buffers: %d", listed))

	if listed == 0 then
		vim.health.warn("No listed buffers found", {
			"This is normal if you just started Neovim",
			"Open some files to see the tabline in action",
		})
	else
		vim.health.ok(string.format("Found %d listed buffer(s)", listed))
	end

	-- Check tabline option
	vim.health.start("Neovim Configuration")
	if vim.o.tabline ~= "" then
		vim.health.ok("tabline option is set")
		if vim.o.tabline:match("require'tabline%.components'") then
			vim.health.ok("tabline is pointing to custom tabline module")
		else
			vim.health.warn("tabline is set but not pointing to custom module", {
				"Expected: %!v:lua.require'tabline.components'.get_tabline()",
				"Current: " .. vim.o.tabline,
			})
		end
	else
		vim.health.error("tabline option is empty", {
			"The tabline should be set if enabled",
			"Try reloading your config or calling setup again",
		})
	end

	-- Check for common issues
	vim.health.start("Common Issues")

	-- Check if showtabline is set appropriately
	if vim.o.showtabline == 0 then
		vim.health.warn("showtabline is set to 0 (never show)", {
			"The tabline will never be displayed",
			"Set to 1 (show if multiple tabs) or 2 (always show)",
			"Add to your config: vim.o.showtabline = 2",
		})
	else
		vim.health.ok(string.format("showtabline is set to %d", vim.o.showtabline))
	end

	-- Check terminal colors
	if vim.o.termguicolors then
		vim.health.ok("termguicolors is enabled (recommended for modern terminals)")
	else
		vim.health.info(
			"termguicolors is disabled, Colors might not display correctly, Enable with: vim.o.termguicolors = true"
		)
	end

	-- Performance check
	vim.health.start("Performance")
	local ok_columns = pcall(function()
		return vim.o.columns
	end)
	if ok_columns then
		local columns = vim.o.columns
		vim.health.info(string.format("Terminal width: %d columns", columns))

		if columns < 80 then
			vim.health.warn("Terminal width is narrow", {
				"Some buffer names might be truncated",
				"Consider using a wider terminal for better display",
			})
		end
	end

	-- Check for potential conflicts
	vim.health.start("Plugin Conflicts")
	local potential_conflicts = {
		"bufferline",
		"barbar",
		"tabline",
		"buftabline",
	}

	local conflicts_found = false
	for _, plugin in ipairs(potential_conflicts) do
		local ok = pcall(require, plugin)
		if ok then
			vim.health.warn(string.format('Detected "%s" plugin', plugin), {
				"This might conflict with custom tabline",
				"Consider disabling one of them",
			})
			conflicts_found = true
		end
	end

	if not conflicts_found then
		vim.health.ok("No conflicting tabline plugins detected")
	end
end

return M
