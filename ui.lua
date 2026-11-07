local component = require("component")
local unicode = require("unicode")
local computer = require("computer")
local config = require("config")
local api = require("me_api")
local db = require("db")
local gpu = component.gpu
local C = config.colors
local ui = {}
local formatSize = config.formatSize

function ui.drawFrame(x, y, w, h, color)
    -- Тень: только правая и нижняя кромки (не залезает внутрь рамки)
    local sw, sh = gpu.getResolution()
    if x + w <= sw and y + h <= sh and w > 2 and h > 2 then
        gpu.setForeground(0x000000)
        gpu.setBackground(0x000000)
        for i = 1, h - 1 do
            gpu.set(x + w, y + i, "║")
        end
        gpu.set(x + 1, y + h, "╚" .. string.rep("═", w - 2) .. "╝")
        gpu.setBackground(C.bg)
    end
    -- Основная рамка
    gpu.setForeground(color)
    gpu.set(x, y, "╔" .. string.rep("═", w - 2) .. "╗")
    for i = 1, h - 2 do 
        gpu.set(x, y + i, "║")
        gpu.set(x + w - 1, y + i, "║") 
    end
    gpu.set(x, y + h - 1, "╚" .. string.rep("═", w - 2) .. "╝")
    gpu.setForeground(C.fg)
end

function ui.drawButton(x, y, w, text, pressed, bg)
    gpu.setBackground(pressed and C.hover or bg or C.btn)
    gpu.fill(x, y, w, 1, " ")
    local t = "[ " .. text .. " ]"
    gpu.setForeground(C.white)
    gpu.set(x + math.floor((w - unicode.len(t)) / 2) + (pressed and 1 or 0), y, t)
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

function ui.getTabs(isAdmin)
    local tabs = {
        { id = "ME",    label = " МЭ-сеть " },
        { id = "INV",   label = " Инвентарь " },
        { id = "STATS", label = " Статистика " },
        { id = "CRAFT", label = " Крафт " },
        { id = "MON",   label = " Монитор " }
    }
    if isAdmin then
        table.insert(tabs, { id = "LOGS",  label = " Журнал " })
        table.insert(tabs, { id = "ADMIN", label = " Админ " })
    end
    return tabs
end

function ui.getTabLayout(W, isAdmin)
    local tabs = ui.getTabs(isAdmin)
    local totalW = 0
    for _, tab in ipairs(tabs) do totalW = totalW + unicode.len(tab.label) + 2 end
    totalW = totalW - 2
    local startX = math.floor((W - totalW) / 2) + 1
    
    local layout = {}
    local currentX = startX
    for _, tab in ipairs(tabs) do
        table.insert(layout, { id = tab.id, label = tab.label, x = currentX, w = unicode.len(tab.label) })
        currentX = currentX + unicode.len(tab.label) + 2
    end
    return layout
end

-- Раскладка нижней панели кнопок (общая для отрисовки и обработки кликов)
function ui.getBottomLayout(W)
    local L = {
        prev    = { x = 5,  w = 12 },
        refresh = { x = 19, w = 15 },
        next    = { x = 36, w = 12 },
        exit    = { x = W - 20, w = 15 }
    }
    local rightLimit = L.exit.x - 1
    -- «ПОИСК» — вплотную перед «ВЫХОД» (влезает уже с 80-колоночного экрана)
    local searchW = 12
    local searchX = L.exit.x - searchW
    if searchX >= L.next.x + L.next.w + 1 then
        L.search = { x = searchX, w = searchW }
    end
    -- «СДАТЬ ВСЁ» — после «>>», если не залезает на «ПОИСК»/«ВЫХОД»
    local depLimit = L.search and (L.search.x - 1) or rightLimit
    local dx = L.next.x + L.next.w + 2
    local dw = 15
    if dx + dw - 1 <= depLimit then
        L.deposit = { x = dx, w = dw }
    end
    return L
end

function ui.drawTabs(W, currentTab, isAdmin)
    local layout = ui.getTabLayout(W, isAdmin)
    for _, tab in ipairs(layout) do
        gpu.setBackground(currentTab == tab.id and C.tab_active or C.tab_inactive)
        -- OC GPU не умеет жирный шрифт: активная вкладка — ярко-белая, неактивные — приглушённые
        gpu.setForeground(currentTab == tab.id and C.white or C.muted)
        gpu.set(tab.x, 2, tab.label)
    end
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

