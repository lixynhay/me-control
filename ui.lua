local component = require("component")
local unicode = require("unicode")
local config = require("config")
local api = require("me_api")
local db = require("db")
local gpu = component.gpu
local C = config.colors
local ui = {}
local formatSize = config.formatSize

function ui.drawFrame(x, y, w, h, color)
    -- Лёгкая тень: тот же прямоугольник на 1 символ правее/ниже, чёрным
    local sw, sh = gpu.getResolution()
    local sx, sy = x + 1, y + 1
    if sx + w - 1 <= sw and sy + h - 1 <= sh and w > 2 and h > 2 then
        gpu.setForeground(0x000000)
        gpu.set(sx, sy, "╔" .. string.rep("═", w - 2) .. "╗")
        for i = 1, h - 2 do
            gpu.set(sx, sy + i, "║")
            gpu.set(sx + w - 1, sy + i, "║")
        end
        gpu.set(sx, sy + h - 1, "╚" .. string.rep("═", w - 2) .. "╝")
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
        { id = "MON",   label = " Монитор " }
    }
    if isAdmin then
        table.insert(tabs, { id = "LOGS",  label = " Логи " })
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
            local s = "Поиск по логам: " .. tostring(state.logSearchQuery or "") .. "_"
            if unicode.len(s) > W - 6 then s = unicode.sub(s, 1, W - 9) .. "..." end
            gpu.set(3, 3, s)
        end
        ui.drawLogs(W, H, state.logs or {}, state.logsPage or 1, state.logsTotalPages or 1)
        return
    elseif state.currentTab == "ADMIN" then
        ui.drawAdmin(W, H, state.adminList)
        return
    elseif state.currentTab == "STATS" then
        ui.drawStats(W, H, state.networkInfo or {}, state.storageInfo)
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
    
    -- Заголовок списка
    gpu.setForeground(C.title)
    local title = state.currentTab == "ME" and "--- Сеть МЭ ---" or "--- Ваш Инвентарь ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)
    
    -- Отрисовка списка
    gpu.fill(2, 5, W - 3, H - 9, " ")
    if state.currentTab == "INV" and not api.isPlayerPresent() then
        gpu.setForeground(C.err)
        gpu.set(3, 6, "Встаньте на PIM для сканирования!")
    elseif #state.items == 0 then 
        gpu.setForeground(C.muted)
        gpu.set(3, 6, "Список пуст...")
    else
        local startIdx = (state.page - 1) * (H - 10) + 1
        local endIdx = math.min(state.page * (H - 10), #state.items)
        local maxL = W - 20
        for i = startIdx, endIdx do
            local rowY = 5 + (i - startIdx)
            gpu.setBackground((i % 2 == 0) and C.bg or C.row_alt)
            gpu.fill(3, rowY, W - 5, 1, " ")
            local dLabel = state.items[i].display or state.items[i].label
            if unicode.len(dLabel) > maxL then dLabel = unicode.sub(dLabel, 1, maxL - 3) .. "..." end
            gpu.setForeground(C.fg)
            gpu.set(3, rowY, dLabel .. string.rep(" ", maxL - unicode.len(dLabel)) .. " | " .. string.format("%8d", math.floor(state.items[i].size)))
        end
        gpu.setBackground(C.bg)
    end
    gpu.setForeground(C.muted)
    local pText = "Стр. " .. state.page .. " из " .. state.totalPages
    gpu.set(W - unicode.len(pText) - 3, 4, pText)
end

-- Админ панель (список игроков)
function ui.drawAdmin(W, H, adminList)
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    gpu.setForeground(C.title)
    gpu.set(3, 5, "Никнейм")
    gpu.set(W - 20, 5, "Роль")
    
    for i, player in ipairs(adminList) do
        if i > H - 8 then break end
        local name = player.name
        local data = player.data
        
        gpu.setForeground(C.fg)
        gpu.set(3, 5 + i, name)
        
        local roleText = tostring(data.role or "?")
        if name == "lixynhay" then roleText = "techadmin" end
        local roleColor = C.fg
        if roleText == "admin" then roleColor = C.admin end
        if roleText == "techadmin" then roleColor = C.techadmin end
        if roleText == "banned" then roleColor = C.banned end
        
        gpu.setForeground(roleColor)
        gpu.set(W - 20, 5 + i, roleText)
    end
    
    gpu.setForeground(C.muted)
    gpu.set(3, H - 4, "Кликните на игрока для смены роли: user -> admin -> banned")
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
    gpu.set(mx + 10, my + 3, tostring(role or "techadmin"))
    
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
    
    local title = "ДОСТУП ЗАПРЕЩЕН"
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
        untilText = "До: " .. d
    else
        untilText = "До: Навсегда"
    end
    gpu.set(math.floor((W - unicode.len(untilText)) / 2) + 1, y + 3, untilText)
    
    local hint = "Обратитесь к администратору"
    gpu.set(math.floor((W - unicode.len(hint)) / 2) + 1, y + 5, hint)
    
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

function ui.drawLogs(W, H, logs, page, totalPages)
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    gpu.setForeground(C.title)
    local title = "--- Логи операций ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)
    
    if #logs == 0 then
        gpu.setForeground(C.muted)
        gpu.set(3, 6, "Записей пока нет.")
    else
        local perPage = H - 10
        local startIdx = (page - 1) * perPage + 1
        local endIdx = math.min(page * perPage, #logs)
        local maxL = W - 6
        for i = startIdx, endIdx do
            local e = logs[i]
            local rowY = 5 + (i - startIdx)
            gpu.setBackground((i % 2 == 0) and C.bg or C.row_alt)
            gpu.fill(3, rowY, W - 5, 1, " ")
            local ts = tostring(e.time or 0)
            if e.time and e.time > 0 and os.date then
                local okD, d = pcall(os.date, "%H:%M:%S", e.time)
                if okD and d then ts = d end
            end
            local act = (e.action == "take") and "Взял" or "Сдал"
            local line = ts .. " | " .. tostring(e.player or "?") .. " | " ..
                         act .. " " .. tostring(e.amount or 0) .. " шт. " .. tostring(e.item or "?")
            if unicode.len(line) > maxL then line = unicode.sub(line, 1, maxL - 3) .. "..." end
            gpu.setForeground(C.fg)
            gpu.set(3, rowY, line)
        end
        gpu.setBackground(C.bg)
    end
    
    gpu.setForeground(C.muted)
    local pText = "Стр. " .. tostring(page) .. " из " .. tostring(totalPages)
    gpu.set(W - unicode.len(pText) - 3, 4, pText)
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

function ui.drawStats(W, H, info, storage)
    info = info or {}
    storage = storage or info.storage
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    gpu.setForeground(C.title)
    local title = "--- Статистика МЭ-сети ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)

    local y = 7

    gpu.setForeground(C.white)
    gpu.set(5, y, "Всего предметов:")
    gpu.setForeground(C.ok)
    gpu.set(25, y, tostring(info.totalItems or 0))
    y = y + 2

    gpu.setForeground(C.white)
    gpu.set(5, y, "Типов предметов:")
    gpu.setForeground(C.ok)
    gpu.set(25, y, tostring(info.totalTypes or 0))
    y = y + 2

    if info.energyStored ~= nil and info.energyMax and info.energyMax > 0 then
        gpu.setForeground(C.white)
        gpu.set(5, y, "Энергия:")
        gpu.setForeground(C.ok)
        gpu.set(25, y, string.format("%d / %d AE", info.energyStored, info.energyMax))
        local pct = percentOf(info.energyStored, info.energyMax)
        gpu.setForeground(pct >= 20 and C.ok or C.danger)
        gpu.set(5, y + 1, progressBar(pct, 20) .. " " .. tostring(pct) .. "%")
        gpu.setForeground(C.fg)
        y = y + 3
    end

    -- Диски: объём в байтах и количество типов
    if storage then
        local usedBytes  = tonumber(storage.usedBytes) or 0
        local totalBytes = tonumber(storage.totalBytes)
        local usedTypes  = tonumber(storage.usedTypes) or 0
        local totalTypes = tonumber(storage.totalTypes)

        gpu.setForeground(C.white)
        gpu.set(5, y, "Диски (Байты):")

        if totalBytes and totalBytes > 0 then
            local pct = percentOf(usedBytes, totalBytes)
            local color = C.ok
            if pct > 95 then
                color = C.danger
            elseif pct >= 80 then
                color = C.admin -- жёлтый/янтарный
            end
            gpu.setForeground(color)
            gpu.set(5, y + 1, progressBar(pct, 20) .. " " .. tostring(pct) .. "%  " ..
                formatSize(usedBytes) .. " / " .. formatSize(totalBytes))
        else
            -- Ёмкость сети недоступна: показываем хотя бы занятое (оценка)
            gpu.setForeground(storage.estimated and C.muted or C.ok)
            local text = formatSize(usedBytes)
            if storage.estimated then text = text .. " (оценка занятого)" end
            gpu.set(5, y + 1, text)
        end
        y = y + 3

        gpu.setForeground(C.white)
        gpu.set(5, y, "Диски (Типы):")
        gpu.setForeground(C.ok)
        local typesText = tostring(usedTypes)
        if totalTypes and totalTypes > 0 then
            typesText = typesText .. " / " .. tostring(totalTypes)
        end
        gpu.set(25, y, typesText)
        y = y + 2
    end

    if info.cpus then
        gpu.setForeground(C.white)
        gpu.set(5, y, "Сопроцессоров:")
        gpu.setForeground(C.ok)
        gpu.set(25, y, tostring(info.cpus))
        y = y + 2
    end

    gpu.setForeground(C.muted)
    gpu.set(5, H - 4, "Автообновление включено (каждые 2 сек)")
end

function ui.drawModal(W, H, item, qty, mode, canAction, isAdmin)
    gpu.setBackground(C.overlay)
    gpu.fill(1, 1, W, H, " ")
    local mw, mh = 56, 16
    local mx, my = math.floor((W - mw) / 2) + 1, math.floor((H - mh) / 2) + 1
    
    gpu.setBackground(C.modal)
    gpu.fill(mx, my, mw, mh, " ")
    ui.drawFrame(mx, my, mw, mh, C.title)
    
    gpu.setForeground(C.title)
    local t = " " .. (mode == "ME" and "Из МЭ" or "В МЭ") .. " "
    gpu.set(mx + math.floor((mw - unicode.len(t)) / 2) + 1, my, t)
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 2, "Название:")
    gpu.setForeground(C.fg)
    local n = item.display or item.label
    if unicode.len(n) > mw - 4 then n = unicode.sub(n, 1, mw - 7) .. "..." end
    gpu.set(mx + 2, my + 3, n)
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 5, "Доступно:")
    gpu.setForeground(C.ok); gpu.set(mx + 11, my + 5, tostring(item.size) .. " шт.")
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 7, "Количество:")
    ui.drawButton(mx + 2, my + 9, 6, "-10", false)
    ui.drawButton(mx + 9, my + 9, 6, "-1", false)
    gpu.setForeground(C.ok)
    local q = tostring(qty) .. " шт."
    gpu.set(mx + 17, my + 9, string.rep(" ", math.max(0, 10 - unicode.len(q))) .. q)
    ui.drawButton(mx + 29, my + 9, 6, "+1", false)
    ui.drawButton(mx + 36, my + 9, 6, "+10", false)
    
    -- Кнопка действия (неактивна, если нет прав или игрока)
    local btnBg = canAction and (mode == "ME" and C.ok or C.warning) or C.disabled
    local btnText = mode == "ME" and "ЗАБРАТЬ" or "ПОЛОЖИТЬ"
    ui.drawButton(mx + 2, my + mh - 2, 18, btnText, false, btnBg)
    
    -- Кнопка лимита (только для админа, над «ЗАКРЫТЬ»)
    if isAdmin then
        local th = db.getThresholds()[item.name]
        local limText = "Лимит:" .. tostring(th and th.min or "Нет")
        ui.drawButton(mx + mw - 20, my + mh - 3, 18, limText, false, C.limit)
    end
    
    ui.drawButton(mx + mw - 14, my + mh - 2, 12, "ЗАКРЫТЬ", false, C.danger)
end

return ui
