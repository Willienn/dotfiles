
hl.window_rule({
  name = "suppress-maximize-events",
  match = { class = "kitty" },
  suppress_event = "maximize",
})

-- Janela do jogo rodando pelo editor do Godot: flutua em vez de dividir a tela
hl.window_rule({
  name = "godot-debug",
  match = { title = ".*\\(DEBUG\\).*" },
  float = true,
})

-- Lista de amigos e janelinhas da Steam flutuando
hl.window_rule({
  name = "steam-friends",
  match = { class = "^steam$", title = "^Friends List$" },
  float = true,
})

-- Jogos da Steam sem escurecer quando perdem o foco (útil no segundo monitor)
hl.window_rule({
  name = "games-no-dim",
  match = { class = "^steam_app_\\d+$" },
  no_dim = true,
})

hl.workspace_rule({ workspace = "1", monitor = "DP-2", default = true })
hl.workspace_rule({ workspace = "10", monitor = "HDMI-A-1", default = true })

hl.window_rule({
  name = "vesktop-segundo-monitor",
  match = { class = "^vesktop$" },
  workspace = "10 silent",
})