function ui.drawMain(W, H, state)
    gpu.setBackground(C.bg)
    gpu.fill(1, 1, W, H, " ")
    ui.drawFrame(1, 1, W, H, state.alertActive and C.danger or C.border)
    
    -- Версия (слева на верхней рамке)
    gpu.setForeground(C.muted)
    gpu.set(3, 1, tostring(config.version or "") .. " | OC-Terminal")
    
    -- Индикатор текущего пользователя (кто стоит на PIM)
    local who
    if state.isTechAdmin then
        who = "[ TechAdmin: lixynhay ]"
        gpu.setForeground(C.techadmin)
    elseif state.currentPlayer then
        who = "[ Пользователь: " .. tostring(state.currentPlayer) .. " ]"
        gpu.setForeground(C.ok)
    else
        who = "[ Панель заблокирована ]"
        gpu.setForeground(C.danger)
    end
    if unicode.len(who) > W - 4 then who = unicode.sub(who, 1, W - 7) .. "..." end
    gpu.set(W - unicode.len(who) - 1, 1, who)
    
    ui.drawTabs(W, state.currentTab, state.isAdmin)
    
    -- Нижняя панель кнопок рисуется для всех вкладок (до ветвлений с return)
    local bottom = ui.getBottomLayout(W)
    ui.drawButton(bottom.prev.x, H - 2, bottom.prev.w, "<<", false)
    ui.drawButton(bottom.refresh.x, H - 2, bottom.refresh.w, "ОБНОВИТЬ", false)
    ui.drawButton(bottom.next.x, H - 2, bottom.next.w, ">>", false)
    if bottom.search and (state.currentTab == "ME" or state.currentTab == "INV" or state.currentTab == "LOGS") then
        ui.drawButton(bottom.search.x, H - 2, bottom.search.w, "ПОИСК", false, C.ok)
    end
    if state.currentTab == "INV" and bottom.deposit then
        ui.drawButton(bottom.deposit.x, H - 2, bottom.deposit.w, "СДАТЬ ВСЁ", false, C.warning)
    end
    if state.isAdmin then
        ui.drawButton(bottom.exit.x, H - 2, bottom.exit.w, "ВЫХОД", false)
    end
    
    if state.currentTab == "LOGS" then
        if state.isLogSearching or (state.logSearchQuery and state.logSearchQuery ~= "") then
            gpu.setForeground(C.title)
            local s = "Поиск по журналу: " .. tostring(state.logSearchQuery or "") .. "_"
            if unicode.len(s) > W - 6 then s = unicode.sub(s, 1, W - 9) .. "..." end
            gpu.set(3, 3, s)
        end
        ui.drawLogs(W, H, state.logs or {}, state.logsPage or 1, state.logsTotalPages or 1, {
            filter = state.logFilter or "all",
            clearArmed = state.logClearArmed == true,
            canClear = state.isAdmin == true,
        })
        return
    elseif state.currentTab == "ADMIN" then
        ui.drawAdmin(W, H, state.adminList)
        return
    elseif state.currentTab == "STATS" then
        ui.drawStats(W, H, state.networkInfo or {}, state.storageInfo, state.energyHistory)
        return
    elseif state.currentTab == "CRAFT" then
        ui.drawCraft(W, H, state.craftables or {}, state.craftPage or 1, state.totalPages or 1)
        return
    elseif state.currentTab == "MON" then
        ui.drawMonitor(W, H, state.monitorStatus or {})
        return
    end
    
    -- Строка поиска/фильтра (только для списков ME/INV)
    if state.isSearching then
        gpu.setForeground(C.title)
        local s = "Поиск: " .. tostring(state.searchQuery) .. "_"
        if unicode.len(s) > W - 6 then s = unicode.sub(s, 1, W - 9) .. "..." end
        gpu.set(3, 3, s)
    elseif state.searchQuery ~= "" then
        gpu.setForeground(C.title)
        local s = "Фильтр: " .. tostring(state.searchQuery) .. " (Esc - сброс)"
        if unicode.len(s) > W - 6 then s = unicode.sub(s, 1, W - 9) .. "..." end
        gpu.set(3, 3, s)
    end
    
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    
    -- Заголовок списка с индикатором сортировки
    gpu.setForeground(C.title)
    local base = (state.currentTab == "ME") and "--- Сеть МЭ" or "--- Ваш Инвентарь"
    local marker
    if state.sortMode == "desc" then
        marker = "[↓ Убыв.]"
    elseif state.sortMode == "asc" then
        marker = "[↑ Возр.]"
    else
        marker = "[А-Я]"
    end
    local title = base .. " " .. marker .. " ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)
    
    -- Отрисовка списка (внутри рамки: x=3..W-3, рамка остаётся на x=2 и x=W-2)
    gpu.fill(3, 5, W - 5, H - 10, " ")
    if state.currentTab == "INV" and not api.isPlayerPresent() then
        gpu.setForeground(C.err)
        gpu.set(4, 6, "Нет активного пользователя — встаньте на PIM")
    elseif #state.items == 0 then 
        gpu.setForeground(C.muted)
        gpu.set(4, 6, "Список пуст")
    else
        local startIdx = (state.page - 1) * (H - 10) + 1
        local endIdx = math.min(state.page * (H - 10), #state.items)

        -- Единая колонка начала строки: x=4 (1 пробел после рамки).
        -- Под иконку всегда отведено 2 колонки (иконка + пробел), поэтому
        -- названия и колонка количества выровнены и с иконкой, и без неё.
        local textX = 4
        local lineW = W - 7            -- от x=4 до x=W-4, 1 пробел до рамки
        local countW = 11              -- " | " + 8 цифр
        local maxL = lineW - countW - 2
        if maxL < 8 then maxL = 8 end

        for i = startIdx, endIdx do
            local rowY = 5 + (i - startIdx)
            gpu.setBackground((i % 2 == 0) and C.bg or C.row_alt)
            gpu.fill(3, rowY, W - 5, 1, " ")

            local dLabel = api.cleanLabel(tostring(state.items[i].display or state.items[i].label or "?"))
            local icon, iconColor = ui.getItemIcon(dLabel)
            local prefix = icon and (icon .. " ") or "  "

            if unicode.len(dLabel) > maxL then dLabel = unicode.sub(dLabel, 1, maxL - 3) .. "..." end
            local pad = maxL - unicode.len(dLabel)
            if pad < 0 then pad = 0 end

            -- Название, отступ и количество рисуются одной строкой с одного X
            gpu.setForeground(C.fg)
            gpu.set(textX, rowY, prefix .. dLabel .. string.rep(" ", pad) ..
                " | " .. string.format("%8d", math.floor(state.items[i].size or 0)))

            -- Перекрашиваем только сам символ иконки: позиция уже занята
            -- в строке, поэтому ничего не сдвигается и не налезает на рамку
            if icon then
                gpu.setForeground(iconColor)
                gpu.set(textX, rowY, icon)
            end
        end
        gpu.setBackground(C.bg)
    end
    gpu.setForeground(C.muted)
    local pText = "Стр. " .. state.page .. " из " .. state.totalPages
    gpu.set(W - unicode.len(pText) - 3, 4, pText)
end

-- Человекочитаемые названия ролей
local ROLE_LABELS = {
    user = "Пользователь",
    admin = "Администратор",
    techadmin = "Тех. админ",
    banned = "Забанен",
}

function ui.roleLabel(role)
    return ROLE_LABELS[tostring(role or "")] or tostring(role or "?")
end

-- Админ панель (список игроков)
function ui.drawAdmin(W, H, adminList)
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    gpu.setForeground(C.title)
    gpu.set(3, 5, "Игрок")
    gpu.set(W - 20, 5, "Роль")
    
    for i, player in ipairs(adminList) do
        if i > H - 8 then break end
        local name = player.name
        local data = player.data
        
        gpu.setForeground(C.fg)
        gpu.set(3, 5 + i, name)
        
        local role = tostring(data.role or "?")
        if name == "lixynhay" then role = "techadmin" end
        local roleColor = C.fg
        if role == "admin" then roleColor = C.admin end
        if role == "techadmin" then roleColor = C.techadmin end
        if role == "banned" then roleColor = C.banned end
        
        gpu.setForeground(roleColor)
        gpu.set(W - 20, 5 + i, ui.roleLabel(role))
    end
    
    gpu.setForeground(C.muted)
    gpu.set(3, H - 4, "Выберите игрока, чтобы изменить роль или выдать бан")
end

-- Окно управления игроком в админке (бан / роль) — геометрия 50x15
function ui.drawAdminBan(W, H, targetName, text, role)
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, W, H, " ")
    
    local mw, mh = 50, 15
    local mx = math.floor((W - mw) / 2) + 1
    local my = math.floor((H - mh) / 2) + 1
    
    -- Фон окна и одна аккуратная рамка (без тени/двойных линий)
    gpu.setBackground(C.modal)
    gpu.fill(mx, my, mw, mh, " ")
    gpu.setForeground(C.title)
    gpu.set(mx, my, "╔" .. string.rep("═", mw - 2) .. "╗")
    for i = 1, mh - 2 do
        gpu.set(mx, my + i, "║")
        gpu.set(mx + mw - 1, my + i, "║")
    end
    gpu.set(mx, my + mh - 1, "╚" .. string.rep("═", mw - 2) .. "╝")
    
    -- Заголовок (на my+1, по центру)
    gpu.setForeground(C.title)
    local title = " Игрок: " .. tostring(targetName) .. " "
    if unicode.len(title) > mw - 2 then title = unicode.sub(title, 1, mw - 5) .. "... " end
    gpu.set(mx + math.floor((mw - unicode.len(title)) / 2) + 1, my + 1, title)
    
    -- Роль
    gpu.setForeground(C.white)
    gpu.set(mx + 2, my + 3, "Роль:")
    gpu.setForeground(C.ok)
    gpu.set(mx + 10, my + 3, ui.roleLabel(role))
    
    -- Поле ввода причины
    gpu.setForeground(C.white)
    gpu.set(mx + 2, my + 6, "Причина бана:")
    
    -- Тёмная плашка под текст
    gpu.setBackground(0x111111)
    gpu.fill(mx + 2, my + 7, mw - 4, 1, " ")
    
    gpu.setForeground(C.ok)
    local displayText = tostring(text or "") .. "_"
    if unicode.len(displayText) > mw - 5 then
        displayText = unicode.sub(displayText, unicode.len(displayText) - (mw - 6), unicode.len(displayText))
    end
    gpu.set(mx + 3, my + 7, displayText)
    
    -- Кнопки (на my + mh - 3 = my + 12)
    local btnY = my + mh - 3
    gpu.setBackground(C.bg)
    ui.drawButton(mx + 2, btnY, 16, "ЗАБАНИТЬ", false, C.danger)
    ui.drawButton(mx + 20, btnY, 10, "РОЛЬ", false, C.limit)
    ui.drawButton(mx + 32, btnY, 16, "ЗАКРЫТЬ", false, C.disabled)
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

