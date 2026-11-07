local component = require("component")
local unicode = require("unicode")
local config = require("config")
local api = require("me_api")
local db = require("db")
local gpu = component.gpu
local C = config.colors
local ui = {}

function ui.drawFrame(x, y, w, h, color)
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

function ui.drawTabs(W, currentTab, isAdmin)
    local layout = ui.getTabLayout(W, isAdmin)
    for _, tab in ipairs(layout) do
        gpu.setBackground(currentTab == tab.id and C.tab_active or C.tab_inactive)
        gpu.setForeground(C.white)
        gpu.set(tab.x, 2, tab.label)
    end
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

function ui.drawMain(W, H, state)
    gpu.setBackground(C.bg)
    gpu.fill(1, 1, W, H, " ")
    ui.drawFrame(1, 1, W, H, C.border)
    ui.drawTabs(W, state.currentTab, state.isAdmin)
    
    if state.currentTab == "ADMIN" then
        ui.drawAdmin(W, H, state.adminList)
        return
    elseif state.currentTab == "STATS" then
        ui.drawStats(W, H, state.networkInfo or {})
        return
    elseif state.currentTab == "MON" then
        ui.drawMonitor(W, H, state.monitorStatus or {})
        return
    end
    
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    
    -- Заголовок списка
    gpu.setForeground(C.title)
    local title = state.currentTab == "ME" and "--- Сеть МЭ ---" or "--- Ваш Инвентарь ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)
    
    ui.drawButton(5, H - 2, 12, "<<", false)
    ui.drawButton(19, H - 2, 15, "ОБНОВИТЬ", false)
    ui.drawButton(36, H - 2, 12, ">>", false)
    if state.currentTab == "INV" then
        ui.drawButton(52, H - 2, 15, "СДАТЬ ВСЁ", false, 0xAA5500)
    end
    ui.drawButton(W - 20, H - 2, 15, "ВЫХОД", false)
    
    -- Отрисовка списка
    gpu.fill(2, 5, W - 3, H - 9, " ")
    if state.currentTab == "INV" and not api.isPlayerPresent() then
        gpu.setForeground(C.err)
        gpu.set(3, 6, "Встаньте на PIM для сканирования!")
    elseif #state.items == 0 then 
        gpu.setForeground(0x888888)
        gpu.set(3, 6, "Список пуст...")
    else
        local startIdx = (state.page - 1) * (H - 10) + 1
        local endIdx = math.min(state.page * (H - 10), #state.items)
        local maxL = W - 20
        for i = startIdx, endIdx do
            local dLabel = state.items[i].label
            if unicode.len(dLabel) > maxL then dLabel = unicode.sub(dLabel, 1, maxL - 3) .. "..." end
            gpu.setForeground(C.fg)
            gpu.set(3, 5 + (i - startIdx), dLabel .. string.rep(" ", maxL - unicode.len(dLabel)) .. " | " .. string.format("%8d", state.items[i].size))
        end
    end
    gpu.setForeground(0x888888)
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
        
        local roleColor = C.fg
        if data.role == "admin" then roleColor = C.admin end
        if data.role == "banned" then roleColor = C.banned end
        
        gpu.setForeground(roleColor)
        gpu.set(W - 20, 5 + i, data.role)
    end
    
    gpu.setForeground(0x888888)
    gpu.set(3, H - 2, "Кликните на игрока для смены роли: user -> admin -> banned")
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
        gpu.setForeground(0x888888)
        gpu.set(3, 7, "Нет настроенных лимитов.")
    else
        local maxL = math.max(10, W - 40)
        for i, s in ipairs(statusList) do
            local rowY = 6 + i
            if rowY > H - 5 then break end
            local label = s.label
            if unicode.len(label) > maxL then label = unicode.sub(label, 1, maxL - 3) .. "..." end
            gpu.setForeground(C.fg)
            gpu.set(3, rowY, label)
            gpu.setForeground(C.title)
            gpu.set(W - 28, rowY, string.format("%d / %d", s.current, s.min))
            gpu.setForeground(s.isOk and C.ok or C.err)
            gpu.set(W - 12, rowY, s.isOk and "ОК" or "МАЛО")
        end
    end
    
    gpu.setForeground(0x888888)
    gpu.set(3, H - 4, "Нажмите ОБНОВИТЬ для обновления данных.")
end

function ui.drawStats(W, H, info)
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    gpu.setForeground(C.title)
    local title = "--- Статистика МЭ-сети ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)
    
    gpu.setForeground(C.white)
    gpu.set(5, 7, "Всего предметов:")
    gpu.setForeground(C.ok)
    gpu.set(25, 7, tostring(info.totalItems or 0))
    
    gpu.setForeground(C.white)
    gpu.set(5, 9, "Типов предметов:")
    gpu.setForeground(C.ok)
    gpu.set(25, 9, tostring(info.totalTypes or 0))
    
    if info.energyStored then
        gpu.setForeground(C.white)
        gpu.set(5, 11, "Энергия:")
        gpu.setForeground(C.ok)
        gpu.set(25, 11, string.format("%d / %d AE", info.energyStored, info.energyMax))
    end
    
    if info.cpus then
        gpu.setForeground(C.white)
        gpu.set(5, 13, "Сопроцессоров:")
        gpu.setForeground(C.ok)
        gpu.set(25, 13, tostring(info.cpus))
    end
    
    gpu.setForeground(0x888888)
    gpu.set(5, H - 4, "Нажмите ОБНОВИТЬ для обновления данных.")
end

function ui.drawModal(W, H, item, qty, mode, canAction, isAdmin)
    gpu.setBackground(0x000000)
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
    local n = item.label
    if unicode.len(n) > mw - 4 then n = unicode.sub(n, 1, mw - 7) .. "..." end
    gpu.set(mx + 2, my + 3, n)
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 5, "Доступно:")
    gpu.setForeground(C.ok); gpu.set(mx + 11, my + 5, tostring(item.size) .. " шт.")
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 7, "Количество:")
    ui.drawButton(mx + 2, my + 9, 6, "-10", false)
    ui.drawButton(mx + 9, my + 9, 6, "-1", false)
    gpu.setForeground(C.ok)
    local q = tostring(qty) .. " шт."
    gpu.set(mx + 17, my + 9, string.rep(" ", 10 - unicode.len(q)) .. q)
    ui.drawButton(mx + 29, my + 9, 6, "+1", false)
    ui.drawButton(mx + 36, my + 9, 6, "+10", false)
    
    -- Кнопка действия (неактивна, если нет прав или игрока)
    local btnBg = canAction and (mode == "ME" and C.ok or 0xAA5500) or 0x555555
    local btnText = mode == "ME" and "ЗАБРАТЬ" or "ПОЛОЖИТЬ"
    ui.drawButton(mx + 2, my + mh - 2, 18, btnText, false, btnBg)
    
    -- Кнопка лимита (только для админа, над «ЗАКРЫТЬ»)
    if isAdmin then
        local th = db.getThresholds()[item.name]
        local limText = "Лимит:" .. tostring(th and th.min or "Нет")
        ui.drawButton(mx + mw - 20, my + mh - 3, 18, limText, false, 0x5555AA)
    end
    
    ui.drawButton(mx + mw - 14, my + mh - 2, 12, "ЗАКРЫТЬ", false, 0xAA0000)
end

return ui
