-- Сброс кэша модулей проекта: обновления через getcode подхватываются без перезагрузки
package.loaded["ui"] = nil
package.loaded["me_api"] = nil
package.loaded["db"] = nil
package.loaded["config"] = nil
package.loaded["locale"] = nil
package.loaded["locale_generated"] = nil

local component = require("component")
local event = require("event")
local unicode = require("unicode")
local computer = require("computer")
local filesystem = require("filesystem")
local gpu = component.gpu

local config = require("config")
local ui = require("ui")
local api = require("me_api")
local db = require("db")
local updater = require("updater")

if not component.isAvailable("me_interface") or not component.isAvailable("pim") then
    print("Ошибка: ME Interface или PIM не найден!") os.exit()
end

db.load()
pcall(function() gpu.setResolution(gpu.maxResolution()) end)

-- Принудительный инвертированный режим касания (если экран это поддерживает)
if component.isAvailable("screen") then
    pcall(function() component.screen.setTouchModeInverted(true) end)
end

local okRes, resW, resH = pcall(function() return gpu.getResolution() end)
local W = (okRes and tonumber(resW)) or 80
local H = (okRes and tonumber(resH)) or 25

local state = {
    items = {}, page = 1, totalPages = 1, selectedItem = nil, quantity = 1,
    currentTab = "DASH", player = nil, currentPlayer = nil, isAdmin = false, canModerate = false, adminList = {},
    statusMsg = "", statusErr = false, statusLevel = "ok",
    notifications = {},
    networkInfo = {},
    storageInfo = nil,
    energyHistory = {},
    craftables = {},
    craftPage = 1,
    lastCraftStatus = nil,
    lastCraftCheck = 0,
    monitorStatus = {},
    lastUpdate = 0,
    alertActive = false,
    lastBeep = 0,
    lastAlertCheck = 0,
    lastAutoCraftCheck = 0,
    lastAutoCrafts = {},
    searchQuery = "",
    isSearching = false,
    sortMode = "alpha",
    originalItems = {},
    logs = {},
    logsPage = 1,
    logsTotalPages = 1,
    lastBanCheck = 0,
    isBanned = false,
    banInfo = nil,
    canCraftTab = false,    -- роль >= user: видна ли вкладка «Крафт»
    canCraftAction = false, -- роль + глобальный флаг: можно ли заказывать
    globalRestrictions = {}, -- расшифровки сработавших глобальных запретов
    showRestrictions = false,
    dashMode = "net",        -- «Главная» для admin+: "net" (сеть) | "system" (система)
    drives = {},             -- список дисководов МЭ (для admin+)
    drivePage = 1,           -- страница блока «Диски»
    systemInfo = {},         -- uptime/память/латентность API для секции «Система»
    healthHistory = {},      -- последние строки /home/healthcheck.history (разобранные)
    healthDirty = true,      -- принудительно перечитать историю
    lastHealthLoad = 0,
    showHistory = false,      -- открыта личная история операций
    historyEntries = {},
    showItemInfo = false,     -- открыты детали предмета (Raw ID / NBT)
    itemInfo = nil,
    showLimitModal = false,   -- открыта настройка лимита/автокрафта (admin+)
    limitItem = nil,
    limitMin = 0,
    limitAutoCraft = true,
    thresholds = {},          -- лимиты/автокрафт по предметам (для маркеров [A]/[L])
    adminTarget = nil,
    isTechAdmin = false,
    banReasonText = "",
    logSearchQuery = "",
    isLogSearching = false,
    logFilter = "all",
    logClearArmed = false,
    logClearTime = 0,
    originalLogs = {},
    updateLogs = {},
    isUpdating = false,
    isUpdateFinished = false,
    dirty = true,        -- true = нужна перерисовка экрана
    lastRender = 0       -- uptime последней отрисовки (троттлинг ~10 кадров/с)
}

-- ===== Статус-бар =====
-- Уровни сообщений: "ok" (по умолчанию), "err", "warn", "info".
-- Для ok/err/warn автоматически подставляется префикс, чтобы все сообщения
-- были в едином стиле: [OK] / [ОШИБКА] / [ВНИМАНИЕ].
local STATUS_PREFIX = { ok = "[OK] ", err = "[ОШИБКА] ", warn = "[ВНИМАНИЕ] " }
local STATUS_COLOR  = { ok = config.colors.ok, err = config.colors.err,
                        warn = config.colors.admin, info = config.colors.title }

local function normalizeLevel(level)
    -- Совместимость: раньше вторым аргументом был boolean isError
    if level == true then return "err" end
    if level == false or level == nil then return "ok" end
    if level == "error" then return "err" end
    if level == "warning" then return "warn" end
    if STATUS_PREFIX[level] or level == "info" then return level end
    return "ok"
end

local function setStatus(msg, level)
    local lvl = normalizeLevel(level)
    msg = tostring(msg or "")

    local prefix = STATUS_PREFIX[lvl]
    if prefix and not msg:find("^%[") then
        msg = prefix .. msg
    end

    -- Обрезаем длинные сообщения, чтобы не вылезали за экран
    if unicode.len(msg) > W - 5 then
        msg = unicode.sub(msg, 1, W - 8) .. "..."
    end

    state.statusMsg = msg
    state.statusLevel = lvl
    state.statusErr = (lvl == "err")

    -- Мгновенная отрисовка статуса (если drawScreen не будет вызван сразу)
    gpu.setBackground(config.colors.bg)
    gpu.fill(1, H - 1, W, 1, " ")
    gpu.setForeground(STATUS_COLOR[lvl] or config.colors.ok)
    gpu.set(3, H - 1, msg)
end

-- ===== Плавающие уведомления (toasts) =====
local TOAST_LIFETIME = 4      -- секунд
local TOAST_MAX = 5           -- одновременно в очереди

local function addToast(text, toastType)
    local lvl = normalizeLevel(toastType)
    local list = state.notifications
    list[#list + 1] = {
        text = tostring(text or ""),
        type = lvl,
        time = computer.uptime(),
    }
    while #list > TOAST_MAX do table.remove(list, 1) end
end

-- Убирает устаревшие уведомления. Возвращает true, если что-то удалили.
local function pruneToasts()
    local list = state.notifications
    local now = computer.uptime()
    local changed = false
    for i = #list, 1, -1 do
        if now - (tonumber(list[i].time) or 0) > TOAST_LIFETIME then
            table.remove(list, i)
            changed = true
        end
    end
    return changed
end

-- Статус-бар + всплывающее уведомление одним вызовом
local function notify(msg, level)
    setStatus(msg, level)
    addToast(msg, level)
    -- Сразу показываем плашку, не дожидаясь следующей перерисовки
    pcall(ui.drawToasts, W, H, state.notifications)
end

-- ===== Автокрафт по лимитам =====
-- Раз в AUTO_CRAFT_INTERVAL секунд проверяем лимиты и, если предмет просел
-- ниже минимума, заказываем недостающее (до 1 стака за раз). Повторный запрос
-- на тот же предмет отправляем не чаще, чем раз в AUTO_CRAFT_COOLDOWN секунд.
local AUTO_CRAFT_INTERVAL = tonumber(config.autoCraft and config.autoCraft.interval) or 10   -- период проверки
local AUTO_CRAFT_COOLDOWN = tonumber(config.autoCraft and config.autoCraft.cooldown) or 60  -- защита от спама
local AUTO_CRAFT_STACK    = tonumber(config.autoCraft and config.autoCraft.maxStack) or 64  -- максимум за запрос

-- Ищет доступный рецепт по имени предмета (кэш state.craftables, при
-- необходимости подгружает список из МЭ).
local function findCraftableByName(itemName)
    if not itemName then return nil end
    local list = state.craftables
    if not list or #list == 0 then
        list = api.getCraftables()
        state.craftables = list
    end
    for _, c in ipairs(list) do
        if c and c.name == itemName then return c end
    end
    return nil
end