function ui.drawMonitor(W, H, statusList)
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    gpu.setForeground(C.title)
    local title = "Мониторинг запасов"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)
    
    -- Заголовки колонок
    gpu.setForeground(C.title)
    gpu.set(3, 5, "Название")
    gpu.set(W - 28, 5, "Текущее/Мин")
    gpu.set(W - 12, 5, "Статус")
    
    if #statusList == 0 then
        gpu.setForeground(C.muted)
        gpu.set(3, 7, "Нет настроенных лимитов.")
    else
        local maxL = math.max(10, W - 40)
        for i, s in ipairs(statusList) do
            local rowY = 6 + i
            if rowY > H - 5 then break end
            local label = s.label or "?"
            if unicode.len(label) > maxL then label = unicode.sub(label, 1, maxL - 3) .. "..." end
            gpu.setForeground(C.fg)
            gpu.set(3, rowY, label)
            local minv = tonumber(s.min) or 0
            local curv = tonumber(s.current) or 0
            if minv > 0 then
                local pct = math.floor(curv / minv * 100)
                if pct < 0 then pct = 0 end
                if pct > 100 then pct = 100 end
                local filled = math.floor(pct / 10)
                if filled < 0 then filled = 0 end
                if filled > 10 then filled = 10 end
                local bar = "[" .. string.rep("█", filled) .. string.rep("░", 10 - filled) .. "]"
                gpu.setForeground(s.isOk and C.ok or C.danger)
                gpu.set(W - 26, rowY, bar)
                gpu.set(W - 11, rowY, tostring(pct) .. "%")
            else
                gpu.setForeground(C.title)
                gpu.set(W - 20, rowY, tostring(curv))
            end
        end
    end
    
    gpu.setForeground(C.muted)
    gpu.set(3, H - 4, "Автообновление включено (каждые 2 сек)")
