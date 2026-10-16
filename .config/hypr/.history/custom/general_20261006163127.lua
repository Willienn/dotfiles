-- Monitores
hl.monitor({
  output = "DP-2",
  mode = "1920x1080@144",
  position = "0x0",
  scale = 1,
  vrr = 1,
  icc = "/home/skaaarlate/.config/hypr/ICC/ultragear.icm"
})
hl.monitor({
  output = "HDMI-A-1",
  mode = "1920x1080@60",
  position = "1920x0",
  scale = 1,
})

hl.config({
        decoration = {
        blur = {
            
            passes = 2,
        },
    },
    cursor = { inactive_timeout = 5 },
    render = {
        direct_scanout = 2,        -- menos latência em jogo fullscreen
    },
    misc = {
        focus_on_activate = false, -- o padrão do end-4 é true: apps roubam foco
    },
    binds = {
        workspace_back_and_forth = true,
    },
})

-- Teclado
hl.config({
 input = {
        kb_layout  = "us",
        kb_variant = "intl",
    },
})