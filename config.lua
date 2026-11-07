local config = {}

config.version = "v0.5.0"

-- Направления
config.side_export = "UP"   -- От МЭ к PIM
config.side_push = "DOWN"   -- От PIM к МЭ (pim.pushItem)
config.side_import = "DOWN" -- (не используется) ME забирает предметы с этой стороны

-- Цветовая палитра
config.colors = {
    bg = 0x1A1A1A, fg = 0xE0E0E0, border = 0x0055AA, title = 0x00AAFF,
    btn = 0x333333, hover = 0x00AA00, white = 0xFFFFFF,
    ok = 0x00AA00, err = 0xFF5555, modal = 0x2A2A2A,
    tab_active = 0x0055AA, tab_inactive = 0x222222,
    admin = 0xFFAA00, banned = 0xFF0000,
    muted = 0x888888, warning = 0xAA5500, danger = 0xAA0000,
    disabled = 0x555555, limit = 0x5555AA, overlay = 0x000000,
    techadmin = 0xFF00FF
}

-- Оповещения
config.alerts = {
    sound = true,         -- Включить звук (пищалку)
    redstone = true,      -- Включить сигнал редстоуна
    redstoneSide = "BACK" -- Сторона, куда подключена лампа/сирена (замени на свою)
}

return config