end

function ui.drawBannedScreen(W, H, banInfo)
    banInfo = banInfo or {}
    gpu.setBackground(C.danger)
    gpu.setForeground(C.white)
    gpu.fill(1, 1, W, H, " ")
    
    local title = "ДОСТУП ЗАПРЕЩЁН"
    local y = math.floor(H / 2) - 3
    gpu.setForeground(C.white)
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, y, title)
    
    local reason = "Причина: " .. tostring(banInfo.reason or "не указана")
    if unicode.len(reason) > W - 4 then reason = unicode.sub(reason, 1, W - 7) .. "..." end
    gpu.set(math.floor((W - unicode.len(reason)) / 2) + 1, y + 2, reason)
    
    local untilText
    if banInfo.expires and banInfo.expires > 0 then
        local d = tostring(banInfo.expires)
        if os.date then
            local ok, s = pcall(os.date, "%Y-%m-%d %H:%M", banInfo.expires)
            if ok and s then d = s end
        end
        untilText = "Заблокировано до: " .. d
    else
        untilText = "Блокировка: бессрочная"
    end
    gpu.set(math.floor((W - unicode.len(untilText)) / 2) + 1, y + 3, untilText)
    
    local hint = "Обратитесь к администратору сервера"
    gpu.set(math.floor((W - unicode.len(hint)) / 2) + 1, y + 5, hint)
    
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

-- ===== Журнал операций =====
-- Раскладка колонок: [Время] | [Игрок] | [Действие] | [Предмет] | [Кол-во]
local LOG_COLS = { time = 8, player = 12, action = 9, amount = 8 }

local function logColumnWidths(W)
    local fixed = LOG_COLS.time + 3 + LOG_COLS.player + 3 + LOG_COLS.action + 3 + 3 + LOG_COLS.amount
    local item = (W - 6) - fixed
    if item < 8 then item = 8 end
    return LOG_COLS.time, LOG_COLS.player, LOG_COLS.action, item, LOG_COLS.amount
