---@class TablineState
---@field buffers integer[]
---@field visible integer[]
---@field cache table
---@field config TablineConfig
---@field update_pending boolean

---@class TablineConfig
---@field separator string
---@field close string
---@field modified string
---@field hide_misc boolean
---@field min_visible integer
---@field max_visible integer
---@field style table

---@class TablineModule
local M = {}
local api = vim.api

-- Minimal state management
local state = {
	buffers = {},
	visible = {},
	cache = {
		highlights = {},
		icons = {},
		tabline = "",
	},
	config = {
		separator = "│", -- Modern vertical separator
		close = "×", -- Cleaner close symbol
		modified = "●", -- Filled circle for modified
		hide_misc = true,
		min_visible = 3, -- Minimum number of buffers to show
		max_visible = 10, -- Maximum number of buffers to show (0 = no limit)
		style = {
			active_bg_blend = 0.12, -- Subtle highlight for active
			inactive_fg_blend = 0.5, -- Dimmed inactive text
			separator_opacity = 0.3, -- Subtle separators
			padding = "  ", -- Consistent spacing
			corner_radius = true, -- Visual corner effect
		},
	},
	update_pending = false,
}

-- Icon providers (webdevicons or mini.icons)
local icon_provider
local has_webdevicons, webdevicons = pcall(require, "nvim-web-devicons")
local has_miniicons, miniicons = pcall(require, "mini.icons")

if has_webdevicons then
	icon_provider = webdevicons
elseif has_miniicons then
	icon_provider = miniicons
end

--------------------------------------------------------------------------------
-- Color Utilities
--------------------------------------------------------------------------------

---Convert hex color to RGB components
---@param hex string|nil Hex color string
---@return number, number, number RGB components
local function hex_to_rgb(hex)
	if not hex or type(hex) ~= "string" then
		return 192, 202, 245 -- Fallback RGB
	end

	hex = hex:gsub("#", "")

	-- Validate hex format
	if not hex:match("^%x%x%x%x%x%x$") then
		return 192, 202, 245 -- Fallback RGB
	end

	return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

---Convert RGB components to hex color
---@param r number Red component
---@param g number Green component
---@param b number Blue component
---@return string Hex color string
local function rgb_to_hex(r, g, b)
	return string.format("#%02x%02x%02x", math.floor(r), math.floor(g), math.floor(b))
end

---Blend two colors with alpha
---@param fg_hex string Foreground hex color
---@param bg_hex string Background hex color
---@param alpha number Alpha value (0-1)
---@return string Blended hex color
local function blend_colors(fg_hex, bg_hex, alpha)
	local fr, fg, fb = hex_to_rgb(fg_hex)
	local br, bg, bb = hex_to_rgb(bg_hex)

	local r = fr * alpha + br * (1 - alpha)
	local g = fg * alpha + bg * (1 - alpha)
	local b = fb * alpha + bb * (1 - alpha)

	return rgb_to_hex(r, g, b)
end

---Get highlight colors
---@param name string Highlight group name
---@return string, string Foreground and background hex colors
local function get_hl(name)
	local ok, hl = pcall(api.nvim_get_hl, 0, { name = name })
	if ok and hl and hl.fg and hl.bg then
		local fg = string.format("#%06x", hl.fg)
		local bg = string.format("#%06x", hl.bg)
		return fg, bg
	end
	return "#c0caf5", "#1a1b26" -- Fallback colors
end

---Create or reuse highlight group
---@param name string Highlight group name
---@param fg string|nil Foreground color
---@param bg string|nil Background color
---@param opts table|nil Additional highlight options
---@return string Highlight group name
local function create_hl(name, fg, bg, opts)
	if state.cache.highlights[name] then
		return name
	end

	opts = opts or {}
	local ok = pcall(api.nvim_set_hl, 0, name, vim.tbl_extend("force", { fg = fg, bg = bg }, opts))
	if ok then
		state.cache.highlights[name] = true
	end
	return name
end

--------------------------------------------------------------------------------
-- Buffer Management
--------------------------------------------------------------------------------

