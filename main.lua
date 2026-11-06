local config = {}

-- Направления (замени на свои, если не работает)
config.side_export = "UP"   -- От МЭ к PIM
config.side_push = "DOWN"   -- От PIM к МЭ

-- Цветовая палитра
config.colors = {
    bg = 0x1A1A1A,       -- Темный фон
    fg = 0xE0E0E0,       -- Светлый текст
    border = 0x0055AA,   -- Синяя рамка
    title = 0x00AAFF,    -- Голубой заголовок
    btn = 0x333333,      -- Кнопка
    hover = 0x00AA00,    -- Кнопка при нажатии
    white = 0xFFFFFF,
    ok = 0x00AA00,       -- Зеленый статус
    err = 0xFF5555,      -- Красный статус
    modal = 0x2A2A2A     -- Фон окна
}

return config