end

local function padRight(s, w)
    s = tostring(s or "")
    if unicode.len(s) > w then s = unicode.sub(s, 1, w - 3) .. "..." end
    local pad = w - unicode.len(s)
    if pad < 0 then pad = 0 end
    return s .. string.rep(" ", pad)
end

local function padLeft(s, w)
    s = tostring(s or "")
    if unicode.len(s) > w then s = unicode.sub(s, 1, w - 3) .. "..." end
    local pad = w - unicode.len(s)
    if pad < 0 then pad = 0 end
    return string.rep(" ", pad) .. s
end

local function logActionLabel(action)
    if action == "put" then return "Сдал" end
    if action == "take" then return "Взял" end
    return tostring(action or "?")
end

local function logActionColor(action)
    if action == "put" then return C.ok end
    if action == "take" then return C.warning end
    return C.fg
end

local LOG_FILTERS = {
    { id = "all",  label = "Все",     hint = "1" },
    { id = "take", label = "Взяли",   hint = "2" },
    { id = "put",  label = "Сдали",   hint = "3" },
}

-- opts = { filter = "all"|"take"|"put", clearArmed = bool, canClear = bool }
function ui.drawLogs(W, H, logs, page, totalPages, opts)
    opts = opts or {}
    logs = logs or {}
    page = page or 1
    totalPages = totalPages or 1
    local filter = opts.filter or "all"

    ui.drawFrame(2, 4, W - 3, H - 8, C.border)

    -- Кнопка очистки (слева в заголовке, только для админа)
    if opts.canClear then
        ui.drawButton(3, 4, 12, opts.clearArmed and "ТОЧНО?" or "ОЧИСТИТЬ", false,
            opts.clearArmed and C.danger or C.disabled)
    end

    gpu.setForeground(C.title)
    local title = "--- Журнал операций ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)

    gpu.setForeground(C.muted)
    local pText = "Стр. " .. tostring(page) .. " из " .. tostring(totalPages)
    gpu.set(W - unicode.len(pText) - 3, 4, pText)

    -- Фильтр по типу операции
    local fx = 3
    gpu.setForeground(C.muted)
    gpu.set(fx, 5, "Фильтр:")
    fx = fx + 8
    for _, f in ipairs(LOG_FILTERS) do
        local active = (filter == f.id)
        gpu.setBackground(active and C.tab_active or C.tab_inactive)
        gpu.setForeground(active and C.white or C.muted)
        local label = " " .. f.label .. " (" .. f.hint .. ") "
        gpu.set(fx, 5, label)
        fx = fx + unicode.len(label) + 1
    end
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)

    -- Шапка колонок
    local wTime, wPlayer, wAction, wItem, wAmount = logColumnWidths(W)
    local header = padRight("Время", wTime) .. " | " ..
                   padRight("Игрок", wPlayer) .. " | " ..
                   padRight("Действие", wAction) .. " | " ..
                   padRight("Предмет", wItem) .. " | " ..
                   padLeft("Кол-во", wAmount)
    gpu.setForeground(C.title)
    gpu.set(3, 6, header)

    local headerY = 6
    local firstRow = headerY + 1
    -- Строки идут до нижней границы рамки (y = H-6), дальше — подсказка в H-4
    local perPage = math.max(1, (H - 6) - firstRow + 1)

    if #logs == 0 then
        gpu.setForeground(C.muted)
        gpu.set(3, firstRow + 1, "Записей нет.")
        gpu.setForeground(C.muted)
        gpu.set(3, H - 3, "Клавиши 1/2/3 — фильтр журнала")
        return
    end

    local startIdx = (page - 1) * perPage + 1
    local endIdx = math.min(page * perPage, #logs)

    -- Очищаем всю область списка, чтобы не оставалось строк от прошлой страницы/фильтра
    gpu.setBackground(C.bg)
    gpu.fill(3, firstRow, W - 5, perPage, " ")

    for i = startIdx, endIdx do
        local e = logs[i]
        local rowY = firstRow + (i - startIdx)
        gpu.setBackground((i % 2 == 0) and C.bg or C.row_alt)
        gpu.fill(3, rowY, W - 5, 1, " ")

        local ts = "--:--:--"
        if e.time and e.time > 0 and os.date then
            local okD, d = pcall(os.date, "%H:%M:%S", e.time)
            if okD and d then ts = d end
        end

        local line = padRight(ts, wTime) .. " | " ..
                     padRight(e.player or "?", wPlayer) .. " | " ..
                     padRight(logActionLabel(e.action), wAction) .. " | " ..
                     padRight(e.item or "?", wItem) .. " | " ..
                     padLeft(math.floor(tonumber(e.amount) or 0), wAmount)

        gpu.setForeground(C.fg)
        gpu.set(3, rowY, line)

        -- Перекрашиваем только ячейку действия
        local actionX = 3 + wTime + 3 + wPlayer + 3
        gpu.setForeground(logActionColor(e.action))
        gpu.set(actionX, rowY, padRight(logActionLabel(e.action), wAction))
    end
    gpu.setBackground(C.bg)

    gpu.setForeground(C.muted)
    gpu.set(3, H - 3, "Клавиши 1/2/3 — фильтр  |  всего записей: " .. tostring(#logs))
    gpu.setForeground(C.fg)
end

-- Позиции кнопок фильтра в строке y=5 (для обработки кликов)
function ui.getLogFilterLayout(W)
    local out = {}
    local fx = 3 + 8
    for _, f in ipairs(LOG_FILTERS) do
        local label = " " .. f.label .. " (" .. f.hint .. ") "
        local w = unicode.len(label)
        out[#out + 1] = { id = f.id, x = fx, w = w }
        fx = fx + w + 1
    end
    return out
end

-- Процент заполнения (0..100), безопасен при total == 0
local function percentOf(used, total)
    used = tonumber(used) or 0
    total = tonumber(total)
    if not total or total <= 0 then return 0 end
    local pct = math.floor(used / total * 100 + 0.5)
    if pct < 0 then pct = 0 end
    if pct > 100 then pct = 100 end
    return pct
end

-- Текстовая полоса прогресса шириной width
local function progressBar(pct, width)
    local filled = math.floor(pct / 100 * width + 0.5)
    if filled < 0 then filled = 0 end
    if filled > width then filled = width end
    return "[" .. string.rep("█", filled) .. string.rep("░", width - filled) .. "]"
end

-- ===== Иконки категорий предметов =====
-- Возвращает символ и цвет маркера (или nil, nil, если категория не опознана).
local function hasWord(haystack, word)
    if not haystack or not word then return false end
    -- Латиница: ищем слово целиком (чтобы "ore" не срабатывал внутри "storage")
    if word:find("^[%a]+$") then
        return haystack:find("%f[%a]" .. word .. "%f[%A]") ~= nil
    end
    -- Кириллица: простая подстрока (Lua-паттерны не работают с UTF-8 буквами)
    return haystack:find(word, 1, true) ~= nil
end

local ICON_RULES = {
    { color = "admin",  words = { "ingot", "слиток" } },
    { color = "muted",  words = { "ore", "руда" } },
    { color = "danger", words = { "dust", "пыль" } },
    { color = "ok",     words = { "food", "apple", "bread", "cookie", "cake",
                                  "яблоко", "хлеб", "мясо", "рыба", "пирог", "печенье" } },
}

function ui.getItemIcon(name)
    if type(name) ~= "string" or name == "" then return nil, nil end
    local lower = unicode.lower(name)
    for _, rule in ipairs(ICON_RULES) do
        for _, word in ipairs(rule.words) do
            -- Проверяем и в нижнем регистре, и в исходном (на случай, если
            -- unicode.lower не умеет в кириллицу в конкретной сборке)
            if hasWord(lower, word) or hasWord(name, word) then
                return "■", C[rule.color]
            end
        end
    end
    return nil, nil
end

-- ===== График энергии («кардиограмма») =====
-- Полная шкала заполнения: 8 уровней по 12.5% (0-100%)
local GRAPH_BLOCKS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

local function graphSymbol(pct)
    pct = tonumber(pct) or 0
    if pct <= 0 then return " " end
    if pct > 100 then pct = 100 end
    -- 1..8: 12.5% на уровень
    local lvl = math.ceil(pct / 100 * #GRAPH_BLOCKS)
    if lvl < 1 then lvl = 1 end
    if lvl > #GRAPH_BLOCKS then lvl = #GRAPH_BLOCKS end
    return GRAPH_BLOCKS[lvl]
end

-- Рисует однострочный график энергии: один символ на замер истории.
local function drawEnergyGraph(x, y, width, history)
    gpu.set(x, y, string.rep(" ", width))
    if not history or #history == 0 then return end

    local n = math.min(#history, width)
    local startIdx = #history - n + 1
    local chars = {}
    for col = 1, n do
        chars[col] = graphSymbol(history[startIdx + col - 1])
    end
    gpu.set(x, y, table.concat(chars))
end

-- Секунды -> ЧЧ:ММ:СС
local function formatUptime(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec < 0 then sec = 0 end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

function ui.drawStats(W, H, info, storage, history)
    info = info or {}
    storage = storage or info.storage
    history = history or info.energyHistory

    -- Рамка чуть ниже обычной: нижняя строка (H-4) остаётся под время работы
    ui.drawFrame(2, 4, W - 3, H - 9, C.border)
    -- Заливаем внутреннюю область, чтобы убрать старый вывод
    gpu.setBackground(C.bg)
    gpu.fill(3, 5, W - 5, H - 11, " ")

    gpu.setForeground(C.title)
    local title = "--- Статистика МЭ-сети ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)

    -- Внутри рамки доступны строки 5 .. H-7
    local lastRow = H - 7
    local y = 5

    gpu.setForeground(C.white)
    gpu.set(5, y, "Предметов:")
    gpu.setForeground(C.ok)
    gpu.set(16, y, tostring(info.totalItems or 0))
    gpu.setForeground(C.white)
    gpu.set(30, y, "Типов:")
    gpu.setForeground(C.ok)
    gpu.set(38, y, tostring(info.totalTypes or 0))
    y = y + 1

    if info.energyStored ~= nil and info.energyMax and info.energyMax > 0 then
        local pct = percentOf(info.energyStored, info.energyMax)

        gpu.setForeground(C.white)
        gpu.set(5, y, "Энергия:")
        gpu.setForeground(C.ok)
        gpu.set(25, y, string.format("%d / %d AE (%d%%)",
            math.floor(info.energyStored), math.floor(info.energyMax), pct))
        y = y + 1

        gpu.setForeground(pct >= 20 and C.ok or C.danger)
        gpu.set(5, y, progressBar(pct, 20))
        y = y + 1

        -- График энергии: одна строка, цвет C.ok
        if y <= lastRow then
            gpu.setForeground(C.ok)
            drawEnergyGraph(5, y, 20, history)
            y = y + 1
        end
    end

    -- Диски: объём в байтах и количество типов
    if storage then
        local usedBytes  = tonumber(storage.usedBytes) or 0
        local totalBytes = tonumber(storage.totalBytes)
        local usedTypes  = tonumber(storage.usedTypes) or 0
        local totalTypes = tonumber(storage.totalTypes)

        if y <= lastRow then
            gpu.setForeground(C.white)
            gpu.set(5, y, "Диски (Байты):")
        end

        if totalBytes and totalBytes > 0 and storage.estimated ~= true then
            local pct = percentOf(usedBytes, totalBytes)
            local color = C.ok
            if pct > 95 then
                color = C.danger
            elseif pct >= 80 then
                color = C.admin -- жёлтый/янтарный
            end
            if y + 1 <= lastRow then
                gpu.setForeground(color)
                gpu.set(5, y + 1, progressBar(pct, 20) .. " " .. tostring(pct) .. "%  " ..
                    formatSize(usedBytes) .. " / " .. formatSize(totalBytes))
            end
        else
            if y + 1 <= lastRow then
                gpu.setForeground(C.muted)
                gpu.set(5, y + 1, formatSize(usedBytes) .. " (оценка занятого)")
            end
        end
        y = y + 2

        if y <= lastRow then
            gpu.setForeground(C.white)
            gpu.set(5, y, "Диски (Типы):")
            gpu.setForeground(C.ok)
            local typesText = tostring(usedTypes)
            if totalTypes and totalTypes > 0 then
                typesText = typesText .. " / " .. tostring(totalTypes)
            end
            gpu.set(25, y, typesText)
        end
        y = y + 1
    end

    -- Крафт-процессоры
    local crafting = info.crafting
    if crafting and crafting.totalCpus and crafting.totalCpus > 0 then
        if y <= lastRow then
            gpu.setForeground(C.white)
            gpu.set(5, y, "Крафт-процессоры:")
            local busy = tonumber(crafting.busyCpus) or 0
            local total = tonumber(crafting.totalCpus) or 0
            gpu.setForeground(busy > 0 and C.admin or C.ok)
            gpu.set(25, y, tostring(busy) .. " / " .. tostring(total))
        end
        y = y + 1
    end

    if info.cpus then
        if y <= lastRow then
            gpu.setForeground(C.white)
            gpu.set(5, y, "Сопроцессоров:")
            gpu.setForeground(C.ok)
            gpu.set(25, y, tostring(info.cpus))
        end
        y = y + 1
    end

    gpu.setForeground(C.muted)
    gpu.set(5, lastRow, "Автообновление включено (каждые 2 сек)")

    -- Время работы компьютера — в самом низу
    local okUp, up = pcall(computer.uptime)
    local upText = "Время работы ПК: " .. formatUptime(okUp and up or 0)
    gpu.setForeground(C.title)
    gpu.fill(3, H - 4, W - 4, 1, " ")
    gpu.set(5, H - 4, upText)
    gpu.setForeground(C.fg)
end

function ui.drawCraft(W, H, craftables, page, totalPages)
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    gpu.setForeground(C.title)
    local title = "--- Доступные крафты ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)

    gpu.setForeground(C.muted)
    local pText = "Стр. " .. tostring(page or 1) .. " из " .. tostring(totalPages or 1)
    gpu.set(W - unicode.len(pText) - 3, 4, pText)

    gpu.fill(3, 5, W - 5, H - 10, " ")
    craftables = craftables or {}
    if #craftables == 0 then
        gpu.setForeground(C.muted)
        gpu.set(4, 6, "Нет доступных рецептов")
        return
    end

    local perPage = H - 10
    local startIdx = ((page or 1) - 1) * perPage + 1
    local endIdx = math.min((page or 1) * perPage, #craftables)

    -- Та же сетка, что и в основных списках: текст всегда с x=4,
    -- под иконку зарезервированы 2 колонки.
    local textX = 4
    local maxL = W - 8
    if maxL < 8 then maxL = 8 end

    for i = startIdx, endIdx do
        local rowY = 5 + (i - startIdx)
        gpu.setBackground((i % 2 == 0) and C.bg or C.row_alt)
        gpu.fill(3, rowY, W - 5, 1, " ")
        local label = api.cleanLabel(tostring(craftables[i].display or craftables[i].label or "?"))

        local icon, iconColor = ui.getItemIcon(label)
        local prefix = icon and (icon .. " ") or "  "

        if unicode.len(label) > maxL then label = unicode.sub(label, 1, maxL - 3) .. "..." end

        gpu.setForeground(C.fg)
        gpu.set(textX, rowY, prefix .. label)

        if icon then
            gpu.setForeground(iconColor)
            gpu.set(textX, rowY, icon)
        end
    end
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

function ui.drawModal(W, H, item, qty, mode, canAction, isAdmin)
    local isCraft = (mode == "CRAFT")
    gpu.setBackground(C.overlay)
    gpu.fill(1, 1, W, H, " ")
    local mw, mh = 56, 16
    local mx, my = math.floor((W - mw) / 2) + 1, math.floor((H - mh) / 2) + 1
    
    gpu.setBackground(C.modal)
    gpu.fill(mx, my, mw, mh, " ")
    ui.drawFrame(mx, my, mw, mh, C.title)
    
    gpu.setForeground(C.title)
    local titleText
    if isCraft then
        titleText = " Запрос на крафт "
    elseif mode == "ME" then
        titleText = " Выдача из МЭ-сети "
    else
        titleText = " Сдача в МЭ-сеть "
    end
    gpu.set(mx + math.floor((mw - unicode.len(titleText)) / 2) + 1, my, titleText)
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 2, "Название:")
    gpu.setForeground(C.fg)
    local n = api.cleanLabel(tostring(item.display or item.label or "?"))
    if unicode.len(n) > mw - 4 then n = unicode.sub(n, 1, mw - 7) .. "..." end
    gpu.set(mx + 2, my + 3, n)
    
    -- Подпись источника: у крафта — доступно для крафта, у МЭ — в сети, у инвентаря — на руках
    gpu.setForeground(C.white)
    local sourceLabel, sourceX
    if isCraft then
        sourceLabel, sourceX = "Доступно для крафта:", 23
    elseif mode == "ME" then
        sourceLabel, sourceX = "В МЭ-сети:", 13
    else
        sourceLabel, sourceX = "В инвентаре:", 15
    end
    gpu.set(mx + 2, my + 5, sourceLabel)
    gpu.setForeground(C.ok)
    gpu.set(mx + sourceX, my + 5, tostring(item.size or 0) .. " шт.")
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 7, "Количество:")
    ui.drawButton(mx + 2, my + 9, 6, "-10", false)
    ui.drawButton(mx + 9, my + 9, 6, "-1", false)
    gpu.setForeground(C.ok)
    local q = tostring(qty) .. " шт."
    gpu.set(mx + 17, my + 9, string.rep(" ", math.max(0, 10 - unicode.len(q))) .. q)
    ui.drawButton(mx + 29, my + 9, 6, "+1", false)
    ui.drawButton(mx + 36, my + 9, 6, "+10", false)
    
    -- Кнопка действия (неактивна, если нет прав или игрока)
    local btnText, btnBg
    if isCraft then
        btnText = "СКРАФТИТЬ"
        btnBg = canAction and C.ok or C.disabled
    elseif mode == "ME" then
        btnText = "ПОЛУЧИТЬ"
        btnBg = canAction and C.ok or C.disabled
    else
        btnText = "СДАТЬ"
        btnBg = canAction and C.warning or C.disabled
    end
    ui.drawButton(mx + 2, my + mh - 2, 18, btnText, false, btnBg)
    
    -- Кнопка лимита (только для админа, над «ЗАКРЫТЬ»; для крафта не нужна)
    if isAdmin and not isCraft then
        local th = db.getThresholds()[item.name]
        local limText = "Лимит:" .. tostring(th and th.min or "Нет")
        ui.drawButton(mx + mw - 20, my + mh - 3, 18, limText, false, C.limit)
    end
    
    ui.drawButton(mx + mw - 14, my + mh - 2, 12, "ЗАКРЫТЬ", false, C.danger)
end

return ui
