local config = {}

config.version = "v1.12.6"

-- Уровни ролей (используются в проверках прав крафта). Не трогаем db.lua.
config.LEVEL_BANNED    = 0
config.LEVEL_GUEST     = 1
config.LEVEL_USER      = 2
config.LEVEL_MODERATOR = 3
config.LEVEL_ADMIN     = 4
config.LEVEL_TECHADMIN = 5

-- Смарт-загрузчик (boot.lua): автообновление при старте.
-- false — boot.lua сразу запускает main.lua без проверки GitHub.
config.boot = { autoUpdate = true }

-- Сбор статистики при загрузке: boot.lua вызывает `healthcheck.lua --append`
-- после успешной проверки версии. false — отключить.
config.healthcheckOnBoot = true

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
    techadmin = 0xFF00FF, row_alt = 0x2A2A2A,
    input = 0x111111       -- фон поля ввода (например, причина бана)
}

-- Оповещения
config.alerts = {
    sound = true,         -- Включить звук (пищалку)
    redstone = true,      -- Включить сигнал редстоуна
    redstoneSide = "BACK" -- Сторона, куда подключена лампа/сирена (замени на свою)
}

-- Хранилище МЭ (для вкладки «Статистика»)
config.storage = {
    -- Укажите общую ёмкость вашей МЭ-сети в байтах для точного отображения.
    -- Оставьте nil, чтобы использовать автоматическую оценку.
    totalBytes = nil
}

-- Автокрафт по лимитам (вкладка «Монитор»)
config.autoCraft = {
    enabled = true,   -- автоматически заказывать предмет при просадке ниже минимума
    interval = 10,    -- как часто проверять лимиты, сек
    cooldown = 60,    -- пауза между запросами на один и тот же предмет, сек
    maxStack = 64,    -- максимум за один запрос (1 стак)
}

-- Человекочитаемый размер: байты -> B / KB / MB / GB / TB
function config.formatSize(bytes)
    bytes = tonumber(bytes) or 0
    if bytes < 1024 then
        return string.format("%d B", bytes)
    end
    local units = { "KB", "MB", "GB", "TB" }
    local value = bytes
    local i = 0
    repeat
        value = value / 1024
        i = i + 1
    until value < 1024 or i >= #units
    return string.format("%.1f %s", value, units[i])
end

return config
