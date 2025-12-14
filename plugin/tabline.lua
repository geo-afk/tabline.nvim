-- A modern, clean, and performant buffer tabline for Neovim
--
-- This file ensures that the plugin is properly loaded by older plugin managers
-- (like Packer without explicit `requires` or some manual runtimepath setups).
-- Modern managers like lazy.nvim don't strictly need this file, but including it
-- ensures maximum compatibility.

-- Prevent loading twice
if vim.g.loaded_modern_tabline then
	return
end
vim.g.loaded_modern_tabline = true

-- Optional: expose a global command for manual setup/reload
vim.api.nvim_create_user_command("ModernTablineSetup", function(opts)
	local args = opts.fargs or {}
	local config = {}

	for _, arg in ipairs(args) do
		local key, value = arg:match("([^=]+)=([^=]+)")
		if key and value then
			if value == "true" then
				value = true
			elseif value == "false" then
				value = false
			elseif tonumber(value) then
				value = tonumber(value)
			end
			config[key] = value
		end
	end

	config.enabled = true
	require("modern-tabline").setup(config)
end, {
	nargs = "*",
	desc = "Setup modern-tabline.nvim with optional key=value config",
})

-- Optional: expose toggle command
vim.api.nvim_create_user_command("ModernTablineToggle", function()
	if vim.g.ui_modern_tabline_enabled then
		require("modern-tabline").setup({ enabled = false })
		vim.notify("Modern Tabline disabled", vim.log.levels.INFO)
	else
		require("modern-tabline").setup({ enabled = true })
		vim.notify("Modern Tabline enabled", vim.log.levels.INFO)
	end
end, {
	desc = "Toggle modern-tabline.nvim on/off",
})

-- Auto-enable on VimEnter if user hasn't explicitly disabled it
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		-- Only auto-setup if not already configured and user hasn't disabled it
		if vim.g.ui_modern_tabline_enabled == nil then
			local ok = pcall(require, "modern-tabline")
			if ok then
				require("modern-tabline").setup({ enabled = true })
			end
		end
	end,
	once = true,
})
