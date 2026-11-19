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
        gpu.setForeground(C.overlay)
        gpu.setBackground(C.overlay)
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

function ui.getTabs(canModerate, isAdmin, canCraft)
    if canCraft == nil then canCraft = true end  -- обратная совместимость вызовов
    local tabs = {
        { id = "DASH",  label = " Главная " },
        { id = "ME",    label = " МЭ-сеть " },
        { id = "INV",   label = " Инвентарь " },
        { id = "MON",   label = " Монитор " }
    }
    if canCraft then
        table.insert(tabs, 5, { id = "CRAFT", label = " Крафт " })
    end
    if canModerate then
        table.insert(tabs, { id = "LOGS",  label = " Журнал " })
        table.insert(tabs, { id = "ADMIN", label = " Админ " })
    end
    if isAdmin then
        table.insert(tabs, { id = "UPD", label = " Обновление " })
    end
    return tabs
end

function ui.getTabLayout(W, canModerate, isAdmin, canCraft)
    local tabs = ui.getTabs(canModerate, isAdmin, canCraft)
    local totalW = 0
    for _, tab in ipairs(tabs) do totalW = totalW + unicode.len(tab.label) + 2 end
    totalW = totalW - 2
    local startX = math.floor((W - totalW) / 2) + 1
    if startX < 1 then startX = 1 end

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

function ui.drawTabs(W, currentTab, canModerate, isAdmin, canCraft)
    local layout = ui.getTabLayout(W, canModerate, isAdmin, canCraft)
    for _, tab in ipairs(layout) do
        gpu.setBackground(currentTab == tab.id and C.tab_active or C.tab_inactive)
        -- OC GPU не умеет жирный шрифт: активная вкладка — ярко-белая, неактивные — приглушённые
        gpu.setForeground(currentTab == tab.id and C.white or C.muted)
        gpu.set(tab.x, 2, tab.label)
    end
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

-- ===== Индикатор глобальных запретов (allowUserWithdraw/Deposit/Craft = false) =====
-- Рисуется в шапке сразу после версии; клик открывает расшифровку.
ui.RESTRICTION_LABEL = "[!] Ограничения"

function ui.getRestrictionsLayout(W)
    local vtext = tostring(config.version or "") .. " | OC-Terminal"
    local x = 3 + unicode.len(vtext) + 2
    local w = unicode.len(ui.RESTRICTION_LABEL)
    if x + w > W - 2 then return nil end
    return { x = x, y = 1, w = w }
end

function ui.getRestrictionsModalLayout(W, H, count)
    local mw = 46
    local mh = 6 + math.max(1, count or 1)
    local mx = math.floor((W - mw) / 2) + 1
    local my = math.floor((H - mh) / 2) + 1
    return {
        mx = mx, my = my, mw = mw, mh = mh,
        close = { x = mx + mw - 14, y = my + mh - 2, w = 12 },
    }
end

