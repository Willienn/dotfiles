hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("[workspace special:special] kitty"),
    { description = "App: Terminal no scratchpad" })
--##! Groups
hl.bind("SUPER + SHIFT + G", hl.dsp.group.toggle(), { description = "Group: Toggle group" })
hl.bind("CTRL + SUPER + G", hl.dsp.group.lock_active({ action = "toggle" }), { description = "Group: Lock/unlock" })
hl.bind("SUPER + Tab", hl.dsp.group.next(), { description = "Group: Next window" })
hl.bind("SUPER + SHIFT + Tab", hl.dsp.group.prev(), { description = "Group: Previous window" })