-- Одна итерация автокрафта. Возвращает true, если был отправлен хотя бы один запрос.
local function runAutoCraft()
    local status = api.getThresholdStatus()
    local now = computer.uptime()
    local sent = false

    for _, item in ipairs(status) do
        -- autoCraft == false — лимит есть, но автокрафт для предмета выключен
        if item and item.isOk == false and item.autoCraft ~= false then
            local craftable = findCraftableByName(item.name)
            if craftable then
                local last = tonumber(state.lastAutoCrafts[item.name]) or -math.huge
                if now - last >= AUTO_CRAFT_COOLDOWN then
                    local diff = (tonumber(item.min) or 0) - (tonumber(item.current) or 0)
                    if diff < 1 then diff = 1 end
                    local amount = diff > AUTO_CRAFT_STACK and AUTO_CRAFT_STACK or diff

                    local ok = api.autoCraft(craftable, amount)
                    if ok then
                        state.lastAutoCrafts[item.name] = now
                        sent = true
                        local name = tostring(craftable.display or craftable.label or item.label or item.name)
                        notify("Автокрафт: запущен " .. name .. " x" .. math.floor(amount), "info")
                    end
                    -- Если CPU занят / нет ресурсов — молча ждём следующей итерации
                    -- (каунтдаун НЕ ставим, чтобы попробовать снова через 10 секунд).
                end
            end
        end
    end
    return sent
end