---Check if buffer is valid and should be shown
---@param bufnr integer Buffer number
---@return boolean
local function is_valid_buffer(bufnr)
	-- Protect the validity check itself
	local ok, is_valid = pcall(api.nvim_buf_is_valid, bufnr)
	if not ok or not is_valid then
		return false
	end

	-- Protect buffer option access
	local ok_listed, is_listed = pcall(function()
		return vim.bo[bufnr].buflisted
	end)
	if not ok_listed or not is_listed then
		return false
	end

	if state.config.hide_misc then
		local ok_name, name = pcall(api.nvim_buf_get_name, bufnr)
		if not ok_name or not name then
			return false
		end
		return name ~= "" and vim.fn.isdirectory(name) == 0
	end

	return true
end

---Get list of valid buffers
---@return integer[]
local function get_buffers()
	local bufs = {}
	local ok, all_bufs = pcall(api.nvim_list_bufs)
	if not ok then
		return bufs
	end

	for _, bufnr in ipairs(all_bufs) do
		if is_valid_buffer(bufnr) then
			table.insert(bufs, bufnr)
		end
	end
	return bufs
end

---Get display name for buffer
---@param bufnr integer Buffer number
---@return string
local function get_buffer_name(bufnr)
	local ok, path = pcall(api.nvim_buf_get_name, bufnr)
	if not ok or not path then
		return "[No Name]"
	end

	local name = vim.fn.fnamemodify(path, ":t")

	if name == "" then
		return "[No Name]"
	end

	-- Check for duplicates and add parent directory
	local count = 0
	for _, b in ipairs(state.buffers) do
		local ok_name, other_path = pcall(api.nvim_buf_get_name, b)
		if ok_name and vim.fn.fnamemodify(other_path, ":t") == name then
			count = count + 1
		end
	end

	if count > 1 then
		local parent = vim.fn.fnamemodify(path, ":h:t")
		return parent .. "/" .. name
	end

	return name
end

---Get icon for buffer
---@param bufnr integer Buffer number
---@return string, string Icon and highlight group
local function get_icon(bufnr)
	local ok, path = pcall(api.nvim_buf_get_name, bufnr)
	if not ok or not path then
		return "", "Normal"
	end

	local name = vim.fn.fnamemodify(path, ":t")
	local ext = vim.fn.fnamemodify(path, ":e")

	local ok_ft, ft = pcall(function()
		return vim.bo[bufnr].filetype
	end)
	ft = ok_ft and ft or ""

	local key = ft ~= "" and ft or ext
	if state.cache.icons[key] then
		return state.cache.icons[key].icon, state.cache.icons[key].hl
	end

	local icon, hl = "", "Normal"

	if icon_provider == webdevicons then
		local ok_icon, icon_result, hl_result = pcall(webdevicons.get_icon, name, ext, { default = true })
		if ok_icon then
			icon, hl = icon_result, hl_result
		end
	elseif icon_provider == miniicons then
		if ft ~= "" then
			local ok_icon, icon_result, hl_result = pcall(miniicons.get, "filetype", ft)
			if ok_icon then
				icon, hl = icon_result, hl_result
			end
		else
			local ok_icon, icon_result, hl_result = pcall(miniicons.get, "file", name)
			if ok_icon then
				icon, hl = icon_result, hl_result
			end
		end
	end

	state.cache.icons[key] = { icon = icon or "", hl = hl or "Normal" }
	return icon or "", hl or "Normal"
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

---Get highlight group for buffer
---@param bufnr integer Buffer number
---@return string Highlight group name
local function get_buffer_highlights(bufnr)
	local ok, current = pcall(api.nvim_get_current_buf)
	if not ok then
		return "Normal"
	end

	local is_active = bufnr == current
	local base_fg, base_bg = get_hl("Normal")

	if is_active then
		-- Active: subtle elevated background
		local bg = blend_colors("#ffffff", base_bg, state.config.style.active_bg_blend)
		return create_hl("TabLineActive", base_fg, bg, { bold = false })
	else
		-- Inactive: dimmed text, same background
		local fg = blend_colors(base_fg, base_bg, state.config.style.inactive_fg_blend)
		return create_hl("TabLineInactive", fg, base_bg)
	end
