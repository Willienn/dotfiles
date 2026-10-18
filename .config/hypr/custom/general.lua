-- Monitores
hl.monitor({
	output = "DP-2",
	mode = "1920x1080@144",
	position = "0x0",
	scale = 1,
	icc = "/home/skaaarlate/.config/hypr/ICC/ultragear.icm",
})
hl.monitor({
	output = "HDMI-A-1",
	mode = "1920x1080@60",
	position = "1920x0",
	scale = 1,
})

hl.config({
	general = {
		-- Gaps and border
		gaps_in = 0,
		gaps_out = 2,
		gaps_workspaces = 50,
		col = {
			active_border = "rgba(ef934dff)",
			inactive_border = "rgba(3b403cff)",
			nogroup_border_active = "rgba(f4b585ff)",
			nogroup_border = "rgba(3b403cff)",
		},
	},
	group = {
		col = {
			border_active = "rgba(ef934dff)",
			border_inactive = "rgba(3b403cff)",
			border_locked_active = "rgba(f16e65ff)",
			border_locked_inactive = "rgba(3b403cff)",
		},
		groupbar = {
			enabled = true,
			render_titles = false,
			gradients = false,
			indicator_height = 2,
			font_size = 12,
			text_color = "rgba(f4decdff)",
			col = {
				active = "rgba(ef934dff)",
				inactive = "rgba(1e1f1eff)",
				locked_active = "rgba(f16e65ff)",
				locked_inactive = "rgba(1e1f1eff)",
			},
		},
	},
	decoration = {
		-- 2 = circle, higher = squircle, 4 = very obvious squircle
		rounding = 0,

		blur = {
			enabled = false, -- ← opaco como o Firefox (layers da bar continuam com blur via rules.lua)
		},
		shadow = {
			enabled = false, -- ← sem sombra, igual o tema flat
		},
		dim_inactive = true, -- (equivalente ao --tabs-discarded-title-opacity: 0.75)
		dim_strength = 0.05,
		dim_special = 0.2,
	},
	cursor = { inactive_timeout = 3 },
	render = {
		direct_scanout = 2, -- menos latência em jogo fullscreen
	},
	misc = {
		focus_on_activate = false, -- o padrão do end-4 é true: apps roubam foco
	},
})

-- Teclado
hl.config({
	input = {
		kb_layout = "us",
		kb_variant = "intl",
	},
})