-- Применяет поисковый фильтр к уже загруженному списку (без повторного обращения к МЭ/PIM).
-- Сортировка применяется ПОСЛЕ фильтрации, иначе режимы конфликтуют.
local function applySearchFilter()
    local source
    if state.searchQuery == "" then
        source = state.originalItems
    else
        local q = unicode.lower(state.searchQuery)
        local filtered = {}
        for _, it in ipairs(state.originalItems) do
            local hay = unicode.lower((it.display or "") .. "|" .. (it.label or ""))
            if hay:find(q, 1, true) then
                table.insert(filtered, it)
            end
        end
        source = filtered
    end

    -- Копия, чтобы не менять порядок в originalItems
    local list = {}
    for i, it in ipairs(source) do list[i] = it end

    state.items = api.sortItems(list, state.sortMode)

    state.totalPages = math.max(1, math.ceil(#state.items / math.max(1, H - 10)))
    if state.page > state.totalPages then state.page = state.totalPages end
end

-- Фильтр журнала: по типу операции (все / взяли / сдали) и по поисковой строке
local function applyLogSearchFilter()
    local q = unicode.lower(state.logSearchQuery or "")
    local filter = state.logFilter or "all"
    local filtered = {}

    for _, e in ipairs(state.originalLogs) do
        local action = tostring(e.action or "")
        local matchType = (filter == "all") or (action == filter)
        if matchType then
            if q == "" then
                filtered[#filtered + 1] = e
            else
                local p = unicode.lower(tostring(e.player or ""))
                local it = unicode.lower(tostring(e.item or ""))
                local a = unicode.lower(action)
                if p:find(q, 1, true) or it:find(q, 1, true) or a:find(q, 1, true) then
                    filtered[#filtered + 1] = e
                end
            end
        end
    end

    state.logs = filtered
    state.logsTotalPages = math.max(1, math.ceil(#state.logs / math.max(1, H - 12)))
    if state.logsPage > state.logsTotalPages then state.logsPage = state.logsTotalPages end
    if state.logsPage < 1 then state.logsPage = 1 end
end

-- ===== История healthcheck для секции «Система» =====
local HEALTH_HISTORY_PATH = "/home/healthcheck.history"
local HEALTH_HISTORY_ROWS = 5
local HEALTH_HISTORY_TTL = 10   -- секунд между авто-перечитываниями файла

-- Читает последние N строк истории и разбирает их.
-- Нет файла / ошибка чтения -> пустой список (UI покажет «История пуста»).
-- Битая строка -> { broken = true } (UI покажет ERR, панель не падает).
local function readHealthHistory(limit)
    limit = math.floor(tonumber(limit) or HEALTH_HISTORY_ROWS)
    if limit <= 0 then return {} end

    local rows = {}
    pcall(function()
        if not filesystem.exists(HEALTH_HISTORY_PATH) then return end
        local f = io.open(HEALTH_HISTORY_PATH, "r")
        if not f then return end
        local content = f:read("*a")
        f:close()
        if not content or content == "" then return end

        local lines = {}
        for line in content:gmatch("[^\r\n]+") do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" then lines[#lines + 1] = line end
        end

        local start = #lines - limit + 1
        if start < 1 then start = 1 end
        for i = start, #lines do
            rows[#rows + 1] = ui.parseHealthcheckLine(lines[i])
        end
    end)
    return rows
end

-- Текущие метрики ПК для секции «Система».
-- totalMemory/freeMemory могут отсутствовать на старых сборках -> nil, UI покажет «нет данных».
local function collectSystemInfo(apiMs)
    local sys = {
        uptime = 0,
        memFreeKb = nil,
        memTotalKb = nil,
        apiMs = apiMs,
        activeAutoCrafts = 0,
        config = db.getConfig() or {},
    }
    local okUp, up = pcall(computer.uptime)
    if okUp then sys.uptime = tonumber(up) or 0 end
    pcall(function()
        sys.memTotalKb = tonumber(computer.totalMemory())
        sys.memFreeKb = tonumber(computer.freeMemory())
    end)
    local okCount, count = pcall(api.countActiveAutoCrafts)
    if okCount then sys.activeAutoCrafts = tonumber(count) or 0 end
    return sys
end

local function updateList(force)
    -- force=true — принудительно обновить TTL-кэш предметов МЭ
    if force then api.getNetworkItems(true) end
    -- Лимиты нужны для маркеров [A]/[L] в списках предметов
    state.thresholds = db.getThresholds() or {}
    if state.currentTab == "DASH" then
        -- «Главная»: сводка по сети + журнал. Статистика AE2 и системные
        -- метрики добавляются только соответствующим ролям.
        state.items = {}
        local t0 = computer.uptime()
        state.networkInfo = api.getNetworkInfo()
        local apiMs = (computer.uptime() - t0) * 1000
        state.networkInfo.crafting = api.getCraftingInfo()
        state.logs = db.getLogs()

        if state.canModerate then
            state.storageInfo = api.getStorageInfo()
            state.networkInfo.storage = state.storageInfo
        end

        if state.isAdmin then
            state.systemInfo = collectSystemInfo(apiMs)
            state.drives = api.getDrivesInfo() or {}

            local now = computer.uptime()
            if state.healthDirty or (now - (state.lastHealthLoad or 0)) >= HEALTH_HISTORY_TTL then
                state.healthHistory = readHealthHistory(HEALTH_HISTORY_ROWS)
                state.lastHealthLoad = now
                state.healthDirty = false
            end
        end
    elseif state.currentTab == "ME" then
        state.items = api.getNetworkItems()
    elseif state.currentTab == "INV" then
        if api.isPlayerPresent() then
            state.items = api.getPlayerInventory()
        else
            state.items = {}
        end
    elseif state.currentTab == "ADMIN" then
        -- Конвертируем таблицу в сортированный массив для стабильного отображения
        local raw = db.getAllPlayers()
        state.adminList = {}
        for name, data in pairs(raw) do
            table.insert(state.adminList, {name = name, data = data})
        end
        table.sort(state.adminList, function(a, b) return a.name < b.name end)
    elseif state.currentTab == "CRAFT" and state.canCraftTab then
        state.items = {}
        state.craftables = api.getCraftables()
        state.totalPages = math.max(1, math.ceil(#state.craftables / math.max(1, H - 10)))
        if state.craftPage > state.totalPages then state.craftPage = state.totalPages end
        if state.craftPage < 1 then state.craftPage = 1 end

        -- Диагностика: пустой список крафтов не должен оставаться «немым»
        if #state.craftables == 0 then
            local errText = _G.last_craft_error
            if not errText or errText == "" then
                errText = "рецепты не найдены (МЭ пуста или нет шаблонов)"
            end
            setStatus("Крафты не найдены: " .. tostring(errText), "err")
        end
    elseif state.currentTab == "MON" then
        state.items = {}
        state.monitorStatus = api.getThresholdStatus()
    elseif state.currentTab == "LOGS" then
        state.items = {}
        state.originalLogs = db.getLogs()
        applyLogSearchFilter()
    elseif state.currentTab == "UPD" then
        -- Вкладка «Обновление» данных из МЭ не читает — рисуется ui.drawUpdater
        state.items = {}
    end
    
    -- Поиск/фильтр по названию (только для ME/INV)
    if state.currentTab == "ME" or state.currentTab == "INV" then
        state.originalItems = state.items
        applySearchFilter()
    else
        state.originalItems = {}
    end
    
    if state.currentTab ~= "ADMIN" and state.currentTab ~= "CRAFT" then
        state.totalPages = math.max(1, math.ceil(#state.items / math.max(1, H - 10)))
        if state.page > state.totalPages then state.page = state.totalPages end
    end
end

-- Собирает расшифровки глобальных запретов (allowUser* == false).
-- Пустой список = ограничений нет, индикатор в шапке не рисуется.
local function collectGlobalRestrictions()
    local list = {}
    local cfg = db.getConfig() or {}
    if cfg.allowUserWithdraw == false then
        list[#list + 1] = "Забор предметов запрещён"
    end
    if cfg.allowUserDeposit == false then
        list[#list + 1] = "Сдача предметов запрещена"
    end
    if cfg.allowUserCraft == false then
        list[#list + 1] = "Крафт отключён администратором"
    end
    return list
end

local function drawScreen()
    if state.isBanned then
        ui.drawBannedScreen(W, H, state.banInfo)
        return
    end
    local level = state.player and db.getRoleLevel(state.player) or config.LEVEL_BANNED
    state.canCraftTab = level >= config.LEVEL_USER
    state.canCraftAction = state.canCraftTab and api.canCraft(state.player)
    state.globalRestrictions = collectGlobalRestrictions()
    if #state.globalRestrictions == 0 then state.showRestrictions = false end
    if state.currentTab == "CRAFT" and not state.canCraftTab then
        state.currentTab = "DASH"
        state.selectedItem = nil
        updateList()
        notify("Крафт доступен с роли user", "err")
    end
    ui.drawMain(W, H, state)
    -- Окно управления игроком (роль / права / статистика) поверх админки
    if state.currentTab == "ADMIN" and state.adminTarget then
        local pd = db.getPlayer(state.adminTarget)
        local banned, banInfo = db.checkBan(state.adminTarget)
        ui.drawAdminBan(W, H, state.adminTarget, {
            text = state.banReasonText or "",
            role = pd and pd.role or "?",
            perms = {
                canWithdraw = pd and pd.canWithdraw ~= false,
                canDeposit  = pd and pd.canDeposit ~= false,
                canCraft    = pd and pd.canCraft ~= false,
            },
            ban = {
                banned = banned or (pd and pd.role == "banned") or false,
                reason = (banInfo and banInfo.reason) or (pd and pd.banReason) or "",
                expires = (banInfo and banInfo.expires) or (pd and pd.banExpires) or 0,
            },
            totalActions = pd and pd.totalActions or 0,
            lastSeen = pd and pd.lastSeen or 0,
            history = db.getLogsForPlayer(state.adminTarget, 5),
        })
    end
    -- Модальное окно предмета (ME / INV / CRAFT). Рисуется и здесь, чтобы отложенная
    -- перерисовка по dirty-флагу не стирала уже открытую карточку.
    if state.selectedItem then
        local isCraft = (state.currentTab == "CRAFT")
        local canAct = (isCraft and state.canCraftAction)
            or (state.currentTab == "ME" and api.canWithdraw(state.player))
            or (state.currentTab == "INV" and api.canDeposit(state.player))
        local reason
        if isCraft and not canAct then
            -- Роль есть, значит действовать мешает глобальный флаг.
            reason = state.canCraftTab and "Глобальный запрет" or "Крафт доступен с роли user"
        end
        ui.drawModal(W, H, state.selectedItem, state.quantity or 1, state.currentTab,
            canAct and true or false, state.isAdmin, reason)
    end
    -- Плавающие уведомления поверх всего
    ui.drawToasts(W, H, state.notifications)
    -- Личная история операций игрока
    if state.showHistory then
        ui.drawPlayerHistory(W, H, state.player or state.currentPlayer, state.historyEntries)
    end
    -- Детали предмета (Raw ID / Damage / NBT) + «Настроить лимит» для admin+
    if state.showItemInfo and state.itemInfo then
        ui.drawItemInfo(W, H, state.itemInfo, state.isAdmin)
    end
    -- Лимит и автокрафт предмета (admin+)
    if state.showLimitModal and state.limitItem then
        ui.drawLimitModal(W, H, state.limitItem.name, {
            label = state.limitItem.display or state.limitItem.label,
            current = state.limitItem.size,
            min = state.limitMin,
            autoCraft = state.limitAutoCraft,
        })
    end
    -- Расшифровка глобальных запретов — самый верхний слой
    if state.showRestrictions then
        ui.drawRestrictions(W, H, state.globalRestrictions)
    end
    -- После отрисовки основного экрана принудительно рисуем статус, чтобы он не исчез
    gpu.setBackground(config.colors.bg)
    gpu.fill(1, H - 1, W, 1, " ")
    local lvl = state.statusLevel or (state.statusErr and "err" or "ok")
    gpu.setForeground(STATUS_COLOR[lvl] or config.colors.ok)
    gpu.set(3, H - 1, state.statusMsg)
end

-- Отмечает экран «грязным». Реальная перерисовка выполняется в главном цикле
-- (см. блок throttling перед event.pull) не чаще одного кадра в 0.1 с.
local function requestRedraw()
    state.dirty = true
end

-- Переключение вкладки: сброс страницы, выбранного предмета и открытых окон.
-- Используется и кликами по вкладкам, и горячими клавишами F1–F6.
local function canCraftRole(playerName)
    if not playerName then return false end
    return (db.getRoleLevel(playerName) or config.LEVEL_BANNED) >= config.LEVEL_USER
end

-- Меняет роль цели на один уровень вверх/вниз (step = +1 / -1).
-- Возвращает ok, newRole|err. Иерархию проверяет db.setRole.
local function changeRoleByStep(targetName, step)
    local pd = db.getPlayer(targetName)
    if not pd then return false, "Игрок не найден" end

    local curLevel = db.ROLE_LEVELS[pd.role] or 0
    local newLevel = curLevel + step
    if newLevel < config.LEVEL_GUEST then
        return false, "Ниже guest нельзя (используйте ЗАБАНИТЬ)"
    end

    local newRole
    for role, lvl in pairs(db.ROLE_LEVELS) do
        if lvl == newLevel then newRole = role; break end
    end
    if not newRole then return false, "Нет такой роли" end

    local ok, err = db.setRole(state.player, targetName, newRole)
    if not ok then return false, tostring(err or "Не удалось изменить роль") end
    return true, newRole
end

local function switchTab(tabId)
    if tabId == nil or tabId == state.currentTab then return false end
    state.canCraftTab = canCraftRole(state.player)
    state.canCraftAction = state.canCraftTab and api.canCraft(state.player)
    if tabId == "CRAFT" and not state.canCraftTab then
        setStatus("Крафт доступен с роли user", "err")
        return false
    end
    state.currentTab = tabId
    state.page = 1
    state.craftPage = 1
    state.selectedItem = nil
    state.adminTarget = nil
    state.banReasonText = ""
    state.isSearching = false
    state.isLogSearching = false
    state.logClearArmed = false
    -- При входе на «Главную» запрашиваем свежий журнал и историю healthcheck
    if tabId == "DASH" then
        state.logs = db.getLogs()
        state.healthDirty = true
    end
    updateList(); requestRedraw()
    return true
end

-- ===== Вкладка «Обновление» =====
local UPDATE_LOG_MAX = 200

-- Запуск обновления из GitHub. Доступно только на вкладке UPD (для админов).
local function startUpdate()
    if state.isUpdating then return end
    state.isUpdating = true
    state.isUpdateFinished = false
    state.updateLogs = {}
    drawScreen()   -- обновление идёт синхронно: рисуем журнал сразу, а не по флагу

    local ok, res = updater.run(function(text)
        state.updateLogs[#state.updateLogs + 1] = tostring(text)
        while #state.updateLogs > UPDATE_LOG_MAX do table.remove(state.updateLogs, 1) end
        drawScreen()
    end)

    state.isUpdating = false
    state.isUpdateFinished = true
    if ok then
        state.updateLogs[#state.updateLogs + 1] = "Готово: " .. tostring(res or "")
        notify("Обновление завершено. Нажмите «ПЕРЕЗАПУСТИТЬ»", "ok")
    else
        state.updateLogs[#state.updateLogs + 1] = "ОШИБКА: " .. tostring(res or "неизвестно")
        notify("Ошибка обновления: " .. tostring(res or ""), "err")
    end
    drawScreen()
end

-- Перезапуск панели: гарантируем автозапуск boot.lua в /home/.shrc, затем shutdown(true)
local function restartPanel()
    local shrc = "/home/.shrc"
    local text = ""
    local f = io.open(shrc, "r")
    if f then
        text = f:read("*a") or ""
        f:close()
    end
    if text:find("main.lua", 1, true) then
        -- Заменяем старый автозапуск main.lua на boot.lua
        text = text:gsub("main%.lua", "boot.lua")
        local w = io.open(shrc, "w")
        if w then w:write(text); w:close() end
    elseif not text:find("boot.lua", 1, true) then
        local w = io.open(shrc, "a")
        if w then
            if text ~= "" and text:sub(-1) ~= "\n" then w:write("\n") end
            w:write("boot.lua\n")
            w:close()
        end
    end
    computer.shutdown(true)
end

local initialPlayer
if component.isAvailable("pim") then
    local okIP, name = pcall(function() return component.pim.getInventoryName() end)
    if okIP then initialPlayer = name end
end
if initialPlayer and initialPlayer ~= "" then
    state.player = initialPlayer
    state.currentPlayer = initialPlayer
    local pData = db.getPlayer(state.player)
    if pData then
        state.isAdmin = db.isAdmin(state.player)
        state.canModerate = db.isModerator(state.player)
        state.isTechAdmin = (pData.role == "techadmin")
        state.canCraftTab = canCraftRole(state.player)
        state.canCraftAction = state.canCraftTab and api.canCraft(state.player)
    end
    local banned, banInfo = db.checkBan(state.player)
    if banned then
        state.isBanned = true
        state.banInfo = banInfo
    end
end

-- Подсказка о горячих клавишах при запуске
state.statusMsg = "F1–F3, F5–F6 — вкладки, / — поиск, 1/2/3 — фильтр журнала"
state.statusLevel = "info"
state.statusErr = false

updateList(); drawScreen()
state.dirty = false
state.lastRender = computer.uptime()

local success, err = pcall(function()
while true do
    -- Оповещения: проверяем лимиты не чаще раза в секунду
    if computer.uptime() - (state.lastAlertCheck or 0) > 1 then
        state.alertActive = api.hasAlert()
        state.lastAlertCheck = computer.uptime()
    end
    local alertActive = state.alertActive
    
    -- Звуковой сигнал (раз в 5 секунд, чтобы не бесить)
    if alertActive and config.alerts.sound then
        if computer.uptime() - (state.lastBeep or 0) > 5 then
            computer.beep(1000, 0.1) -- Высокий писк
            state.lastBeep = computer.uptime()
        end
    end
    
    -- Сигнал редстоуна (если компонент есть)
    if component.isAvailable("redstone") and config.alerts.redstone then
        local rs = component.redstone
        rs.setOutput(config.alerts.redstoneSide, alertActive and 15 or 0)
    end
    
    -- Отслеживание статуса последнего крафта (раз в 2 секунды)
    if state.lastCraftStatus ~= nil and computer.uptime() - (state.lastCraftCheck or 0) > 2 then
        state.lastCraftCheck = computer.uptime()
        local st = api.getCraftStatus(state.lastCraftStatus)
        if st then
            if st.failed == true then
                notify("Крафт провален: не хватает ресурсов или занят CPU", "err")
                state.lastCraftStatus = nil
            elseif st.done == true then
                notify("Крафт завершён")
                state.lastCraftStatus = nil
                -- Обновляем список/статистику, чтобы показать новые предметы
                if state.currentTab == "CRAFT" or state.currentTab == "ME" then
                    updateList(); requestRedraw()
                end
            elseif st.canceled == true then
                notify("Крафт отменён", "warn")
                state.lastCraftStatus = nil
            end
        else
            -- Объект статуса больше не читается — прекращаем слежение
            state.lastCraftStatus = nil
        end
    end

    -- Проверка истечения бана раз в 5 секунд
    if state.isBanned and computer.uptime() - (state.lastBanCheck or 0) > 5 then
        state.lastBanCheck = computer.uptime()
        if state.banInfo and state.banInfo.expires and state.banInfo.expires > 0 then
            local okT, now = pcall(os.time)
            now = okT and tonumber(now) or nil
            if now and now >= state.banInfo.expires then
                db.unbanPlayer(nil, state.player)
                state.isBanned = false
                state.banInfo = nil
                setStatus("Срок бана истёк, доступ восстановлен")
                updateList(); requestRedraw()
            end
        end
    end
    
    -- Автокрафт по лимитам: раз в 10 секунд (можно отключить в config.autoCraft.enabled)
    if (config.autoCraft == nil or config.autoCraft.enabled ~= false)
        and computer.uptime() - (state.lastAutoCraftCheck or 0) > AUTO_CRAFT_INTERVAL then
        state.lastAutoCraftCheck = computer.uptime()
        -- Ошибку автокрафта не пробрасываем в главный цикл: просто ждём следующей попытки
        pcall(runAutoCraft)
    end

    -- Отрисовка по «грязному» флагу: не чаще одного кадра в 0.1 с (~10 FPS).
    -- Так быстрый ввод (мышь/клавиатура) не заставляет видеокарту рисовать 100 раз в секунду.
    if state.dirty and (computer.uptime() - state.lastRender > 0.1) then
        drawScreen()
        state.dirty = false
        state.lastRender = computer.uptime()
    end

    -- Ловим все события; фильтрация выполняется ниже по eventName
    local eventName, p1, p2, p3, p4, p5 = event.pull(0.1)
    if eventName == "interrupted" then break end

    -- Убираем устаревшие всплывающие уведомления (живут 4 секунды)
    if #state.notifications > 0 and pruneToasts() then
        requestRedraw()
    end
    
    -- Автообновление дашборда и монитора раз в 2 секунды
    -- (не трогаем открытую карточку предмета)
    if state.selectedItem == nil and (state.currentTab == "MON" or state.currentTab == "DASH") and computer.uptime() - state.lastUpdate > 2 then
        updateList()

        -- Точка для графика энергии (только там, где он рисуется: moderator+)
        if state.currentTab == "DASH" and state.canModerate and state.networkInfo then
            local eStored = tonumber(state.networkInfo.energyStored)
            local eMax = tonumber(state.networkInfo.energyMax)
            if eStored and eMax and eMax > 0 then
                local pct = eStored / eMax * 100
                if pct < 0 then pct = 0 end
                if pct > 100 then pct = 100 end
                table.insert(state.energyHistory, pct)
                while #state.energyHistory > 20 do
                    table.remove(state.energyHistory, 1)
                end
            end
        end

        requestRedraw()
        state.lastUpdate = computer.uptime()
    end
    
    if eventName == "player_on" then
        state.player = tostring(p1)
        state.currentPlayer = state.player
        local pData = db.getPlayer(state.player)
        local isNew = false

        if not pData then
            db.registerPlayer(state.player)
            pData = db.getPlayer(state.player)
            isNew = true
        end

        state.isAdmin = db.isAdmin(state.player)
        state.canModerate = db.isModerator(state.player)
        state.isTechAdmin = pData and (pData.role == "techadmin") or false
        state.canCraftTab = canCraftRole(state.player)
        state.canCraftAction = state.canCraftTab and api.canCraft(state.player)

        if isNew then
            notify("Новый игрок: " .. state.player)
        else
            notify("С возвращением, " .. state.player)
        end

        -- Проверка бана
        local banned, banInfo = db.checkBan(state.player)
        if banned then
            state.isBanned = true
            state.banInfo = banInfo
            state.selectedItem = nil
            setStatus("Доступ запрещён: вы забанены", "err")
            requestRedraw()
        else
            state.isBanned = false
            state.banInfo = nil
            if state.isTechAdmin then
                notify("Вы вошли как Технический Администратор")
            elseif state.isAdmin then
                notify("Вы вошли как администратор")
            end
            state.currentTab = "DASH"
            updateList(); requestRedraw()
        end
        
    elseif eventName == "player_off" then
        state.player = nil
        state.currentPlayer = nil
        state.isAdmin = false
        state.canModerate = false
        state.canCraftTab = false
        state.canCraftAction = false
        state.isBanned = false
        state.banInfo = nil
        state.adminTarget = nil
        state.isTechAdmin = false
        state.banReasonText = ""
        state.isLogSearching = false
        state.currentTab = "DASH"
        state.selectedItem = nil -- Закрываем открытую карточку при уходе игрока
        state.page = 1
        setStatus("Пользователь покинул PIM", "warn")
        updateList(); requestRedraw()
        
    elseif eventName == "key_down" then
        local keyCode = tonumber(p3) or 0
        local charCode = tonumber(p2) or 0

        -- Коды клавиш из /lib/core/full_keyboard.lua OpenOS:
        --   F1=59 (0x3B) … F6=64 (0x40), "/"=53 (0x35)
        -- F4 свободна: вкладки «Статистика» больше нет (её блоки переехали
        -- на «Главную»). Пустые клавиши не занимаем.
        local function keyToTab(code)
            if code == 59 then return "DASH" end    -- F1
            if code == 60 then return "ME" end      -- F2
            if code == 61 then return "INV" end     -- F3
            if code == 63 then return "CRAFT" end   -- F5
            if code == 64 then return "MON" end     -- F6
            return nil
        end

        -- Режимы ввода текста (там "/" — обычный символ, а не хоткей)
        local typingText = state.isSearching or state.isLogSearching or (state.adminTarget ~= nil)
        local hotkeyTab = keyToTab(keyCode)

        if hotkeyTab then
            -- F1–F6: переключение вкладок (работает в любом режиме).
            -- Доступ к крафту перечитывается из БД в switchTab.
            local needsModeration = (hotkeyTab == "LOGS" or hotkeyTab == "ADMIN")
            if needsModeration and not state.canModerate then
                setStatus("Недостаточно прав: раздел доступен администратору", "err")
            else
                switchTab(hotkeyTab)
            end
        elseif (keyCode == 53 or charCode == 47) and not typingText then
            -- «/» — быстрый поиск (аналог кнопки «ПОИСК»)
            if state.currentTab == "LOGS" then
                state.isLogSearching = true
                state.logSearchQuery = ""
                applyLogSearchFilter(); requestRedraw()
            elseif state.currentTab == "ME" or state.currentTab == "INV" then
                state.isSearching = true
                state.searchQuery = ""
                applySearchFilter(); requestRedraw()
            else
                setStatus("Поиск доступен на вкладках: МЭ-сеть, Инвентарь, Журнал", "warn")
            end

        elseif (keyCode == 2 or keyCode == 3 or keyCode == 4) and not typingText
               and state.currentTab == "LOGS" then
            -- 1 / 2 / 3 — фильтр журнала: все / взяли / сдали
            local map = { [2] = "all", [3] = "take", [4] = "put" }
            local names = { all = "все операции", take = "только выдача", put = "только сдача" }
            local newFilter = map[keyCode]
            if newFilter and newFilter ~= state.logFilter then
                state.logFilter = newFilter
                state.logsPage = 1
                applyLogSearchFilter(); requestRedraw()
                setStatus("Фильтр журнала: " .. (names[newFilter] or newFilter))
            end

        elseif state.adminTarget and state.currentTab == "ADMIN" then
            local code = tonumber(p3) or 0
            if code == 28 then
                -- Enter: забанить навсегда с введённой причиной
                local reason = state.banReasonText
                if reason == "" then reason = "Без причины" end
                local okB, bErr = db.banPlayer(state.player, state.adminTarget, reason, 0)
                if okB then
                    notify("Игрок " .. state.adminTarget .. " забанен")
                else
                    notify(tostring(bErr or "Не удалось забанить игрока"), "err")
                end
                state.adminTarget = nil
                state.banReasonText = ""
                updateList(); requestRedraw()
            elseif code == 1 then
                -- Esc: закрыть окно
                state.adminTarget = nil
                state.banReasonText = ""
                requestRedraw()
            elseif code == 14 then
                local n = unicode.len(state.banReasonText)
                if n > 0 then state.banReasonText = unicode.sub(state.banReasonText, 1, n - 1) end
                requestRedraw()
            else
                local ch
                if type(p2) == "number" and p2 > 0 then
                    ch = unicode.char(p2)
                elseif type(p2) == "string" and unicode.len(p2) == 1 then
                    ch = p2
                end
                if ch and ch ~= "" then
                    state.banReasonText = state.banReasonText .. ch
                    requestRedraw()
                end
            end
        elseif state.isLogSearching then
            local code = tonumber(p3) or 0
            if code == 28 then
                -- Enter: сохранить фильтр и выйти
                state.isLogSearching = false
                applyLogSearchFilter(); requestRedraw()
            elseif code == 1 then
                -- Esc: сбросить фильтр
                state.isLogSearching = false
                state.logSearchQuery = ""
                applyLogSearchFilter(); requestRedraw()
            elseif code == 14 then
                local n = unicode.len(state.logSearchQuery)
                if n > 0 then state.logSearchQuery = unicode.sub(state.logSearchQuery, 1, n - 1) end
                applyLogSearchFilter(); requestRedraw()
            else
                local ch
                if type(p2) == "number" and p2 > 0 then
                    ch = unicode.char(p2)
                elseif type(p2) == "string" and unicode.len(p2) == 1 then
                    ch = p2
                end
                if ch and ch ~= "" then
                    state.logSearchQuery = state.logSearchQuery .. ch
                    applyLogSearchFilter(); requestRedraw()
                end
            end
        elseif state.isSearching then
            local code = tonumber(p3) or 0
            if code == 28 or code == 1 then
                -- Enter (28) — применить фильтр и выйти; Esc (1) — выйти и сбросить
                state.isSearching = false
                if code == 1 then state.searchQuery = "" end
                applySearchFilter(); requestRedraw()
            elseif code == 14 then
                -- Backspace
                local n = unicode.len(state.searchQuery)
                if n > 0 then state.searchQuery = unicode.sub(state.searchQuery, 1, n - 1) end
                applySearchFilter(); requestRedraw()
            else
                -- p2 в key_down — КОД символа (число), а не строка; в старых версиях может быть строкой
                local ch
                if type(p2) == "number" and p2 > 0 then
                    ch = unicode.char(p2)
                elseif type(p2) == "string" and unicode.len(p2) == 1 then
                    ch = p2
                end
                if ch and ch ~= "" then
                    state.searchQuery = state.searchQuery .. ch
                    applySearchFilter(); requestRedraw()
                end
            end
        end
        
    elseif eventName == "touch" then
        -- Для touch p2 - это X, p3 - это Y, p5 - имя игрока
        local x, y = p2, p3
        local clickPlayer = p5
        
        -- Кнопка «ВЫХОД» — только для админа (доступна даже без игрока на PIM)
        if y == H - 2 and x >= W - 20 and x < W - 5 then
            if not state.isAdmin then
                setStatus("Недостаточно прав: выключение доступно администратору", "err")
            else
                setStatus("Завершение работы панели…", "info"); os.sleep(0.5); break
            end
        end
        
        -- Клик по индикатору ограничений в шапке (работает и без игрока на PIM)
        local restrictionsRect = (#state.globalRestrictions > 0) and ui.getRestrictionsLayout(W) or nil
        local onRestrictions = restrictionsRect ~= nil
            and y == restrictionsRect.y
            and x >= restrictionsRect.x and x < restrictionsRect.x + restrictionsRect.w

        -- Забанен — все действия заблокированы (кроме ВЫХОД, обработанного выше)
        if state.isBanned then
            -- ничего не делаем
        elseif state.showRestrictions then
            -- Открыта расшифровка глобальных запретов: закрываем по кнопке или клику вне окна
            local L = ui.getRestrictionsModalLayout(W, H, #state.globalRestrictions)
            local onClose = x >= L.close.x and x < L.close.x + L.close.w and y == L.close.y
            local inside = x >= L.mx and x < L.mx + L.mw and y >= L.my and y < L.my + L.mh
            if onClose or not inside then
                state.showRestrictions = false
                requestRedraw()
            end
        elseif onRestrictions then
            state.showRestrictions = true
            requestRedraw()
        elseif state.showHistory then
            -- Личная история: закрытие по кнопке или клику вне окна
            local L = ui.getPlayerHistoryLayout(W, H, math.max(#state.historyEntries, 1))
            local onClose = x >= L.close.x and x < L.close.x + L.close.w and y == L.close.y
            local inside = x >= L.mx and x < L.mx + L.mw and y >= L.my and y < L.my + L.mh
            if onClose or not inside then
                state.showHistory = false
                requestRedraw()
            end
        elseif state.showLimitModal and state.limitItem then
            -- Настройка лимита/автокрафта: самый верхний слой над «Деталями»
            local L = ui.getLimitModalLayout(W, H)
            local function hit(r) return x >= r.x and x < r.x + r.w and y == r.y end

            if hit(L.minus10) then
                state.limitMin = math.max(0, state.limitMin - 10)
                requestRedraw()
            elseif hit(L.minus1) then
                state.limitMin = math.max(0, state.limitMin - 1)
                requestRedraw()
            elseif hit(L.plus1) then
                state.limitMin = state.limitMin + 1
                requestRedraw()
            elseif hit(L.plus10) then
                state.limitMin = state.limitMin + 10
                requestRedraw()
            elseif hit(L.toggle) then
                state.limitAutoCraft = not state.limitAutoCraft
                requestRedraw()
            elseif hit(L.save) then
                local item = state.limitItem
                local okSave, saveErr = db.setThreshold(state.player, item.name,
                    item.display or item.label, state.limitMin, state.limitAutoCraft)
                if okSave then
                    notify("Лимит сохранён: " .. tostring(item.display or item.label) ..
                        " — минимум " .. tostring(state.limitMin) ..
                        (state.limitAutoCraft and ", автокрафт ВКЛ" or ", автокрафт ВЫКЛ"))
                    state.showLimitModal = false
                    state.limitItem = nil
                else
                    notify(tostring(saveErr or "Не удалось сохранить лимит"), "err")
                end
                updateList(); requestRedraw()
            else
                local onClose = hit(L.close)
                local inside = x >= L.mx and x < L.mx + L.mw and y >= L.my and y < L.my + L.mh
                if onClose or not inside then
                    state.showLimitModal = false
                    state.limitItem = nil
                    requestRedraw()
                end
            end
        elseif state.showItemInfo then
            -- Детали предмета: кнопка лимита (admin+) либо закрытие
            local L = ui.getItemInfoLayout(W, H)
            local onClose = x >= L.close.x and x < L.close.x + L.close.w and y == L.close.y
            local onLimit = state.isAdmin and L.limit
                and x >= L.limit.x and x < L.limit.x + L.limit.w and y == L.limit.y
            local inside = x >= L.mx and x < L.mx + L.mw and y >= L.my and y < L.my + L.mh
            if onLimit then
                local th = db.getThreshold(state.itemInfo.name) or {}
                state.limitItem = state.itemInfo
                state.limitMin = math.floor(tonumber(th.min) or 0)
                state.limitAutoCraft = th.autoCraft ~= false
                state.showLimitModal = true
                requestRedraw()
            elseif onClose or not inside then
                state.showItemInfo = false
                state.itemInfo = nil
                requestRedraw()
            end
        elseif state.currentPlayer == nil then
            setStatus("Нет активного пользователя (встаньте на PIM)", "err")
        elseif clickPlayer ~= state.currentPlayer then
            setStatus("Панель занята игроком " .. tostring(state.currentPlayer), "warn")
        else
            -- Любой клик выходит из режима поиска (кнопки ПОИСК ниже включат его снова)
            state.isSearching = false
            state.isLogSearching = false

        -- Переключение вкладок
        if y == 2 then
            local layout = ui.getTabLayout(W, state.canModerate, state.isAdmin, state.canCraftTab)
            local newTab = state.currentTab
            
            for _, tab in ipairs(layout) do
                if x >= tab.x and x < tab.x + tab.w then
                    newTab = tab.id
                    break
                end
            end
            
            if newTab ~= state.currentTab then
                switchTab(newTab)
            end
            
        elseif not state.selectedItem and state.currentTab == "LOGS" and y == 4
               and state.isAdmin and x >= 3 and x < 15 then
            -- «ОЧИСТИТЬ»: первое нажатие взводит, второе (в течение 3 сек) очищает
            local now = computer.uptime()
            if state.logClearArmed and (now - (state.logClearTime or 0)) <= 3 then
                db.clearLogs()
                state.logClearArmed = false
                state.logsPage = 1
                updateList(); requestRedraw()
                notify("Журнал операций очищен")
            else
                state.logClearArmed = true
                state.logClearTime = now
                requestRedraw()
                setStatus("Нажмите «ТОЧНО?» ещё раз, чтобы очистить журнал", "warn")
            end

        elseif not state.selectedItem and state.currentTab == "LOGS" and y == 5 then
            -- Кнопки фильтра по типу операции
            for _, f in ipairs(ui.getLogFilterLayout(W)) do
                if x >= f.x and x < f.x + f.w then
                    if state.logFilter ~= f.id then
                        state.logFilter = f.id
                        state.logsPage = 1
                        applyLogSearchFilter(); requestRedraw()
                    end
                    break
                end
            end

        elseif not state.selectedItem and y == 4
               and (state.currentTab == "ME" or state.currentTab == "INV") then
            -- Клик по заголовку списка — переключение режима сортировки
            if state.sortMode == "alpha" then
                state.sortMode = "desc"
            elseif state.sortMode == "desc" then
                state.sortMode = "asc"
            else
                state.sortMode = "alpha"
            end
            state.page = 1
            updateList(); requestRedraw()
            local names = { alpha = "А-Я", asc = "по возрастанию", desc = "по убыванию" }
            setStatus("Сортировка: " .. (names[state.sortMode] or state.sortMode))

        elseif not state.selectedItem and state.currentTab == "DASH" then
            -- Переключатель «Сеть / Система» (только admin/techadmin)
            if state.isAdmin then
                for _, m in ipairs(ui.getDashModeLayout(W, H)) do
                    if y == m.y and x >= m.x and x < m.x + m.w then
                        if state.dashMode ~= m.id then
                            state.dashMode = m.id
                            if m.id == "system" then state.healthDirty = true end
                            requestRedraw()
                        end
                        break
                    end
                end
            end

            -- Блок «Диски» в режиме «Система» (admin+)
            local drivesHandled = false
            if state.isAdmin and state.dashMode == "system" then
                local DL = ui.getDrivesLayout(W, H, #state.drives, state.drivePage or 1)
                local function hitRect(r)
                    return r ~= nil and y == r.y and x >= r.x and x < r.x + r.w
                end

                if hitRect(DL.prev) then
                    drivesHandled = true
                    if DL.page > 1 then
                        state.drivePage = DL.page - 1
                        requestRedraw()
                    end
                elseif hitRect(DL.next) then
                    drivesHandled = true
                    if DL.page < DL.totalPages then
                        state.drivePage = DL.page + 1
                        requestRedraw()
                    end
                else
                    for _, slotL in ipairs(DL.drives) do
                        local d = state.drives[slotL.index]
                        if d and not drivesHandled then
                            if hitRect(slotL.plus) then
                                drivesHandled = true
                                local newPrio = (tonumber(d.priority) or 0) + 1
                                local okP, pErr = api.setDrivePriority(d.slot, newPrio)
                                if okP then
                                    notify("Приоритет диска " .. tostring(d.slot) .. ": " .. tostring(newPrio))
                                    state.drives = api.getDrivesInfo() or {}
                                else
                                    notify(tostring(pErr or "Не удалось изменить приоритет"), "err")
                                end
                                requestRedraw()
                            elseif hitRect(slotL.minus) then
                                drivesHandled = true
                                local newPrio = (tonumber(d.priority) or 0) - 1
                                local okP, pErr = api.setDrivePriority(d.slot, newPrio)
                                if okP then
                                    notify("Приоритет диска " .. tostring(d.slot) .. ": " .. tostring(newPrio))
                                    state.drives = api.getDrivesInfo() or {}
                                else
                                    notify(tostring(pErr or "Не удалось изменить приоритет"), "err")
                                end
                                requestRedraw()
                            elseif hitRect(slotL.eject) then
                                drivesHandled = true
                                local okE, eErr = api.ejectDrive(d.slot, state.player)
                                if okE then
                                    notify("Диск " .. tostring(d.slot) .. " выгружен в инвентарь")
                                    state.drives = api.getDrivesInfo() or {}
                                else
                                    notify(tostring(eErr or "Не удалось выгрузить диск"), "err")
                                end
                                requestRedraw()
                            end
                        end
                    end
                end
            end

            -- Кнопки дашборда: МЭ-СЕТЬ / СДАТЬ ВСЁ / МОИ ДЕЙСТВИЯ / ОБНОВИТЬ
            for _, b in ipairs(ui.getDashboardLayout(W, H)) do
                if drivesHandled then break end
                if y == b.y and x >= b.x and x < b.x + b.w then
                    if b.action == "net" then
                        switchTab("ME")
                    elseif b.action == "deposit" then
                        if not api.isPlayerPresent() then
                            setStatus("Нет активного пользователя (встаньте на PIM)", "err")
                        elseif not api.canDeposit(state.player) then
                            setStatus("Доступ запрещён: недостаточно прав", "err")
                        else
                            local moved, msg = api.depositAll()
                            updateList(); requestRedraw()
                            local isWarn = (moved == 0) or (msg and msg:find("ВНИМАНИЕ", 1, true) ~= nil)
                            notify(msg, isWarn and "warn" or "ok")
                        end
                    elseif b.action == "history" then
                        if not state.player then
                            setStatus("Нет активного пользователя (встаньте на PIM)", "err")
                        else
                            state.historyEntries = db.getLogs(state.player, ui.PLAYER_HISTORY_ROWS)
                            state.showHistory = true
                            requestRedraw()
                        end
                    elseif b.action == "refresh" then
                        state.lastUpdate = 0
                        state.energyHistory = {}
                        state.healthDirty = true   -- перечитать healthcheck.history
                        updateList(true); requestRedraw()
                        setStatus("Данные обновлены")
                    end
                    break
                end
            end

        elseif not state.selectedItem and y == H - 2 and state.currentTab ~= "DASH" then
            -- Нижняя панель: работает на всех вкладках (раскладка общая с ui).
            -- На «Главной» (DASH) этих кнопок нет — обработку пропускаем.
            local bottom = ui.getBottomLayout(W)
            if x >= bottom.prev.x and x < bottom.prev.x + bottom.prev.w then
                if state.currentTab == "LOGS" then
                    if state.logsPage > 1 then state.logsPage = state.logsPage - 1; requestRedraw() end
                elseif state.currentTab == "CRAFT" then
                    if state.craftPage > 1 then state.craftPage = state.craftPage - 1; requestRedraw() end
                elseif state.page > 1 then state.page = state.page - 1; requestRedraw() end
            end
            if x >= bottom.refresh.x and x < bottom.refresh.x + bottom.refresh.w then
                if state.currentTab == "UPD" then
                    startUpdate()
                else
                    state.lastUpdate = 0; updateList(true); requestRedraw(); setStatus("Данные обновлены")
                end
            end
            if x >= bottom.next.x and x < bottom.next.x + bottom.next.w then
                if state.currentTab == "LOGS" then
                    if state.logsPage < state.logsTotalPages then state.logsPage = state.logsPage + 1; requestRedraw() end
                elseif state.currentTab == "CRAFT" then
                    if state.craftPage < state.totalPages then state.craftPage = state.craftPage + 1; requestRedraw() end
                elseif state.page < state.totalPages then state.page = state.page + 1; requestRedraw() end
            end
            if bottom.search and x >= bottom.search.x and x < bottom.search.x + bottom.search.w then
                if state.currentTab == "LOGS" then
                    state.isLogSearching = true
                    state.logSearchQuery = ""
                    applyLogSearchFilter(); requestRedraw()
                elseif state.currentTab == "ME" or state.currentTab == "INV" then
                    state.isSearching = true
                    state.searchQuery = ""
                    applySearchFilter(); requestRedraw()
                end
            end
            if state.currentTab == "INV" and bottom.deposit and x >= bottom.deposit.x and x < bottom.deposit.x + bottom.deposit.w then
                if not api.isPlayerPresent() then
                    setStatus("Нет активного пользователя (встаньте на PIM)", "err")
                elseif not api.canDeposit(state.player) then
                    setStatus("Доступ запрещён: недостаточно прав", "err")
                else
                    local moved, msg = api.depositAll()
                    updateList(); requestRedraw()
                    local isWarn = (moved == 0) or (msg and msg:find("ВНИМАНИЕ", 1, true) ~= nil)
                    notify(msg, isWarn and "warn" or "ok")
                end
            end
            -- «ВЫХОД» обработан выше (только для админа)

        elseif state.currentTab == "UPD" then
            -- Кнопки вкладки «Обновление»
            local L = ui.getUpdaterLayout(W, H)
            if state.isUpdating then
                setStatus("Обновление уже идёт…", "warn")
            elseif state.isUpdateFinished then
                if x >= L.restart.x and x < L.restart.x + L.restart.w and y == L.restart.y then
                    setStatus("Перезапуск панели…", "info")
                    restartPanel()
                end
            else
                if x >= L.update.x and x < L.update.x + L.update.w and y == L.update.y then
                    startUpdate()
                end
            end

        elseif state.currentTab == "ADMIN" and state.canModerate then
            -- Окно управления игроком (бан / роль / персональные права)
            local L = ui.getAdminBanLayout(W, H)
            if state.adminTarget then
                local function inRect(r)
                    return x >= r.x and x < r.x + r.w and y == r.y
                end

                if inRect(L.withdraw) then
                    local okP, res = db.setPermission(state.player, state.adminTarget, "canWithdraw", nil)
                    if okP then
                        notify("Забор для " .. state.adminTarget .. ": " .. (res and "разрешён" or "запрещён"))
                    else
                        notify(tostring(res), "err")
                    end
                    updateList(); requestRedraw()

                elseif inRect(L.deposit) then
                    local okP, res = db.setPermission(state.player, state.adminTarget, "canDeposit", nil)
                    if okP then
                        notify("Сдача для " .. state.adminTarget .. ": " .. (res and "разрешена" or "запрещена"))
                    else
                        notify(tostring(res), "err")
                    end
                    updateList(); requestRedraw()

                elseif inRect(L.craft) then
                    local okP, res = db.setPermission(state.player, state.adminTarget, "canCraft", nil)
                    if okP then
                        notify("Крафт для " .. state.adminTarget .. ": " .. (res and "разрешён" or "запрещён"))
                    else
                        notify(tostring(res), "err")
                    end
                    updateList(); requestRedraw()

                elseif inRect(L.roleDown) then
                    local okR, res = changeRoleByStep(state.adminTarget, -1)
                    if okR then
                        notify("Роль игрока " .. state.adminTarget .. ": " .. ui.roleLabel(res))
                    else
                        notify(tostring(res), "err")
                    end
                    updateList(); requestRedraw()

                elseif inRect(L.roleUp) then
                    local okR, res = changeRoleByStep(state.adminTarget, 1)
                    if okR then
                        notify("Роль игрока " .. state.adminTarget .. ": " .. ui.roleLabel(res))
                    else
                        notify(tostring(res), "err")
                    end
                    updateList(); requestRedraw()

                elseif inRect(L.ban) then
                    local reason = state.banReasonText
                    if reason == "" then reason = "Без причины" end
                    local okB, bErr = db.banPlayer(state.player, state.adminTarget, reason, 0)
                    if okB then
                        notify("Игрок " .. state.adminTarget .. " забанен")
                    else
                        notify(tostring(bErr or "Не удалось забанить игрока"), "err")
                    end
                    state.adminTarget = nil
                    state.banReasonText = ""
                    updateList(); requestRedraw()

                elseif inRect(L.role) then
                    -- Смена роли по кругу: guest -> user -> moderator -> admin -> banned
                    local pd = db.getPlayer(state.adminTarget)
                    if pd then
                        local actorLevel = db.getRoleLevel(state.player)
                        local order = db.ROLE_ORDER
                        local idx = 0
                        for i, r in ipairs(order) do
                            if r == pd.role then idx = i end
                        end
                        local newRole = nil
                        for step = 1, #order do
                            local cand = order[(idx + step - 1) % #order + 1]
                            local lvl = db.ROLE_LEVELS[cand] or 0
                            if lvl < actorLevel then
                                newRole = cand
                                break
                            end
                        end
                        if not newRole then newRole = "banned" end

                        local okR, rErr
                        if newRole == "banned" then
                            okR, rErr = db.banPlayer(state.player, state.adminTarget, "Смена роли через админку", 0)
                        else
                            okR, rErr = db.setRole(state.player, state.adminTarget, newRole)
                        end
                        if okR then
                            notify("Роль игрока " .. state.adminTarget .. ": " .. ui.roleLabel(newRole))
                        else
                            notify(tostring(rErr or "Не удалось изменить роль"), "err")
                        end
                    end
                    updateList(); requestRedraw()

                elseif inRect(L.unban) then
                    local okU, uErr = db.unbanPlayer(state.player, state.adminTarget)
                    if okU then
                        notify("Игрок " .. state.adminTarget .. " разбанен")
                    else
                        notify("Не удалось разбанить игрока", "err")
                    end
                    updateList(); requestRedraw()

                elseif inRect(L.close) then
                    state.adminTarget = nil
                    state.banReasonText = ""
                    requestRedraw()
                end
            else
                -- Клик по строке игрока -> открыть карточку
                local row = y - 5
                if y >= 6 and y <= H - 3 and row >= 1 and state.adminList[row] then
                    state.adminTarget = state.adminList[row].name
                    state.banReasonText = ""
                    requestRedraw()
                end
            end
            
        elseif state.selectedItem then
            local mw, mh = 56, 16
            local mx, my = math.floor((W - mw) / 2) + 1, math.floor((H - mh) / 2) + 1
            local isCraft = (state.currentTab == "CRAFT")
            -- Для крафта «максимум» не ограничен количеством в сети
            local maxQty = isCraft and 1000000 or math.floor(tonumber(state.selectedItem.size) or 0)

            -- Кнопки количества
            if y == my + 9 then
                local old = state.quantity
                if x >= mx + 2 and x < mx + 8 then state.quantity = math.max(1, state.quantity - 10) end
                if x >= mx + 9 and x < mx + 15 then state.quantity = math.max(1, state.quantity - 1) end
                if x >= mx + 29 and x < mx + 35 then state.quantity = math.min(maxQty, state.quantity + 1) end
                if x >= mx + 36 and x < mx + 42 then state.quantity = math.min(maxQty, state.quantity + 10) end
                if state.quantity < 1 then state.quantity = 1 end
                if old ~= state.quantity then
                    requestRedraw()
                end
            end

            -- «[i] Инфо» — технические детали предмета
            if y == my + 11 and x >= mx + 2 and x < mx + 12 then
                state.itemInfo = state.selectedItem
                state.showItemInfo = true
                requestRedraw()
            end
            
            -- Кнопка действия
            if y == my + mh - 2 and x >= mx + 2 and x < mx + 20 then
                if isCraft then
                    -- Роль перечитываем перед каждым заказом: вкладка могла остаться
                    -- открытой после понижения роли / отключения крафта.
                    state.canCraftTab = canCraftRole(state.player)
                    state.canCraftAction = state.canCraftTab and api.canCraft(state.player)
                    if not state.canCraftTab then
                        notify("Крафт доступен с роли user", "err")
                        state.selectedItem = nil
                        requestRedraw()
                    else
                        -- «СКРАФТИТЬ»
                        local ok, res, status = api.requestCraft(state.selectedItem, state.quantity)
                        if ok then
                            state.lastCraftStatus = status
                            state.lastCraftCheck = 0
                            notify("Запрос на крафт отправлен: " .. tostring(state.selectedItem.display or state.selectedItem.label)
                                .. " x" .. math.floor(state.quantity))
                        else
                            state.lastCraftStatus = nil
                            notify("Не удалось запросить крафт: " .. tostring(res), "err")
                        end
                        state.selectedItem = nil
                        updateList(); requestRedraw()
                    end
                else
                    if not state.player then
                        setStatus("Нет активного пользователя (встаньте на PIM)", "err")
                    elseif state.currentTab == "ME" and not api.canWithdraw(state.player) then
                        setStatus("Доступ запрещён: недостаточно прав", "err")
                    elseif state.currentTab == "INV" and not api.canDeposit(state.player) then
                        setStatus("Доступ запрещён: недостаточно прав", "err")
                    else
                        local ok, msg
                        if state.currentTab == "ME" then
                            ok, msg = api.exportToPlayer(state.selectedItem, state.quantity)
                        else
                            ok, msg = api.pushFromPlayer(state.selectedItem, state.quantity)
                        end
                        notify(msg, ok and "ok" or "err")
                    end
                    state.selectedItem = nil; updateList(); requestRedraw()
                end
            end
            
            -- Закрыть
            if y == my + mh - 2 and x >= mx + mw - 14 and x < mx + mw - 2 then
                state.selectedItem = nil; requestRedraw()
            end
            
            -- Кнопка лимита (только админ, не для крафта): цикл 100 -> 1000 -> 10000 -> 100000 -> Нет
            if state.isAdmin and not isCraft and y == my + mh - 3 and x >= mx + mw - 20 and x < mx + mw - 2 then
                local thresholds = db.getThresholds()
                local cur = thresholds[state.selectedItem.name]
                local curMin = cur and cur.min or nil
                local newMin
                if curMin == nil then newMin = 100
                elseif curMin == 100 then newMin = 1000
                elseif curMin == 1000 then newMin = 10000
                elseif curMin == 10000 then newMin = 100000
                else newMin = 0 end
                
                db.setThreshold(state.player, state.selectedItem.name, state.selectedItem.label, newMin)
                requestRedraw()
            end
            
        else
            -- Клик по списку (навигация уже обработана выше)
            if y >= 5 and y <= H - 6 and x >= 3 and x <= W - 3 then
                if state.currentTab == "CRAFT" then
                    local idx = ((state.craftPage or 1) - 1) * (H - 10) + (y - 4)
                    local entry = state.craftables[idx]
                    if entry then
                        state.selectedItem = entry
                        state.quantity = 1
                        requestRedraw()
                    end
                else
                    local idx = (state.page - 1) * (H - 10) + (y - 4)
                    if (state.currentTab == "ME" or state.currentTab == "INV") and state.items[idx] then 
                        state.selectedItem = state.items[idx]
                        state.quantity = 1
                        requestRedraw()
                    end
                end
            end
        end
        end
    end
end
end)

-- Если произошла ошибка или выход, возвращаем экран в нормальное состояние
gpu.setBackground(config.colors.overlay)
gpu.setForeground(config.colors.white)
gpu.fill(1, 1, W, H, " ")
if not success then
    print("Скрипт аварийно завершился: " .. tostring(err))
else
    print("Скрипт успешно завершен.")
end