-- list = { "Крафт отключён администратором", ... }
function ui.drawRestrictions(W, H, list)
    list = list or {}
    local L = ui.getRestrictionsModalLayout(W, H, #list)
    gpu.setBackground(C.overlay)
    gpu.fill(1, 1, W, H, " ")
    gpu.setBackground(C.modal)
    gpu.fill(L.mx, L.my, L.mw, L.mh, " ")
    ui.drawFrame(L.mx, L.my, L.mw, L.mh, C.warning)

    gpu.setForeground(C.warning)
    local title = " Глобальные ограничения "
    gpu.set(L.mx + math.floor((L.mw - unicode.len(title)) / 2) + 1, L.my, title)

    local maxLen = L.mw - 6
    for i = 1, #list do
        local line = "[!] " .. tostring(list[i])
        if unicode.len(line) > maxLen then line = unicode.sub(line, 1, maxLen - 3) .. "..." end
        gpu.setForeground(C.err)
        gpu.set(L.mx + 2, L.my + 1 + i, line)
    end

    ui.drawButton(L.close.x, L.close.y, L.close.w, "ЗАКРЫТЬ", false, C.disabled)
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

-- ===== Плавающие уведомления (Toasts) =====
local TOAST_COLORS = {
    ok   = { border = C.ok,      text = C.white, icon = "+" },
    err  = { border = C.err,     text = C.white, icon = "!" },
    warn = { border = C.admin,   text = C.white, icon = "!" },
    info = { border = C.title,   text = C.white, icon = "i" },
}

-- notifications: массив { text = "...", type = "ok"|"err"|"warn", time = uptime }
-- Рисуются плашками в правом верхнем углу, поверх интерфейса.
function ui.drawToasts(W, H, notifications)
    if not notifications or #notifications == 0 then return end

    local boxW = 28
    if boxW > W - 6 then boxW = W - 6 end
    local boxH = 3
    local x = W - boxW - 3
    local y0 = 4

    local maxToasts = math.floor((H - y0 - 3) / boxH)
    if maxToasts < 1 then return end

    -- Показываем самые свежие (последние в очереди)
    local first = math.max(1, #notifications - maxToasts + 1)

    for idx = first, #notifications do
        local n = notifications[idx]
        local style = TOAST_COLORS[n.type] or TOAST_COLORS.info
        local y = y0 + (idx - first) * boxH

        -- Непрозрачная подложка, чтобы не сливаться с фоном
        gpu.setBackground(C.modal)
        gpu.setForeground(style.border)
        gpu.fill(x, y, boxW, boxH, " ")

        -- Рамка
        gpu.set(x, y, "╔" .. string.rep("═", boxW - 2) .. "╗")
        for i = 1, boxH - 2 do
            gpu.set(x, y + i, "║")
            gpu.set(x + boxW - 1, y + i, "║")
        end
        gpu.set(x, y + boxH - 1, "╚" .. string.rep("═", boxW - 2) .. "╝")

        -- Текст: [иконка] сообщение
        local text = tostring(n.text or "")
        local maxLen = boxW - 7
        if unicode.len(text) > maxLen then
            text = unicode.sub(text, 1, maxLen - 3) .. "..."
        end
        gpu.setForeground(style.border)
        gpu.set(x + 2, y + 1, "[" .. style.icon .. "]")
        gpu.setForeground(style.text)
        gpu.set(x + 6, y + 1, text)
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

    -- Индикатор глобальных запретов: виден только когда есть ограничения
    if state.globalRestrictions and #state.globalRestrictions > 0 then
        local R = ui.getRestrictionsLayout(W)
        if R then
            gpu.setForeground(state.showRestrictions and C.white or C.warning)
            gpu.set(R.x, R.y, ui.RESTRICTION_LABEL)
        end
    end
    
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
    
    ui.drawTabs(W, state.currentTab, state.canModerate, state.isAdmin, state.canCraftTab)
    
    -- Нижняя панель кнопок рисуется для всех вкладок (до ветвлений с return).
    -- На «Главной» (DASH) своя панель кнопок рисуется в ui.drawDashboard —
    -- стандартные <<, >> и [ ОБНОВИТЬ ] здесь не дублируем.
    local bottom = ui.getBottomLayout(W)
    if state.currentTab ~= "DASH" then
        ui.drawButton(bottom.prev.x, H - 2, bottom.prev.w, "<<", false)
        ui.drawButton(bottom.refresh.x, H - 2, bottom.refresh.w, "ОБНОВИТЬ", false)
        ui.drawButton(bottom.next.x, H - 2, bottom.next.w, ">>", false)
    end
    if bottom.search and (state.currentTab == "ME" or state.currentTab == "INV" or state.currentTab == "LOGS") then
        ui.drawButton(bottom.search.x, H - 2, bottom.search.w, "ПОИСК", false, C.ok)
    end
    if state.currentTab == "INV" and bottom.deposit then
        ui.drawButton(bottom.deposit.x, H - 2, bottom.deposit.w, "СДАТЬ ВСЁ", false, C.warning)
    end
    if state.isAdmin then
        ui.drawButton(bottom.exit.x, H - 2, bottom.exit.w, "ВЫХОД", false)
    end
    
    if state.currentTab == "DASH" then
        ui.drawDashboard(W, H, state)
        return
    elseif state.currentTab == "LOGS" then
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
    elseif state.currentTab == "CRAFT" then
        ui.drawCraft(W, H, state.craftables or {}, state.craftPage or 1, state.totalPages or 1)
        return
    elseif state.currentTab == "MON" then
        ui.drawMonitor(W, H, state.monitorStatus or {})
        return
    elseif state.currentTab == "UPD" then
        ui.drawUpdater(W, H, state.updateLogs or {}, state.isUpdating, state.isUpdateFinished)
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

        -- Маркеры настроек: [A] — автокрафт включён, [L] — лимит без автокрафта
        local thresholds = state.thresholds or {}

        for i = startIdx, endIdx do
            local rowY = 5 + (i - startIdx)
            gpu.setBackground((i % 2 == 0) and C.bg or C.row_alt)
            gpu.fill(3, rowY, W - 5, 1, " ")

            local item = state.items[i]
            local dLabel = api.cleanLabel(tostring(item.display or item.label or "?"))
            local icon, iconColor = ui.getItemIcon(dLabel)
            local prefix = icon and (icon .. " ") or "  "

            local th = item.name and thresholds[item.name] or nil
            local marker = ""
            if th then
                marker = (th.autoCraft ~= false) and "[A] " or "[L] "
            end

            local labelRoom = maxL - unicode.len(marker)
            if labelRoom < 4 then labelRoom = 4 end
            if unicode.len(dLabel) > labelRoom then dLabel = unicode.sub(dLabel, 1, labelRoom - 3) .. "..." end
            local pad = labelRoom - unicode.len(dLabel)
            if pad < 0 then pad = 0 end

            -- Название, отступ и количество рисуются одной строкой с одного X
            gpu.setForeground(C.fg)
            gpu.set(textX, rowY, prefix .. marker .. dLabel .. string.rep(" ", pad) ..
                " | " .. string.format("%8d", math.floor(item.size or 0)))

            -- Перекрашиваем только сам символ иконки: позиция уже занята
            -- в строке, поэтому ничего не сдвигается и не налезает на рамку
            if icon then
                gpu.setForeground(iconColor)
                gpu.set(textX, rowY, icon)
            end
            -- Маркер подсвечиваем: [A] — зелёный, [L] — приглушённый
            if marker ~= "" then
                gpu.setForeground(th.autoCraft ~= false and C.ok or C.muted)
                gpu.set(textX + unicode.len(prefix), rowY, marker)
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
    guest = "Гость",
    user = "Пользователь",
    moderator = "Модератор",
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
    -- Очищаем список, чтобы не оставались строки от других вкладок
    gpu.setBackground(C.bg)
    gpu.fill(3, 5, W - 5, H - 10, " ")
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
        if role == "guest" then roleColor = C.muted end
        if role == "moderator" then roleColor = C.limit end
        if role == "admin" then roleColor = C.admin end
        if role == "techadmin" then roleColor = C.techadmin end
        if role == "banned" then roleColor = C.banned end
        
        gpu.setForeground(roleColor)
        gpu.set(W - 20, 5 + i, ui.roleLabel(role))
    end
    
    gpu.setForeground(C.muted)
    gpu.set(3, H - 4, "Выберите игрока, чтобы изменить роль или выдать бан")
end

-- Форматирует время лога как ЧЧ:ММ (или дату, если запись не за сегодня)
local function formatLogTime(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return "--:--" end
    local now = os.time and tonumber(os.time()) or 0
    local today = os.date and os.date("%d.%m", now) or nil
    local stampDay = os.date and os.date("%d.%m", ts) or nil
    local fmt = (today and stampDay and today ~= stampDay) and "%d.%m %H:%M" or "%H:%M"
    if os.date then
        local ok, s = pcall(os.date, fmt, ts)
        if ok and s then return s end
    end
    return "--:--"
end

-- Строка истории: "[12:30] Сдал 64x Iron Ingot"
local function formatLogLine(entry)
    local action = entry.action
    local label = "Взял"
    if action == "put" then label = "Сдал"
    elseif action == "craft" then label = "Скрафтил" end
    local amount = math.floor(tonumber(entry.amount) or 0)
    local item = tostring(entry.item or "?")
    return "[" .. formatLogTime(entry.time) .. "] " .. label .. " " .. amount .. "x " .. item
end

local function logActionColor(action)
    if action == "put" then return C.ok end
    if action == "take" then return C.warning end
    if action == "craft" then return C.title end
    return C.fg
end

-- Окно управления игроком в админке (роль / права / статистика / история) — 58x22
-- opts = {
--   role = "...", text = "причина",
--   perms = { canWithdraw, canDeposit, canCraft },
--   totalActions = N, lastSeen = ts,
--   history = { лог-записи }  -- до 5, свежие первыми
-- }
function ui.drawAdminBan(W, H, targetName, opts)
    opts = opts or {}
    local text = opts.text or ""
    local role = opts.role or "user"
    local perms = opts.perms or {}
    local history = opts.history or {}

    gpu.setBackground(C.overlay)
    gpu.fill(1, 1, W, H, " ")

    local mw, mh = 58, 22
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

    -- Заголовок
    gpu.setForeground(C.title)
    local title = " Игрок: " .. tostring(targetName) .. " "
    if unicode.len(title) > mw - 2 then title = unicode.sub(title, 1, mw - 5) .. "... " end
    gpu.set(mx + math.floor((mw - unicode.len(title)) / 2) + 1, my + 1, title)

    -- Роль + быстрые кнопки «на уровень ниже / выше»
    gpu.setForeground(C.white)
    gpu.set(mx + 2, my + 2, "Роль:")
    gpu.setForeground(C.ok)
    gpu.set(mx + 9, my + 2, ui.roleLabel(role))
    ui.drawButton(mx + 30, my + 2, 4, "-", false, C.limit)
    ui.drawButton(mx + 36, my + 2, 4, "+", false, C.limit)

    -- Статус бана
    local ban = opts.ban or {}
    gpu.setForeground(C.white)
    gpu.set(mx + 2, my + 3, "Бан:")
    if ban.banned then
        gpu.setForeground(C.err)
        local banLine = tostring(ban.reason or "без причины")
        if tonumber(ban.expires) and tonumber(ban.expires) > 0 then
            banLine = banLine .. " (до " .. formatLogTime(ban.expires) .. ")"
        end
        local room = mw - 10
        if unicode.len(banLine) > room then banLine = unicode.sub(banLine, 1, room - 3) .. "..." end
        gpu.set(mx + 9, my + 3, banLine)
    else
        gpu.setForeground(C.muted)
        gpu.set(mx + 9, my + 3, "нет")
    end

    -- Персональные права: три тумблера в одной строке
    gpu.setForeground(C.white)
    gpu.set(mx + 2, my + 4, "Права:")

    local function permButton(x, y, w, label, enabled)
        local stateText = enabled and "ВКЛ" or "ВЫКЛ"
        local bgColor = enabled and C.ok or C.disabled
        ui.drawButton(x, y, w, label .. ":" .. stateText, false, bgColor)
    end

    permButton(mx + 2,  my + 5, 18, "ЗАБОР", perms.canWithdraw ~= false)
    permButton(mx + 21, my + 5, 18, "СДАЧА", perms.canDeposit ~= false)
    permButton(mx + 40, my + 5, 16, "КРАФТ", perms.canCraft ~= false)

    -- Статистика профиля
    gpu.setForeground(C.white)
    gpu.set(mx + 2, my + 7, "Статистика:")
    gpu.setForeground(C.muted)
    gpu.set(mx + 2, my + 8, "Всего действий:")
    gpu.setForeground(C.fg)
    gpu.set(mx + 19, my + 8, tostring(math.floor(tonumber(opts.totalActions) or 0)))

    gpu.setForeground(C.muted)
    gpu.set(mx + 2, my + 9, "Последняя активность:")
    gpu.setForeground(C.fg)
    local lastSeen = tonumber(opts.lastSeen) or 0
    gpu.set(mx + 24, my + 9, lastSeen > 0 and formatLogTime(lastSeen) or "Не заходил")

    -- Последние 5 действий
    gpu.setForeground(C.white)
    gpu.set(mx + 2, my + 11, "Последние 5 действий:")

    local rowY = my + 12
    if #history == 0 then
        gpu.setForeground(C.muted)
        gpu.set(mx + 3, rowY, "Нет недавних действий")
    else
        local maxLen = mw - 6
        for i = 1, math.min(5, #history) do
            local e = history[i]
            local line = formatLogLine(e)
            if unicode.len(line) > maxLen then
                line = unicode.sub(line, 1, maxLen - 3) .. "..."
            end
            gpu.setForeground(logActionColor(e.action))
            gpu.set(mx + 3, rowY + (i - 1), line)
        end
    end

    -- Поле ввода причины бана (ниже истории: 5 строк от my+12 до my+16)
    local reasonY = my + 17
    gpu.setForeground(C.white)
    gpu.set(mx + 2, reasonY, "Причина бана:")

    gpu.setBackground(C.input)
    gpu.fill(mx + 2, reasonY + 1, mw - 4, 1, " ")

    gpu.setForeground(C.ok)
    local displayText = tostring(text or "") .. "_"
    if unicode.len(displayText) > mw - 5 then
        displayText = unicode.sub(displayText, unicode.len(displayText) - (mw - 6), unicode.len(displayText))
    end
    gpu.set(mx + 3, reasonY + 1, displayText)

    -- Кнопки внизу
    local btnY = my + mh - 2
    gpu.setBackground(C.bg)
    ui.drawButton(mx + 2,  btnY, 16, "ЗАБАНИТЬ", false, C.danger)
    ui.drawButton(mx + 20, btnY, 12, "РОЛЬ", false, C.limit)
    ui.drawButton(mx + 33, btnY, 11, "РАЗБАН", false, C.warning)
    ui.drawButton(mx + mw - 12, btnY, 10, "ЗАКРЫТЬ", false, C.disabled)
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

-- Геометрия кнопок окна игрока (общая для отрисовки и обработки кликов)
function ui.getAdminBanLayout(W, H)
    local mw, mh = 58, 22
    local mx = math.floor((W - mw) / 2) + 1
    local my = math.floor((H - mh) / 2) + 1
    return {
        mx = mx, my = my, mw = mw, mh = mh,
        roleDown = { x = mx + 30, y = my + 2, w = 4 },
        roleUp   = { x = mx + 36, y = my + 2, w = 4 },
        withdraw = { x = mx + 2,  y = my + 5, w = 18 },
        deposit  = { x = mx + 21, y = my + 5, w = 18 },
        craft    = { x = mx + 40, y = my + 5, w = 16 },
        ban      = { x = mx + 2,      y = my + mh - 2, w = 16 },
        role     = { x = mx + 20,     y = my + mh - 2, w = 12 },
        unban    = { x = mx + 33,     y = my + mh - 2, w = 11 },
        close    = { x = mx + mw - 12, y = my + mh - 2, w = 10 },
    }
end

-- ===== Личная история операций игрока =====
-- entries — массив записей лога (свежие первыми), до ui.PLAYER_HISTORY_ROWS штук.
ui.PLAYER_HISTORY_ROWS = 10

function ui.getPlayerHistoryLayout(W, H, count)
    local mw = 52
    local rows = math.max(1, math.min(tonumber(count) or 1, ui.PLAYER_HISTORY_ROWS))
    local mh = 5 + rows
    local mx = math.floor((W - mw) / 2) + 1
    local my = math.floor((H - mh) / 2) + 1
    return {
        mx = mx, my = my, mw = mw, mh = mh, rows = rows,
        close = { x = mx + mw - 14, y = my + mh - 2, w = 12 },
    }
end

function ui.drawPlayerHistory(W, H, playerName, entries)
    entries = entries or {}
    local shown = math.min(#entries, ui.PLAYER_HISTORY_ROWS)
    local L = ui.getPlayerHistoryLayout(W, H, math.max(shown, 1))

    gpu.setBackground(C.overlay)
    gpu.fill(1, 1, W, H, " ")
    gpu.setBackground(C.modal)
    gpu.fill(L.mx, L.my, L.mw, L.mh, " ")
    ui.drawFrame(L.mx, L.my, L.mw, L.mh, C.title)

    gpu.setForeground(C.title)
    local title = " История операций: " .. tostring(playerName or "?") .. " "
    if unicode.len(title) > L.mw - 2 then title = unicode.sub(title, 1, L.mw - 5) .. "... " end
    gpu.set(L.mx + math.floor((L.mw - unicode.len(title)) / 2) + 1, L.my, title)

    if shown == 0 then
        gpu.setForeground(C.muted)
        gpu.set(L.mx + 3, L.my + 2, "Нет операций")
    else
        local maxLen = L.mw - 6
        for i = 1, shown do
            local e = entries[i]
            local line = formatLogLine(e)
            if unicode.len(line) > maxLen then
                line = unicode.sub(line, 1, maxLen - 3) .. "..."
            end
            gpu.setForeground(logActionColor(e.action))
            gpu.set(L.mx + 3, L.my + 1 + i, line)
        end
    end

    ui.drawButton(L.close.x, L.close.y, L.close.w, "ЗАКРЫТЬ", false, C.disabled)
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

-- ===== Детали предмета (Raw ID / Damage / NBT) =====
-- NBT определяем по отпечатку МЭ или полю nbt: у обычных предметов их нет.
function ui.itemHasNbt(item)
    if type(item) ~= "table" then return false end
    if item.nbt ~= nil then return true end
    if item.fingerprint ~= nil and item.fingerprint ~= "" then return true end
    return false
end

function ui.getItemInfoLayout(W, H)
    local mw, mh = 56, 12
    local mx = math.floor((W - mw) / 2) + 1
    local my = math.floor((H - mh) / 2) + 1
    return {
        mx = mx, my = my, mw = mw, mh = mh,
        limit = { x = mx + 2, y = my + mh - 2, w = 20 },
        close = { x = mx + mw - 14, y = my + mh - 2, w = 12 },
    }
end

function ui.drawItemInfo(W, H, item, isAdmin)
    item = item or {}
    local L = ui.getItemInfoLayout(W, H)

    gpu.setBackground(C.overlay)
    gpu.fill(1, 1, W, H, " ")
    gpu.setBackground(C.modal)
    gpu.fill(L.mx, L.my, L.mw, L.mh, " ")
    ui.drawFrame(L.mx, L.my, L.mw, L.mh, C.title)

    gpu.setForeground(C.title)
    local title = " Детали предмета "
    gpu.set(L.mx + math.floor((L.mw - unicode.len(title)) / 2) + 1, L.my, title)

    local maxLen = L.mw - 14
    local function row(y, label, value, color)
        gpu.setForeground(C.white)
        gpu.set(L.mx + 2, y, label)
        local text = tostring(value)
        if unicode.len(text) > maxLen then text = unicode.sub(text, 1, maxLen - 3) .. "..." end
        gpu.setForeground(color or C.fg)
        gpu.set(L.mx + 14, y, text)
    end

    row(L.my + 2, "Название:", api.cleanLabel(tostring(item.display or item.label or "?")), C.fg)
    row(L.my + 3, "Raw ID:", tostring(item.name or "?"), C.title)

    local damage = math.floor(tonumber(item.damage) or 0)
    if damage > 0 then
        row(L.my + 4, "Damage:", tostring(damage), C.admin)
    end

    if ui.itemHasNbt(item) then
        row(L.my + 5, "NBT:", "Есть NBT-данные", C.ok)
        local fp = item.fingerprint
        if fp ~= nil and fp ~= "" then
            -- В МЭ отпечаток часто приходит таблицей: показываем это явно, а не "table: 0x..."
            local fpText = (type(fp) == "table") and "объект МЭ (hash)" or tostring(fp)
            row(L.my + 6, "Fingerprint:", fpText, C.muted)
        end
    else
        row(L.my + 5, "NBT:", "Без NBT", C.muted)
    end

    if isAdmin then
        ui.drawButton(L.limit.x, L.limit.y, L.limit.w, "Настроить лимит", false, C.limit)
    end
    ui.drawButton(L.close.x, L.close.y, L.close.w, "ЗАКРЫТЬ", false, C.disabled)
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

-- ===== Модалка «Лимит и Автокрафт» (admin+) =====
-- opts = { current = <запас в сети>, min = <минимум>, autoCraft = true/false, label = "..." }
function ui.getLimitModalLayout(W, H)
    local mw, mh = 52, 14
    local mx = math.floor((W - mw) / 2) + 1
    local my = math.floor((H - mh) / 2) + 1
    return {
        mx = mx, my = my, mw = mw, mh = mh,
        minus10 = { x = mx + 2,  y = my + 8, w = 6 },
        minus1  = { x = mx + 9,  y = my + 8, w = 6 },
        plus1   = { x = mx + 29, y = my + 8, w = 6 },
        plus10  = { x = mx + 36, y = my + 8, w = 6 },
        toggle  = { x = mx + 2,  y = my + 10, w = 22 },
        save    = { x = mx + 2,  y = my + mh - 2, w = 14 },
        close   = { x = mx + mw - 14, y = my + mh - 2, w = 12 },
    }
end

function ui.drawLimitModal(W, H, itemName, opts)
    opts = opts or {}
    local L = ui.getLimitModalLayout(W, H)
    local minAmount = math.floor(tonumber(opts.min) or 0)
    local autoCraft = opts.autoCraft ~= false

    gpu.setBackground(C.overlay)
    gpu.fill(1, 1, W, H, " ")
    gpu.setBackground(C.modal)
    gpu.fill(L.mx, L.my, L.mw, L.mh, " ")
    ui.drawFrame(L.mx, L.my, L.mw, L.mh, C.title)

    gpu.setForeground(C.title)
    local title = " Лимит и Автокрафт "
    gpu.set(L.mx + math.floor((L.mw - unicode.len(title)) / 2) + 1, L.my, title)

    local maxLen = L.mw - 6
    local function clip(text)
        local t = tostring(text)
        if unicode.len(t) > maxLen then t = unicode.sub(t, 1, maxLen - 3) .. "..." end
        return t
    end

    gpu.setForeground(C.white)
    gpu.set(L.mx + 2, L.my + 2, "Предмет:")
    gpu.setForeground(C.fg)
    gpu.set(L.mx + 12, L.my + 2, clip(api.cleanLabel(tostring(opts.label or itemName or "?"))))

    gpu.setForeground(C.white)
    gpu.set(L.mx + 2, L.my + 3, "В сети:")
    gpu.setForeground(C.ok)
    gpu.set(L.mx + 12, L.my + 3, tostring(math.floor(tonumber(opts.current) or 0)))

    gpu.setForeground(C.white)
    gpu.set(L.mx + 2, L.my + 5, "Минимум:")
    gpu.setForeground(minAmount > 0 and C.admin or C.muted)
    gpu.set(L.mx + 12, L.my + 5, tostring(minAmount))

    gpu.setForeground(C.muted)
    gpu.set(L.mx + 2, L.my + 6, "0 — лимит снять")

    -- Кнопки количества (как в крафте)
    ui.drawButton(L.minus10.x, L.minus10.y, L.minus10.w, "-10", false)
    ui.drawButton(L.minus1.x,  L.minus1.y,  L.minus1.w,  "-1",  false)
    ui.drawButton(L.plus1.x,   L.plus1.y,   L.plus1.w,   "+1",  false)
    ui.drawButton(L.plus10.x,  L.plus10.y,  L.plus10.w,  "+10", false)

    -- Тумблер автокрафта
    ui.drawButton(L.toggle.x, L.toggle.y, L.toggle.w,
        "Автокрафт:" .. (autoCraft and "ВКЛ" or "ВЫКЛ"), false,
        autoCraft and C.ok or C.disabled)

    ui.drawButton(L.save.x, L.save.y, L.save.w, "СОХРАНИТЬ", false, C.ok)
    ui.drawButton(L.close.x, L.close.y, L.close.w, "ЗАКРЫТЬ", false, C.disabled)
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

-- ===== Вкладка «Обновление» =====
-- Раскладка кнопок (общая для отрисовки и обработки кликов).
-- Кнопка «ОБНОВИТЬ» и «ПЕРЕЗАПУСТИТЬ» располагаются на одном месте.
function ui.getUpdaterLayout(W, H)
    local bw = 22
    local bx = math.floor((W - bw) / 2) + 1
    local by = H - 5
    return {
        update  = { x = bx, y = by, w = bw },
        restart = { x = bx, y = by, w = bw },
    }
end

function ui.drawUpdater(W, H, logs, isUpdating, isFinished)
    logs = logs or {}

    -- Заголовок
    gpu.setForeground(C.title)
    local title = "--- Обновление системы ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)

    -- Рамка-лог
    local frameY = 6
    local frameW = W - 6
    local frameH = H - 12
    if frameH < 3 then frameH = 3 end
    ui.drawFrame(3, frameY, frameW, frameH, C.border)

    -- Строки журнала (показываем последние, что влезают)
    local innerX = 5
    local innerY = frameY + 1
    local innerW = frameW - 4
    local innerH = frameH - 2
    if innerW < 4 then innerW = 4 end
    local startIdx = math.max(1, #logs - innerH + 1)
    for i = startIdx, #logs do
        local rowY = innerY + (i - startIdx)
        local text = tostring(logs[i] or "")
        if unicode.len(text) > innerW then
            text = unicode.sub(text, 1, innerW - 3) .. "..."
        end
        local color = C.fg
        if text:find("ОШИБКА", 1, true) or text:find("ПРОПУСК", 1, true) then
            color = C.err
        elseif text:find("OK:", 1, true) then
            color = C.ok
        end
        gpu.setForeground(color)
        gpu.set(innerX, rowY, text)
    end

    -- Статус / кнопки
    local layout = ui.getUpdaterLayout(W, H)
    if isUpdating then
        gpu.setForeground(C.err)
        local s = "[ ИДЁТ ОБНОВЛЕНИЕ... ]"
        gpu.set(math.floor((W - unicode.len(s)) / 2) + 1, layout.update.y, s)
    elseif isFinished then
        ui.drawButton(layout.restart.x, layout.restart.y, layout.restart.w, "ПЕРЕЗАПУСТИТЬ", false, C.ok)
    else
        ui.drawButton(layout.update.x, layout.update.y, layout.update.w, "ОБНОВИТЬ", false, C.ok)
    end

    -- Подсказка
    gpu.setForeground(C.muted)
    gpu.set(5, H - 3, "Требуется интернет-карта и токен /home/mecontrol.token")

    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
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

-- Внутренняя ширина текстовой полосы прогресса (без учёта скобок "[" "]")
local ENERGY_BAR_WIDTH = 20
-- Энергетическая полоса и график под ней начинаются в этой колонке
local ENERGY_BAR_X = 5

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
-- Рисуется ПОСТРОЧНО через gpu.set, чтобы гарантированно не задевать
-- соседние строки (полосу заполнения сверху и «Приход/Расход» снизу).
-- При пустой истории НЕ рисует ничего (в т.ч. не выводит пустые символы).
local function drawEnergyGraph(x, y, width, history)
    if not history or #history == 0 then return end

    local n = math.min(#history, width)
    local startIdx = #history - n + 1
    for col = 1, n do
        local sym = graphSymbol(history[startIdx + col - 1])
        gpu.set(x + col - 1, y, sym)
    end
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

-- ===== Системная панель (admin+): метрики ПК и история healthcheck =====

-- Секунды -> ЧЧ:ММ (компактный uptime для системной секции)
function ui.formatUptimeHM(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec < 0 then sec = 0 end
    return string.format("%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60))
end

-- Текстовая полоса заполнения памяти: bar, процент занятого.
-- freeKb/totalKb — как их отдают computer.freeMemory()/totalMemory().
function ui.memoryBar(freeKb, totalKb, width)
    local total = tonumber(totalKb)
    local free = tonumber(freeKb) or 0
    if not total or total <= 0 then return nil, 0 end
    local used = total - free
    if used < 0 then used = 0 end
    if used > total then used = total end
    local pct = percentOf(used, total)
    return progressBar(pct, width or 20), pct
end

-- Разбор одной JSON-строки из /home/healthcheck.history.
-- Битая строка -> { broken = true }: UI не падает и показывает ERR.
function ui.parseHealthcheckLine(line)
    if type(line) ~= "string" or line == "" then return { broken = true } end

    local out = {}
    local pos, n = 1, #line
    local function skip()
        while pos <= n and line:sub(pos, pos):match("%s") do pos = pos + 1 end
    end

    skip()
    if line:sub(pos, pos) ~= "{" then return { broken = true } end
    pos = pos + 1

    while true do
        skip()
        local ch = line:sub(pos, pos)
        if ch == "}" then pos = pos + 1; break end
        if ch ~= '"' then return { broken = true } end

        local keyEnd = line:find('"', pos + 1, true)
        if not keyEnd then return { broken = true } end
        local key = line:sub(pos + 1, keyEnd - 1)
        pos = keyEnd + 1

        skip()
        if line:sub(pos, pos) ~= ":" then return { broken = true } end
        pos = pos + 1
        skip()

        local value
        if line:sub(pos, pos) == '"' then
            local vend = line:find('"', pos + 1, true)
            if not vend then return { broken = true } end
            value = line:sub(pos + 1, vend - 1)
            pos = vend + 1
        else
            local s, e = line:find("^[-%d%.eE+]+", pos)
            if s then
                value = tonumber(line:sub(s, e)) or 0
                pos = e + 1
            else
                local word = line:match("^%a+", pos)
                if word == "true" then value = true
                elseif word == "false" then value = false
                elseif word == "null" then value = nil
                else return { broken = true } end
                pos = pos + #word
            end
        end

        if key ~= "" then out[key] = value end

        skip()
        local sep = line:sub(pos, pos)
        pos = pos + 1
        if sep == "}" then break end
        if sep ~= "," then return { broken = true } end
        -- после запятой обязан идти следующий ключ (висячая запятая = битая строка)
        skip()
        if line:sub(pos, pos) ~= '"' then return { broken = true } end
    end

    if out.version == nil and out.ts == nil then return { broken = true } end
    return out
end

-- ===== Блок «Диски» в секции «Система» (admin+) =====
ui.DRIVES_PER_PAGE = 5

-- Геометрия блока (общая для отрисовки и обработки кликов).
-- Живёт в правой колонке «Главной», под переключателем «Сеть/Система».
function ui.getDrivesLayout(W, H, totalDrives, page)
    local colGap = 4
    local leftX = 4
    local leftW = math.floor((W - 5 - colGap) / 2) - 1
    if leftW < 20 then leftW = 20 end
    local rightX = leftX + leftW + colGap
    local rightW = (W - 3) - rightX - 1
    if rightW < 18 then rightW = 18 end

    local top = 6   -- строка 6: под переключателем режимов (строка 5)
    local total = math.max(0, math.floor(tonumber(totalDrives) or 0))
    local totalPages = math.max(1, math.ceil(total / ui.DRIVES_PER_PAGE))
    local cur = math.floor(tonumber(page) or 1)
    if cur < 1 then cur = 1 end
    if cur > totalPages then cur = totalPages end

    local L = {
        rightX = rightX, rightW = rightW, top = top,
        page = cur, totalPages = totalPages,
        prev = { x = rightX + rightW - 10, y = top, w = 4 },
        next = { x = rightX + rightW - 5,  y = top, w = 4 },
        drives = {},
    }

    local startIdx = (cur - 1) * ui.DRIVES_PER_PAGE + 1
    local shown = math.min(ui.DRIVES_PER_PAGE, math.max(0, total - startIdx + 1))
    for i = 1, shown do
        local rowY = top + 1 + (i - 1) * 2
        L.drives[i] = {
            index = startIdx + i - 1,
            infoY = rowY,
            plus  = { x = rightX,      y = rowY + 1, w = 6 },
            minus = { x = rightX + 7,  y = rowY + 1, w = 6 },
            eject = { x = rightX + 14, y = rowY + 1, w = 9 },
        }
    end
    return L
end

-- Компактная строка диска: слот, заполнение, типы, приоритет (+ байты, если влезает).
function ui.formatDriveLine(drive, width)
    local pct = percentOf(drive.usedBytes or 0, drive.totalBytes)
    local usedTypes = tostring(math.floor(tonumber(drive.usedTypes) or 0))
    local totalTypes = tonumber(drive.totalTypes)
    local types = (totalTypes and totalTypes > 0) and (usedTypes .. "/" .. math.floor(totalTypes)) or usedTypes
    local prio = drive.priority ~= nil and tostring(math.floor(drive.priority)) or "-"

    local line = string.format("[%s] %d%% %s P:%s",
        tostring(drive.slot), pct, types, prio)

    -- Байты добавляем, если есть место (на 80 колонках правая колонка узкая).
    -- Крупные объёмы — в MB, мелкие — в KB, совсем мелкие — в байтах.
    local totalBytes = tonumber(drive.totalBytes)
    if totalBytes and totalBytes > 0 then
        local usedBytes = tonumber(drive.usedBytes) or 0
        local sizeText
        if totalBytes >= 1048576 then
            sizeText = string.format("%.1f/%.1fMB", usedBytes / 1048576, totalBytes / 1048576)
        elseif totalBytes >= 1024 then
            sizeText = string.format("%.0f/%.0fKB", usedBytes / 1024, totalBytes / 1024)
        else
            sizeText = string.format("%d/%dB", usedBytes, totalBytes)
        end
        local extra = " " .. sizeText
        if unicode.len(line .. extra) <= (width or 0) then line = line .. extra end
    end

    if width and unicode.len(line) > width then
        line = unicode.sub(line, 1, width - 3) .. "..."
    end
    return line, pct
end

function ui.drawDrivesPanel(W, H, state)
    state = state or {}
    local drives = state.drives or {}
    local L = ui.getDrivesLayout(W, H, #drives, state.drivePage or 1)

    gpu.setForeground(C.title)
    gpu.set(L.rightX, L.top, "Диски")
    if L.totalPages > 1 then
        ui.drawButton(L.prev.x, L.prev.y, L.prev.w, "<", false)
        ui.drawButton(L.next.x, L.next.y, L.next.w, ">", false)
    end

    if #drives == 0 then
        gpu.setForeground(C.muted)
        gpu.set(L.rightX, L.top + 1, "Нет дисководов")
        return L
    end

    for i, slotL in ipairs(L.drives) do
        local d = drives[slotL.index]
        if d then
            local text, pct = ui.formatDriveLine(d, L.rightW)
            -- Цвет: зелёный <90%, жёлтый 70-89%, красный >=90%
            local color = C.ok
            if pct >= 90 then color = C.danger
            elseif pct >= 70 then color = C.admin end
            gpu.setForeground(color)
            gpu.set(L.rightX, slotL.infoY, text)

            ui.drawButton(slotL.plus.x, slotL.plus.y, slotL.plus.w, "+P", false, C.limit)
            ui.drawButton(slotL.minus.x, slotL.minus.y, slotL.minus.w, "-P", false, C.limit)
            ui.drawButton(slotL.eject.x, slotL.eject.y, slotL.eject.w, "Eject", false, C.warning)
        end
    end
    return L
end

-- Секция «Система» внутри «Главной» (только admin/techadmin).
-- state.systemInfo  = { uptime, memFreeKb, memTotalKb, apiMs, config }
-- state.healthHistory = массив строк из ui.parseHealthcheckLine
function ui.drawSystemPanel(W, H, state, top)
    state = state or {}
    local sys = state.systemInfo or {}
    local info = state.networkInfo or {}
    local lastRow = H - 5
    local leftX = 4
    local valueX = leftX + 14
    local y = top or 5

    -- Ширина левой колонки: значения не должны заезжать в блок «Диски» справа
    local colGap = 4
    local leftW = math.floor((W - 5 - colGap) / 2) - 1
    if leftW < 20 then leftW = 20 end
    local maxValue = leftW - (valueX - leftX)
    if maxValue < 6 then maxValue = 6 end

    local function clip(text, width)
        local t = tostring(text)
        if width and unicode.len(t) > width then
            t = unicode.sub(t, 1, math.max(1, width - 3)) .. "..."
        end
        return t
    end

    local function line(label, value, color)
        if y > lastRow then return end
        gpu.setForeground(C.white)
        gpu.set(leftX, y, label)
        gpu.setForeground(color or C.fg)
        gpu.set(valueX, y, clip(value, maxValue))
        y = y + 1
    end

    line("Версия:", tostring(config.version or "?"), C.title)
    line("Uptime:", ui.formatUptimeHM(sys.uptime), C.ok)

    local freeKb, totalKb = tonumber(sys.memFreeKb), tonumber(sys.memTotalKb)
    if freeKb and totalKb and totalKb > 0 then
        -- На узких экранах длинная подпись не влезает в половину ширины
        local memText
        if maxValue >= 30 then
            memText = string.format("Свободно %d MB / Всего %d MB",
                math.floor(freeKb / 1024), math.floor(totalKb / 1024))
        else
            memText = string.format("%d / %d MB",
                math.floor(freeKb / 1024), math.floor(totalKb / 1024))
        end
        line("Память:", memText, C.fg)
        -- Ширина полосы подгоняется под колонку, чтобы не обрезалась
        local barW = maxValue - 6
        if barW > 20 then barW = 20 end
        if barW < 6 then barW = 6 end
        local bar, pct = ui.memoryBar(freeKb, totalKb, barW)
        if bar and y <= lastRow then
            local color = C.ok
            if pct >= 90 then color = C.danger
            elseif pct >= 70 then color = C.admin end
            gpu.setForeground(color)
            gpu.set(valueX, y, clip(bar .. " " .. tostring(pct) .. "%", maxValue))
            y = y + 1
        end
    else
        line("Память:", "нет данных", C.muted)
    end

    local apiMs = tonumber(sys.apiMs)
    local itemsCount = tostring(info.totalItems or 0)
    if maxValue >= 26 then
        if apiMs then
            line("МЭ-сеть:", "Предметов " .. itemsCount ..
                " | API " .. tostring(math.floor(apiMs)) .. " мс", C.ok)
        else
            line("МЭ-сеть:", "Предметов " .. itemsCount .. " | API н/д", C.muted)
        end
    else
        -- Узкая колонка: компактная запись, чтобы не заезжать в блок «Диски»
        if apiMs then
            line("МЭ-сеть:", itemsCount .. " шт | " .. tostring(math.floor(apiMs)) .. " мс", C.ok)
        else
            line("МЭ-сеть:", itemsCount .. " шт | н/д", C.muted)
        end
    end

    -- Активные автокрафты (лимит задан и флаг включён)
    local active = tonumber(sys.activeAutoCrafts) or 0
    line("Автокрафт:", tostring(active) .. " активных", active > 0 and C.ok or C.muted)

    -- Глобальные флаги: выключенные подсвечиваем красным
    local cfg = sys.config or {}
    if y <= lastRow then
        gpu.setForeground(C.white)
        gpu.set(leftX, y, "Флаги:")
        local flags = {
            { long = "Забор", short = "З", on = cfg.allowUserWithdraw ~= false },
            { long = "Сдача", short = "С", on = cfg.allowUserDeposit ~= false },
            { long = "Крафт", short = "К", on = cfg.allowUserCraft ~= false },
        }
        local useLong = maxValue >= 30
        local limitX = valueX + maxValue
        local fx = valueX
        for _, f in ipairs(flags) do
            local txt = useLong
                and (f.long .. ":" .. (f.on and "ВКЛ" or "ВЫКЛ"))
                or (f.short .. ":" .. (f.on and "ВКЛ" or "ВЫКЛ"))
            if fx + unicode.len(txt) > limitX then break end
            gpu.setForeground(f.on and C.ok or C.err)
            gpu.set(fx, y, txt)
            fx = fx + unicode.len(txt) + 1
        end
        y = y + 1
    end

    -- История healthcheck
    if y <= lastRow then
        gpu.setForeground(C.title)
        gpu.set(leftX, y, "История (healthcheck):")
        y = y + 1
    end

    local rows = state.healthHistory or {}
    if #rows == 0 then
        if y <= lastRow then
            gpu.setForeground(C.muted)
            gpu.set(leftX + 2, y, "История пуста")
        end
        return
    end

    if y <= lastRow then
        gpu.setForeground(C.muted)
        -- Колонки узкие, чтобы таблица не заходила в правую колонку с блоком «Диски»
        gpu.set(leftX + 2, y, string.format("%-6s %-7s %-8s %-3s %s",
            "Uptime", "Версия", "RAM Free", "Шт", "API"))
        y = y + 1
    end

    for i = 1, math.min(5, #rows) do
        if y > lastRow then break end
        local r = rows[i]
        if r.broken then
            gpu.setForeground(C.err)
            gpu.set(leftX + 2, y, "ERR  битая строка истории")
        else
            local when = tonumber(r.uptime_secs) and ui.formatUptimeHM(r.uptime_secs)
                or tostring(r.ts or "--:--")
            local ver = tostring(r.version or "?")
            local freeMb = "-"
            if tonumber(r.mem_free_kb) then
                freeMb = math.floor(tonumber(r.mem_free_kb) / 1024) .. " MB"
            end
            local items = r.items_count ~= nil and tostring(r.items_count) or "-"
            local api = r.cold_call_ms ~= nil and tostring(r.cold_call_ms) or "-"
            gpu.setForeground(C.fg)
            gpu.set(leftX + 2, y, string.format("%-6s %-7s %-8s %-3s %s",
                when, ver, freeMb, items, api))
        end
        y = y + 1
    end
end

-- ===== Вкладка «Главная» (дашборд) =====
-- Русские подписи действий в журнале -> человекочитаемый текст
local ACTION_LABEL = {
    take = "взял",
    put  = "сдал",
}

-- Действие -> глагол в 3-м лице для строки событий
local ACTION_VERB = {
    take = "получил",
    put  = "сдал",
}

-- Раскладка кнопок дашборда (общая для отрисовки и обработки кликов)
function ui.getDashboardLayout(W, H)
    local bw, gap = 17, 2
    local total = bw * 4 + gap * 3
    local x = math.floor((W - total) / 2) + 1
    if x < 2 then x = 2 end
    local function mk(off, action, text)
        return { x = x + off, y = H - 3, w = bw, action = action, text = text }
    end
    return {
        mk(0,              "net",     "МЭ-СЕТЬ"),
        mk(bw + gap,       "deposit", "СДАТЬ ВСЁ"),
        mk((bw + gap) * 2, "history", "МОИ ДЕЙСТВИЯ"),
        mk((bw + gap) * 3, "refresh", "ОБНОВИТЬ"),
    }
end

-- Режимы «Главной» для admin/techadmin: сеть AE2 или метрики ПК
ui.DASH_MODES = {
    { id = "net",    label = "Сеть" },
    { id = "system", label = "Система" },
}

-- Раскладка переключателя «[Сеть] / [Система]» (общая для отрисовки и кликов)
function ui.getDashModeLayout(W, H)
    local bw, gap = 12, 1
    local total = bw * #ui.DASH_MODES + gap * (#ui.DASH_MODES - 1)
    local x = W - 3 - total
    if x < 3 then x = 3 end
    local out = {}
    for i, m in ipairs(ui.DASH_MODES) do
        out[#out + 1] = {
            x = x + (i - 1) * (bw + gap), y = 5, w = bw,
            id = m.id, label = m.label,
        }
    end
    return out
end

-- Отрисовка дашборда. state — общий state из main.lua:
--   networkInfo (totalItems/totalTypes/энергия), crafting (busy/total), logs,
--   storageInfo, canModerate/isAdmin, dashMode ("net"/"system"),
--   systemInfo и healthHistory (только для admin+).
function ui.drawDashboard(W, H, state)
    state = state or {}
    local info = state.networkInfo or {}
    local crafting = info.crafting or {}
    local history = state.energyHistory

    -- Верхняя рамка-панель (не мешает глобальным вкладкам и статусу внизу)
    ui.drawFrame(2, 4, W - 3, H - 8, C.border)
    gpu.setBackground(C.bg)
    gpu.fill(3, 5, W - 5, H - 10, " ")

    gpu.setForeground(C.title)
    local title = "--- Главная ---"
    gpu.set(math.floor((W - unicode.len(title)) / 2) + 1, 4, title)

    -- Переключатель «Сеть / Система» — только admin/techadmin
    local isAdmin = state.isAdmin == true
    local mode = state.dashMode or "net"
    local top = 5
    if isAdmin then
        for _, m in ipairs(ui.getDashModeLayout(W, H)) do
            local active = (m.id == mode)
            ui.drawButton(m.x, m.y, m.w, m.label, false,
                active and C.tab_active or C.btn)
        end
        top = 6
    end

    -- Режим «Система»: метрики ПК, история healthcheck и диски
    if isAdmin and mode == "system" then
        ui.drawSystemPanel(W, H, state, top)
        ui.drawDrivesPanel(W, H, state)
        for _, b in ipairs(ui.getDashboardLayout(W, H)) do
            local bg = C.btn
            if b.action == "deposit" then bg = C.warning end
            if b.action == "refresh" then bg = C.ok end
            ui.drawButton(b.x, b.y, b.w, b.text, false, bg)
        end
        gpu.setForeground(C.fg)
        return
    end

    local lastRow = H - 5
    local colGap = 4
    local leftX = 4
    local leftW = math.floor((W - 5 - colGap) / 2) - 1
    if leftW < 20 then leftW = 20 end
    local rightX = leftX + leftW + colGap
    local rightW = (W - 3) - rightX - 1
    if rightW < 18 then rightW = 18 end

    -- Модератор и выше видит статистику AE2 (энергия, график, диски)
    local showStats = state.canModerate == true

    -- ===== Левая колонка: сводка =====
    local y = top
    gpu.setForeground(C.title)
    gpu.set(leftX, y, "Сводка")
    y = y + 1

    gpu.setForeground(C.white)
    gpu.set(leftX, y, "Предметов:")
    gpu.setForeground(C.ok)
    -- totalItems — число уникальных типов (ТЗ-010); отдельная строка «Типов»
    -- дублировала это же значение, поэтому показываем одно число.
    gpu.set(leftX + 18, y, tostring(info.totalItems or 0))
    y = y + 1

    gpu.setForeground(C.white)
    gpu.set(leftX, y, "Крафт-процессоры:")
    y = y + 1
    local busy = tonumber(crafting.busyCpus) or 0
    local total = tonumber(crafting.totalCpus) or 0
    gpu.setForeground(busy > 0 and C.admin or C.ok)
    gpu.set(leftX + 2, y, tostring(busy) .. " / " .. tostring(total))

    -- ===== Правая колонка: энергия и диски (moderator+) =====
    y = top
    if showStats then
        gpu.setForeground(C.title)
        gpu.set(rightX, y, "Энергия")
        y = y + 1

        local eStored = tonumber(info.energyStored)
        local eMax = tonumber(info.energyMax)
        if eStored and eMax and eMax > 0 then
            local pct = percentOf(eStored, eMax)
            gpu.setForeground(C.white)
            gpu.set(rightX, y, string.format("%d / %d AE (%d%%)",
                math.floor(eStored), math.floor(eMax), pct))
            y = y + 1

            -- Полоса заполнения — цельная, ENERGY_BAR_WIDTH символов внутри
            gpu.setForeground(pct >= 20 and C.ok or C.danger)
            gpu.set(rightX, y, progressBar(pct, ENERGY_BAR_WIDTH))
            local barY = y
            y = y + 1

            -- График строго под полосой; при пустой истории не рисуется вовсе
            gpu.setForeground(C.ok)
            drawEnergyGraph(rightX, barY + 1, ENERGY_BAR_WIDTH + 2, history)
            y = barY + 2
        else
            gpu.setForeground(C.muted)
            gpu.set(rightX, y, "нет данных о энергии")
            y = y + 2
        end

        -- Приход / расход
        local injection = tonumber(info.avgPowerInjection)
        local usage = tonumber(info.avgPowerUsage)
        if injection ~= nil or usage ~= nil then
            injection = injection or 0
            usage = usage or 0
            local deficit = usage > injection
            if y <= lastRow then
                gpu.setForeground(C.ok)
                gpu.set(rightX, y, string.format("+%.0f AE/t", injection))
                gpu.setForeground(C.danger)
                gpu.set(rightX + 14, y, string.format("-%.0f AE/t", usage))
                y = y + 1
            end
            if deficit and y <= lastRow then
                gpu.setForeground(C.danger)
                gpu.set(rightX, y, "[!] Дефицит")
                y = y + 1
            end
        end

        -- Диски (перенесено со вкладки «Статистика»)
        local storage = state.storageInfo
        if storage and y <= lastRow then
            local usedBytes  = tonumber(storage.usedBytes) or 0
            local totalBytes = tonumber(storage.totalBytes)
            local usedTypes  = tonumber(storage.usedTypes) or 0
            local totalTypes = tonumber(storage.totalTypes)

            gpu.setForeground(C.white)
            gpu.set(rightX, y, "Диски:")
            y = y + 1

            if totalBytes and totalBytes > 0 and storage.estimated ~= true then
                local pct = percentOf(usedBytes, totalBytes)
                local color = C.ok
                if pct > 95 then color = C.danger
                elseif pct >= 80 then color = C.admin end
                if y <= lastRow then
                    gpu.setForeground(color)
                    gpu.set(rightX, y, progressBar(pct, 12) .. " " .. tostring(pct) .. "% " ..
                        formatSize(usedBytes) .. " / " .. formatSize(totalBytes))
                    y = y + 1
                end
            elseif y <= lastRow then
                gpu.setForeground(C.muted)
                gpu.set(rightX, y, formatSize(usedBytes) .. " (оценка)")
                y = y + 1
            end

            if y <= lastRow then
                local typesText = tostring(usedTypes)
                if totalTypes and totalTypes > 0 then
                    typesText = typesText .. " / " .. tostring(totalTypes)
                end
                gpu.setForeground(C.white)
                gpu.set(rightX, y, "Типов: ")
                gpu.setForeground(C.ok)
                gpu.set(rightX + 8, y, typesText)
                y = y + 1
            end
        end
    end

    -- Инфо-блок в правой колонке: время работы ПК (moderator+) и текущий игрок
    if y < top + 7 then y = top + 7 end
    gpu.setForeground(C.title)
    gpu.set(rightX, y, "Сеанс")
    y = y + 1

    if showStats then
        gpu.setForeground(C.white)
        gpu.set(rightX, y, "Время ПК:")
        gpu.setForeground(C.ok)
        local okUp, up = pcall(computer.uptime)
        gpu.set(rightX + 18, y, formatUptime(okUp and up or 0))
        y = y + 1
    end

    gpu.setForeground(C.white)
    gpu.set(rightX, y, "Игрок:")
    if state.currentPlayer then
        gpu.setForeground(C.ok)
        gpu.set(rightX + 18, y, tostring(state.currentPlayer))
    else
        gpu.setForeground(C.muted)
        gpu.set(rightX + 18, y, "нет")
    end

    -- ===== Центр-низ: последние события =====
    local evY = top + 7
    if evY > lastRow then evY = lastRow end

    gpu.setForeground(C.title)
    gpu.set(leftX, evY, "Последние события")
    evY = evY + 1

    local logs = state.logs or {}
    local shown = 0
    -- Строки событий ограничиваем шириной левой колонки, чтобы не залезать
    -- на блок «Сеанс» в правой колонке.
    local evMaxW = leftW
    for i = 1, #logs do
        if shown >= 4 then break end
        local e = logs[i]
        local verb = ACTION_VERB[e.action] or ACTION_LABEL[e.action] or tostring(e.action or "?")
        local when
        local t = tonumber(e.time)
        if e.timeText then
            when = tostring(e.timeText)
        elseif t and t > 0 then
            local okD, d = pcall(os.date, "%H:%M", t)
            when = okD and d or "--:--"
        else
            when = "--:--"
        end
        local line = string.format("[%s] %s: %s", when, tostring(e.player or "?"), verb)
        if unicode.len(line) > evMaxW then line = unicode.sub(line, 1, evMaxW - 3) .. "..." end
        gpu.setForeground(C.fg)
        gpu.set(leftX, evY, line)
        evY = evY + 1
        shown = shown + 1
    end
    if shown == 0 then
        gpu.setForeground(C.muted)
        gpu.set(leftX, evY, "Событий пока нет")
    end

    -- ===== Кнопки внизу =====
    for _, b in ipairs(ui.getDashboardLayout(W, H)) do
        local bg = C.btn
        if b.action == "deposit" then bg = C.warning end
        if b.action == "refresh" then bg = C.ok end
        ui.drawButton(b.x, b.y, b.w, b.text, false, bg)
    end

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

function ui.drawModal(W, H, item, qty, mode, canAction, isAdmin, reason)
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
    gpu.set(mx + sourceX, my + 5, math.floor(tonumber(item.size) or 0) .. " шт.")
    
    gpu.setForeground(C.white); gpu.set(mx + 2, my + 7, "Количество:")
    ui.drawButton(mx + 2, my + 9, 6, "-10", false)
    ui.drawButton(mx + 9, my + 9, 6, "-1", false)
    gpu.setForeground(C.ok)
    local q = math.floor(tonumber(qty) or 0) .. " шт."
    gpu.set(mx + 17, my + 9, string.rep(" ", math.max(0, 10 - unicode.len(q))) .. q)
    ui.drawButton(mx + 29, my + 9, 6, "+1", false)
    ui.drawButton(mx + 36, my + 9, 6, "+10", false)

    -- Технические детали предмета (Raw ID / Damage / NBT)
    ui.drawButton(mx + 2, my + 11, 10, "[i] Инфо", false, C.title)
    
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
    
    -- Красная пометка справа от кнопки действия, если действовать нельзя.
    -- Рисуем в той же строке, чтобы не затирать нижнюю рамку окна.
    if not canAction and reason then
        local hint = tostring(reason)
        local room = mw - 24
        if room > 0 then
            if unicode.len(hint) > room then hint = unicode.sub(hint, 1, room - 3) .. "..." end
            gpu.setForeground(C.err)
            gpu.set(mx + 21, my + mh - 2, hint)
        end
    end
    
    -- Кнопка лимита (только для админа, над «ЗАКРЫТЬ»; для крафта не нужна)
    if isAdmin and not isCraft then
        local th = db.getThresholds()[item.name]
        local limText = "Лимит:" .. tostring(th and th.min or "Нет")
        ui.drawButton(mx + mw - 20, my + mh - 3, 18, limText, false, C.limit)
    end
    
    ui.drawButton(mx + mw - 14, my + mh - 2, 12, "ЗАКРЫТЬ", false, C.danger)
end

-- ===== Экран загрузки (boot.lua) =====
-- opts = {
--   status = "Проверка обновлений...",  -- текст статуса
--   progress = 60,                      -- 0..100 (nil — бар не рисуется)
--   logs = { "строка", ... },           -- последние строки журнала
--   version = "v1.11.0",                -- версия внизу
-- }
function ui.drawBootScreen(W, H, opts)
    opts = opts or {}
    local status = tostring(opts.status or "")
    local progress = opts.progress
    local logs = opts.logs or {}
    local version = tostring(opts.version or config.version or "")

    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
    gpu.fill(1, 1, W, H, " ")

    -- Логотип ME-CONTROL: большой ASCII-арт на широких экранах,
    -- компактный текст на узких (например, 80x25).
    local artY = 2
    local logoHeight
    if W >= 100 then
        local art = {
            " __  __ ___    ___ ___  _  _ _____ ___  _   ___  _ ",
            "|  \\/  | __|  / __/ _ \\| \\| |_   _/ _ \\| | | _ \\| |",
            "| |\\/| | _|  | (_| (_) | .` | | || (_) | |_|   /| |",
            "|_|  |_|___|  \\___\\___/|_|\\_| |_| \\___/|___|_|_\\|_|",
        }
        gpu.setForeground(C.title)
        for i, line in ipairs(art) do
            local draw = line
            if unicode.len(draw) > W - 2 then draw = unicode.sub(draw, 1, W - 2) end
            local ax = math.floor((W - unicode.len(draw)) / 2) + 1
            if ax < 1 then ax = 1 end
            gpu.set(ax, artY + i - 1, draw)
        end
        logoHeight = #art
    else
        -- Компактный логотип: разреженные буквы, гарантированно влезает в W
        local logo = "M E - C O N T R O L"
        if unicode.len(logo) > W - 2 then logo = "ME-CONTROL" end
        if unicode.len(logo) > W - 2 then logo = unicode.sub(logo, 1, math.max(1, W - 2)) end
        gpu.setForeground(C.title)
        local lx = math.floor((W - unicode.len(logo)) / 2) + 1
        if lx < 1 then lx = 1 end
        gpu.set(lx, artY, logo)
        logoHeight = 1
    end

    local y = artY + logoHeight + 1

    -- Статус (цвет по смыслу сообщения)
    local color = C.fg
    if status:find("актуальна", 1, true) or status:find("завершено", 1, true)
        or status:find("Все файлы на месте", 1, true) then
        color = C.ok
    elseif status:find("Доступно обновление", 1, true) then
        color = C.admin
    elseif status:find("Ошибка", 1, true) or status:find("Нет связи", 1, true)
        or status:find("Отсутствует", 1, true) then
        color = C.err
    elseif status:find("Проверка", 1, true) or status:find("Загрузка", 1, true) then
        color = C.title
    end
    gpu.setForeground(color)
    local st = status
    if unicode.len(st) > W - 2 then st = unicode.sub(st, 1, W - 5) .. "..." end
    local stX = math.floor((W - unicode.len(st)) / 2) + 1
    if stX < 1 then stX = 1 end
    gpu.set(stX, y, st)
    y = y + 2

    -- Прогресс-бар (если задан)
    if progress ~= nil then
        local pct = math.floor(tonumber(progress) or 0)
        if pct < 0 then pct = 0 end
        if pct > 100 then pct = 100 end
        local barW = 30
        if barW > W - 12 then barW = W - 12 end
        if barW < 5 then barW = 5 end
        local filled = math.floor(pct / 100 * barW + 0.5)
        if filled < 0 then filled = 0 end
        if filled > barW then filled = barW end
        local bar = "[" .. string.rep("█", filled) .. string.rep("░", barW - filled) .. "]"
        local bx = math.floor((W - unicode.len(bar)) / 2) + 1
        if bx < 1 then bx = 1 end
        gpu.setForeground(C.ok)
        gpu.set(bx, y, bar)
        gpu.setForeground(C.fg)
        gpu.set(bx + unicode.len(bar) + 1, y, tostring(pct) .. "%")
        y = y + 2
    end

    -- Логи (последние, что влезают над строкой версии).
    -- На стандартных экранах (>=50x16) область вмещает >=8 строк. Если строк
    -- больше, показываем последние N и итог "... и ещё X файлов" (серым).
    local bottomLimit = H - 1
    local avail = bottomLimit - y + 1
    if avail > 0 and #logs > 0 then
        local shown = math.min(#logs, avail)
        local hidden = #logs - shown
        if hidden > 0 then
            -- Оставляем одну строку под итог
            shown = math.max(0, avail - 1)
            hidden = #logs - shown
        end
        local startIdx = #logs - shown + 1
        for i = startIdx, #logs do
            local line = tostring(logs[i] or "")
            if unicode.len(line) > W - 4 then line = unicode.sub(line, 1, W - 7) .. "..." end
            local ry = y + (i - startIdx)
            if ry <= bottomLimit then
                local lc = C.muted
                if line:find("^%[OK%]") or line:find("^Все файлы на месте") then
                    lc = C.ok
                elseif line:find("^%[MISS%]") or line:find("^Отсутствует") then
                    lc = C.err
                elseif line:find("ОШИБКА", 1, true) then
                    lc = C.err
                end
                gpu.setForeground(lc)
                gpu.set(3, ry, line)
            end
        end
        if hidden > 0 then
            local summary = "... и ещё " .. hidden .. " файлов"
            if unicode.len(summary) > W - 4 then summary = unicode.sub(summary, 1, W - 7) .. "..." end
            local ry = y + shown
            if ry <= bottomLimit then
                gpu.setForeground(C.muted)
                gpu.set(3, ry, summary)
            end
        end
    end

    -- Версия внизу
    gpu.setForeground(C.muted)
    local vt = "ME-Control " .. version
    if unicode.len(vt) > W - 2 then vt = unicode.sub(vt, 1, W - 5) .. "..." end
    local vtX = math.floor((W - unicode.len(vt)) / 2) + 1
    if vtX < 1 then vtX = 1 end
    gpu.set(vtX, H, vt)

    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

return ui