end

---Get separator highlight group
---@return string Highlight group name
local function get_separator_hl()
	local base_fg, base_bg = get_hl("Normal")
	local sep_fg = blend_colors(base_fg, base_bg, state.config.style.separator_opacity)
	return create_hl("TabLineSeparator", sep_fg, base_bg)
end

---Render a single buffer
---@param bufnr integer Buffer number
---@return string Rendered buffer string
local function render_buffer(bufnr)
	local ok, current = pcall(api.nvim_get_current_buf)
	if not ok then
		return ""
	end

	local is_active = bufnr == current

	local ok_mod, is_modified = pcall(function()
		return vim.bo[bufnr].modified
	end)
	is_modified = ok_mod and is_modified or false

	local name = get_buffer_name(bufnr)
	local icon, icon_hl = get_icon(bufnr)
	local buf_hl = get_buffer_highlights(bufnr)
	local sep_hl = get_separator_hl()

	-- Icon highlight matching buffer state
	local icon_fg, _ = get_hl(icon_hl)
	local _, buf_bg = get_hl(buf_hl)

	-- Blend icon color with buffer background for consistency
	if not is_active then
		icon_fg = blend_colors(icon_fg, buf_bg, 0.7)
	end

	local state_icon_hl = create_hl("TabLineIcon" .. (is_active and "Active" or "Inactive") .. bufnr, icon_fg, buf_bg)

	-- Build buffer string with modern spacing
	local parts = {
		string.format("%%%d@v:lua.require'tabline.components'.click@", bufnr),
		string.format("%%#%s#", buf_hl),
		state.config.style.padding,
		string.format("%%#%s#", state_icon_hl),
		icon ~= "" and (icon .. " ") or "",
		string.format("%%#%s#", buf_hl),
		name,
	}

	-- Modern modified/close indicator
	if is_modified then
		parts[#parts + 1] = " "
		parts[#parts + 1] = state.config.modified
	else
		parts[#parts + 1] =
			string.format(" %%%d@v:lua.require'tabline.components'.close@%s%%X", bufnr, state.config.close)
	end

	parts[#parts + 1] = state.config.style.padding

	-- Add separator between buffers
	parts[#parts + 1] = string.format("%%#%s#", sep_hl)
	parts[#parts + 1] = state.config.separator
	parts[#parts + 1] = "%*"

	return table.concat(parts)
end

---Calculate which buffers should be visible
---@return integer[]
local function calculate_visible_buffers()
	local ok, current = pcall(api.nvim_get_current_buf)
	if not ok then
		return {}
	end

	local columns = vim.o.columns
	local available = math.max(columns - 20, 50) -- Ensure minimum width

	-- Find current buffer index
	local current_idx
	for i, bufnr in ipairs(state.buffers) do
		if bufnr == current then
			current_idx = i
			break
		end
	end

	if not current_idx then
		-- Current buffer not in list, force rebuild
		state.buffers = get_buffers()
		return state.buffers[1] and { state.buffers[1] } or {}
	end

	-- If we have fewer buffers than min_visible, show all
	if #state.buffers <= state.config.min_visible then
		return state.buffers
	end

	local visible = { current }
	local used = #render_buffer(current)
	local count = 1

	local left_idx = current_idx - 1
	local right_idx = current_idx + 1

	-- Calculate max buffers we can show
	local max_count = state.config.max_visible > 0 and state.config.max_visible or math.huge

	-- Ensure we meet minimum visible requirement
	local target_min = math.max(state.config.min_visible, 1)

	-- Expand from center, alternating left and right
	while count < max_count and (state.buffers[left_idx] or state.buffers[right_idx]) do
		local added = false

		-- Try to add left buffer
		if state.buffers[left_idx] then
			local len = #render_buffer(state.buffers[left_idx])
			if used + len <= available or count < target_min then
				table.insert(visible, 1, state.buffers[left_idx])
				used = used + len
				count = count + 1
				left_idx = left_idx - 1
				added = true
			else
				left_idx = nil -- Stop trying left
			end
		end

		-- Try to add right buffer
		if count < max_count and state.buffers[right_idx] then
			local len = #render_buffer(state.buffers[right_idx])
			if used + len <= available or count < target_min then
				table.insert(visible, state.buffers[right_idx])
				used = used + len
				count = count + 1
				right_idx = right_idx + 1
				added = true
			else
				right_idx = nil -- Stop trying right
			end
		end

		-- If we couldn't add anything and met minimum, stop
		if not added and count >= target_min then
			break
		end

		-- If both directions exhausted, stop
		if not state.buffers[left_idx] and not state.buffers[right_idx] then
			break
		end
	end

	return visible
end

---Build the complete tabline string
local function build_tabline()
	state.buffers = get_buffers()
	state.visible = calculate_visible_buffers()

	local parts = {}
	local base_fg, base_bg = get_hl("Normal")
	local overflow_fg = blend_colors(base_fg, base_bg, 0.4)
	local overflow_hl = create_hl("TabLineOverflow", overflow_fg, base_bg)

	-- Left overflow (minimal)
	if state.visible[1] ~= state.buffers[1] then
		parts[#parts + 1] = string.format("%%#%s#", overflow_hl)
		parts[#parts + 1] = "   ‹  "
	else
		parts[#parts + 1] = string.format("%%#%s#", overflow_hl)
		parts[#parts + 1] = "  "
	end

	-- Render visible buffers
	for _, bufnr in ipairs(state.visible) do
		parts[#parts + 1] = render_buffer(bufnr)
	end

	-- Right overflow (minimal)
	if state.visible[#state.visible] ~= state.buffers[#state.buffers] then
		parts[#parts + 1] = string.format("%%#%s#", overflow_hl)
		parts[#parts + 1] = "  ›   "
	end

	-- Fill rest with normal background
	parts[#parts + 1] = string.format("%%#%s#", create_hl("TabLineFill", base_fg, base_bg))
	parts[#parts + 1] = "%="

	state.cache.tabline = table.concat(parts)
end

-- Debounced update
local function schedule_update()
	if state.update_pending then
		return
	end

	state.update_pending = true
	vim.schedule(function()
		state.update_pending = false

		-- Protect against errors during update
		local ok_update, err = pcall(function()
			build_tabline()
			vim.cmd.redrawtabline()
		end)

		if not ok_update then
			vim.notify("Tabline update failed: " .. tostring(err), vim.log.levels.WARN)
		end
	end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---Get the current tabline string
---@return string
function M.get_tabline()
	return state.cache.tabline
end

---Trigger a tabline update
function M.update()
	schedule_update()
end

---Handle buffer click
---@param bufnr integer Buffer number
function M.click(bufnr)
	if is_valid_buffer(bufnr) then
		local ok_click = pcall(vim.cmd, "buffer " .. bufnr)
		if not ok_click then
			vim.notify("Failed to switch to buffer " .. bufnr, vim.log.levels.WARN)
		end
	end
end

---Close a buffer
---@param bufnr integer Buffer number
function M.close(bufnr)
	-- Double-check validity with protection
	local ok_valid = pcall(api.nvim_buf_is_valid, bufnr)
	if not ok_valid or not api.nvim_buf_is_valid(bufnr) then
		vim.notify("Invalid buffer", vim.log.levels.WARN)
		return
	end

	-- Protect modified check
	local ok_mod, is_modified = pcall(function()
		return vim.bo[bufnr].modified
	end)

	if not ok_mod then
		return -- Buffer was deleted
	end

	if is_modified then
		local choice = vim.fn.confirm("Buffer modified. Save?", "&Yes\n&No\n&Cancel", 3)
		if choice == 1 then
			local ok_write = pcall(vim.cmd, "silent! write")
			if not ok_write then
				vim.notify("Failed to save buffer", vim.log.levels.ERROR)
				return
			end
		elseif choice == 3 then
			return
		end
	end

	vim.schedule(function()
		-- Double-check again inside schedule
		local still_valid = pcall(api.nvim_buf_is_valid, bufnr)
		if not still_valid or not api.nvim_buf_is_valid(bufnr) then
			return
		end

		pcall(vim.lsp.inlay_hint.enable, false, { bufnr = bufnr })
		local ok_delete = pcall(api.nvim_buf_delete, bufnr, { force = false })

		if not ok_delete then
			vim.notify("Failed to delete buffer " .. bufnr, vim.log.levels.ERROR)
		end
	end)
end

---Navigate to next buffer
function M.next()
	local ok_current, current = pcall(api.nvim_get_current_buf)
	if not ok_current then
		return
	end

	for i, bufnr in ipairs(state.buffers) do
		if bufnr == current then
			local next_buf = state.buffers[i + 1] or state.buffers[1]
			local ok_switch = pcall(vim.cmd, "buffer " .. next_buf)
			if not ok_switch then
				vim.notify("Failed to switch to next buffer", vim.log.levels.WARN)
			end
			return
		end
	end
end

---Navigate to previous buffer
function M.prev()
	local ok_current, current = pcall(api.nvim_get_current_buf)
	if not ok_current then
		return
	end

	for i, bufnr in ipairs(state.buffers) do
		if bufnr == current then
			local prev_buf = state.buffers[i - 1] or state.buffers[#state.buffers]
			local ok_switch = pcall(vim.cmd, "buffer " .. prev_buf)
			if not ok_switch then
				vim.notify("Failed to switch to previous buffer", vim.log.levels.WARN)
			end
			return
		end
	end
end

---Setup the tabline plugin
---@param opts? TablineConfig Configuration options
M.set = function(opts)
	opts = opts or {}

	if not opts.enabled then
		vim.o.tabline = ""
		return
	end

	-- Validate configuration
	local ok_validate, err = pcall(vim.validate, {
		separator = { opts.separator, "string", true },
		close = { opts.close, "string", true },
		modified = { opts.modified, "string", true },
		hide_misc = { opts.hide_misc, "boolean", true },
		min_visible = { opts.min_visible, "number", true },
		max_visible = { opts.max_visible, "number", true },
	})

	if not ok_validate then
		vim.notify("Invalid tabline configuration: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	-- Additional validation
	if opts.min_visible and opts.min_visible < 1 then
		vim.notify("min_visible must be >= 1, using default", vim.log.levels.WARN)
		opts.min_visible = 3
	end

	if opts.max_visible and opts.max_visible < 0 then
		vim.notify("max_visible must be >= 0, using default", vim.log.levels.WARN)
		opts.max_visible = 10
	end

	-- Merge config
	state.config = vim.tbl_deep_extend("force", state.config, opts)

	-- Clear caches on colorscheme change
	api.nvim_create_autocmd("ColorScheme", {
		callback = function()
			state.cache.highlights = {}
			state.cache.icons = {} -- Clear icons too, as colors may change
			schedule_update()
		end,
	})

	-- Setup autocmds
	local group = api.nvim_create_augroup("ModernTabline", { clear = true })

	api.nvim_create_autocmd({ "BufEnter", "BufDelete", "BufWipeout" }, {
		group = group,
		callback = function(args)
			local ok_listed, is_listed = pcall(function()
				return vim.bo[args.buf].buflisted
			end)
			if ok_listed and is_listed then
				schedule_update()
			end
		end,
	})

	api.nvim_create_autocmd("BufModifiedSet", {
		group = group,
		callback = schedule_update,
	})

	api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = schedule_update,
	})

	-- Set tabline
	vim.o.tabline = [[%!v:lua.require'tabline.components'.get_tabline()]]

	-- Keymaps
	vim.keymap.set("n", "<Tab>", M.next, { desc = "Next buffer", silent = true })
	vim.keymap.set("n", "<S-Tab>", M.prev, { desc = "Previous buffer", silent = true })
	vim.keymap.set("n", "<A-c>", function()
		local ok_current, current = pcall(api.nvim_get_current_buf)
		if ok_current then
			M.close(current)
		end
	end, { desc = "Close buffer", silent = true })

	-- Initial render
	schedule_update()
end

return M
