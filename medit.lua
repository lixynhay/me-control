-- medit.lua — простой текстовый редактор для OpenComputers.
-- Запуск:  medit <файл>   (например: medit test.lua)
-- Если файл существует — он загружается, иначе редактор открывается пустым.
--
-- Горячие клавиши:
--   Ctrl+S (код 31)  — сохранить файл в текущую директорию
--   Ctrl+Q (код 16)  — выйти (с предупреждением, если есть несохранённые правки)
--   Ctrl+F (код 33)  — поиск по тексту (Enter — найти, Esc — отмена)
--   Esc              — то же, что Ctrl+Q
--
-- Навигация: стрелки, PageUp/PageDown, Home/End.
-- Ввод: обычные символы и цифры, Enter — новая строка, Backspace — удаление
-- (с поддержкой UTF-8, включая кириллицу, через библиотеку unicode).
--
-- Подсветка синтаксиса Lua (без полноценного парсера):
--   ключевые слова (local, if, then, ...) — цветом C.title (голубой);
--   комментарии (-- ... до конца строки)   — цветом C.muted (серый);
--   строки в кавычках ("..." / '...')       — цветом C.ok (зелёный).

local component = require("component")
local event = require("event")
local unicode = require("unicode")
local computer = require("computer")

-- Палитра берётся из config.colors; если config недоступен — используется встроенная.
local okCfg, config = pcall(require, "config")
local C = (okCfg and config and config.colors) or {
    bg = 0x1A1A1A, fg = 0xE0E0E0, muted = 0x888888,
    title = 0x00AAFF, white = 0xFFFFFF, danger = 0xFF5555,
    ok = 0x00AA00, tab_active = 0x0055AA,
}

local gpu = component.gpu
local W, H = gpu.getResolution()
W = tonumber(W) or 80
H = tonumber(H) or 25

-- ===== Параметры интерфейса =====
local GUTTER = 4                 -- ширина поля номеров строк
local TEXT_X = GUTTER + 2        -- первый столбец текста (6)
local TEXT_W = W - TEXT_X + 1    -- ширина области текста

if H < 3 or TEXT_W < 1 then
    print("Экран слишком мал для редактора")
    return
end

-- ===== Аргументы командной строки =====
local cliArgs = { ... }
if #cliArgs == 0 and type(arg) == "table" then
    for i = 1, #arg do cliArgs[i] = arg[i] end
end
local fname = tostring(cliArgs[1] or "untitled.txt")

-- ===== Состояние редактора =====
local lines = { "" }        -- текст хранится массивом строк
local cy, cx = 1, 0         -- курсор: строка (1..n) и позиция в ней (0 = начало)
local topLine, leftCol = 1, 0
local dirty = false         -- есть несохранённые изменения
local quitArmed = false     -- подтверждение выхода без сохранения
local statusMsg, statusErr, statusUntil = nil, false, 0
local running = true

-- Поиск (Ctrl+F)
local searching = false     -- открыто поле поиска
local searchQuery = ""      -- вводимый запрос
local searchMatch = nil     -- { line, col, len } — найденное слово (для подсветки)

-- ===== Утилиты UTF-8 =====
local function ulen(s) return unicode.len(s or "") end
local function usub(s, i, j) return unicode.sub(s or "", i, j) end
local function uchar(n) return unicode.char(n) end

local function clip(text, maxChars)
    text = text or ""
    if maxChars <= 0 then return "" end
    if ulen(text) <= maxChars then return text end
    return usub(text, 1, maxChars)
end

local function setStatus(msg, isErr, seconds)
    statusMsg = msg
    statusErr = isErr and true or false
    statusUntil = computer.uptime() + (seconds or 3)
end

-- ===== Работа с файлом =====
local function splitLines(text)
    local out = {}
    for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
        out[#out + 1] = line:gsub("\r$", "")
    end
    if #out == 0 then out[1] = "" end
    return out
end

local function loadFile()
    local f = io.open(fname, "r")
    if f then
        local data = f:read("*a") or ""
        f:close()
        lines = splitLines(data)
        setStatus("Загружено: " .. fname .. " (" .. #lines .. " стр.)", false, 4)
    else
        lines = { "" }
        setStatus("Новый файл: " .. fname, false, 4)
    end
    cy, cx = 1, 0
    topLine, leftCol = 1, 0
    dirty = false
end

local function saveFile()
    local ok, f, err = pcall(io.open, fname, "w")
    if not ok or not f then
        setStatus("Не удалось сохранить: " .. tostring(err or f), true, 6)
        return false
    end
    f:write(table.concat(lines, "\n"))
    f:close()
    dirty = false
    setStatus("Сохранено: " .. fname, false, 3)
    return true
end

-- ===== Операции редактирования =====
local function clampCursor()
    if cy < 1 then cy = 1 end
    if cy > #lines then cy = #lines end
    if cx < 0 then cx = 0 end
    local n = ulen(lines[cy])
    if cx > n then cx = n end
end

local function insertChar(ch)
    local line = lines[cy]
    lines[cy] = usub(line, 1, cx) .. ch .. usub(line, cx + 1, ulen(line))
    cx = cx + ulen(ch)
    dirty = true
end

local function newline()
    local line = lines[cy]
    local left = usub(line, 1, cx)
    local right = usub(line, cx + 1, ulen(line))
    lines[cy] = left
    table.insert(lines, cy + 1, right)
    cy = cy + 1
    cx = 0
    dirty = true
end

local function backspace()
    if cx > 0 then
        local line = lines[cy]
        lines[cy] = usub(line, 1, cx - 1) .. usub(line, cx + 1, ulen(line))
        cx = cx - 1
        dirty = true
    elseif cy > 1 then
        local prev = lines[cy - 1]
        local n = ulen(prev)
        lines[cy - 1] = prev .. lines[cy]
        table.remove(lines, cy)
        cy = cy - 1
        cx = n
        dirty = true
    end
end

local function deleteForward()
    local line = lines[cy]
    if cx < ulen(line) then
        lines[cy] = usub(line, 1, cx) .. usub(line, cx + 2, ulen(line))
        dirty = true
    elseif cy < #lines then
        lines[cy] = line .. lines[cy + 1]
        table.remove(lines, cy + 1)
        dirty = true
    end
end

-- ===== Подсветка синтаксиса Lua =====
-- Список ключевых слов рисуется цветом C.title.
local KEYWORDS = {
    ["local"] = true, ["if"] = true, ["then"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["function"] = true, ["return"] = true,
    ["for"] = true, ["while"] = true, ["do"] = true, ["in"] = true,
    ["and"] = true, ["or"] = true, ["not"] = true, ["nil"] = true,
    ["true"] = true, ["false"] = true, ["repeat"] = true, ["until"] = true,
    ["break"] = true, ["goto"] = true,
}

-- Разбивает строку на куски { text, color }. Без полноценного парсера:
--   * комментарий "-- ..." (вне строки) — до конца строки, цвет C.muted;
--   * "строка" или 'строка' (с экранированием \) — цвет C.ok;
--   * слово-ключевое слово — цвет C.title, остальное — C.fg.
local function tokenize(line)
    local segs = {}
    local n = ulen(line)
    local i = 1

    local function push(text, color)
        if text == nil or text == "" then return end
        local last = segs[#segs]
        if last and last.color == color then
            last.text = last.text .. text
        else
            segs[#segs + 1] = { text = text, color = color }
        end
    end

    while i <= n do
        local ch = usub(line, i, i)
        local c2 = usub(line, i + 1, i + 1)
        if ch == "-" and c2 == "-" then
            -- Комментарий до конца строки
            push(usub(line, i, n), C.muted)
            i = n + 1
        elseif ch == '"' or ch == "'" then
            -- Строковый литерал
            local quote = ch
            local j = i + 1
            while j <= n do
                local cj = usub(line, j, j)
                if cj == "\\" then
                    j = j + 2
                elseif cj == quote then
                    j = j + 1
                    break
                else
                    j = j + 1
                end
            end
            if j > n + 1 then j = n + 1 end
            push(usub(line, i, math.min(j - 1, n)), C.ok)
            i = j
        elseif ch:match("[%a_]") then
            -- Идентификатор или ключевое слово (целиком)
            local j = i
            while j <= n and usub(line, j, j):match("[%w_]") do j = j + 1 end
            local word = usub(line, i, j - 1)
            push(word, KEYWORDS[word] and C.title or C.fg)
            i = j
        else
            push(ch, C.fg)
            i = i + 1
        end
    end
    return segs
end

-- Рисует строку с подсветкой; пишет только видимое окно [leftCol .. leftCol+TEXT_W-1].
local function drawSyntax(row, line)
    local winStart = leftCol
    local winEnd = leftCol + TEXT_W - 1
    local base = 0 -- 0-based индекс символа в исходной строке
    for _, seg in ipairs(tokenize(line)) do
        local len = ulen(seg.text)
        local segStart = base
        local segStop = base + len - 1
        local vs = math.max(segStart, winStart)
        local ve = math.min(segStop, winEnd)
        if vs <= ve then
            gpu.setForeground(seg.color)
            gpu.set(TEXT_X + (vs - winStart), row,
                usub(seg.text, vs - segStart + 1, ve - segStart + 1))
        end
        base = base + len
        if segStart > winEnd then break end
    end
end

-- ===== Поиск (Ctrl+F) =====
-- Возвращает line (1-based) и col (0-based) первого вхождения (без учёта регистра ASCII).
local function findFirst(query)
    if query == "" then return nil end
    local q = string.lower(query)
    local m = ulen(q)
    for li = 1, #lines do
        local line = lines[li]
        local n = ulen(line)
        for ci = 0, n - m do
            if string.lower(usub(line, ci + 1, ci + m)) == q then
                return li, ci
            end
        end
    end
    return nil
end

-- ===== Отрисовка =====
local function draw()
    local viewH = H - 1

    -- Держим курсор в видимой области
    if cy < topLine then topLine = cy end
    if cy > topLine + viewH - 1 then topLine = cy - viewH + 1 end
    if topLine < 1 then topLine = 1 end
    if cx < leftCol then leftCol = cx end
    if cx > leftCol + TEXT_W - 1 then leftCol = cx - TEXT_W + 1 end
    if leftCol < 0 then leftCol = 0 end

    gpu.setBackground(C.bg)
    gpu.fill(1, 1, W, H, " ")

    -- Номера строк и текст
    for row = 1, viewH do
        local ln = topLine + row - 1
        if ln >= 1 and ln <= #lines then
            -- Поле номеров строк (ширина 4, приглушённый цвет)
            gpu.setForeground(C.muted)
            local num = tostring(ln)
            if #num > 3 then num = num:sub(-3) end
            gpu.set(1, row, string.rep(" ", 3 - #num) .. num .. " ")

            -- Текст строки с подсветкой синтаксиса Lua
            drawSyntax(row, lines[ln])
        end
    end

    -- Подсветка найденного слова (Ctrl+F) — инверсией цвета
    if searchMatch then
        local li, ci, mlen = searchMatch.line, searchMatch.col, searchMatch.len
        local hrow = li - topLine + 1
        if hrow >= 1 and hrow <= viewH then
            local vs = math.max(ci, leftCol)
            local ve = math.min(ci + mlen - 1, leftCol + TEXT_W - 1)
            if vs <= ve then
                gpu.setBackground(C.title)
                gpu.setForeground(C.bg)
                gpu.set(TEXT_X + (vs - leftCol), hrow, usub(lines[li], vs + 1, ve + 1))
                gpu.setBackground(C.bg)
                gpu.setForeground(C.fg)
            end
        end
    end

    -- Курсор — инверсией цвета (символ под курсором, либо пробел в конце строки)
    local row = cy - topLine + 1
    local col = TEXT_X + (cx - leftCol)
    if row >= 1 and row <= viewH and col >= TEXT_X and col <= W then
        local ch = usub(lines[cy], cx + 1, cx + 1)
        if ch == "" then ch = " " end
        gpu.setBackground(C.title)
        gpu.setForeground(C.bg)
        gpu.set(col, row, ch)
        gpu.setBackground(C.bg)
        gpu.setForeground(C.fg)
    end

    -- Статус-бар (последняя строка)
    gpu.setBackground(C.tab_active or 0x0055AA)
    gpu.setForeground(C.white)
    gpu.fill(1, H, W, 1, " ")

    local bar
    if searching then
        bar = " Поиск: " .. searchQuery .. "_   (Enter — найти, Esc — отмена)"
    elseif statusMsg and computer.uptime() < statusUntil then
        bar = " " .. statusMsg
        if statusErr then gpu.setForeground(0xFFB0B0) end
    else
        bar = string.format(" Стр: %d, Кол: %d | Файл: %s%s | Ctrl+S - Сохранить, Ctrl+Q - Выйти",
            cy, cx + 1, dirty and "[*] " or "", fname)
    end
    gpu.set(1, H, clip(bar, W))

    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

-- ===== Обработка клавиш =====
local function tryQuit()
    if dirty and not quitArmed then
        quitArmed = true
        setStatus("Есть несохранённые изменения! Ctrl+Q ещё раз — выйти без сохранения", true, 6)
    else
        running = false
    end
end

-- Ввод в поле поиска (режим Ctrl+F)
local function handleSearchKey(char, code)
    if code == 1 then                          -- Esc — отменить поиск
        searching = false
        searchQuery = ""
        setStatus("Поиск отменён", false, 2)
    elseif code == 28 then                     -- Enter — найти
        local li, ci = findFirst(searchQuery)
        searching = false
        if li then
            cy, cx = li, ci
            searchMatch = { line = li, col = ci, len = ulen(searchQuery) }
            setStatus("Найдено: " .. searchQuery .. " (стр. " .. li .. ")", false, 3)
        else
            searchMatch = nil
            setStatus("Не найдено: " .. searchQuery, true, 3)
        end
    elseif code == 14 then                     -- Backspace — стереть символ
        local n = ulen(searchQuery)
        if n > 0 then searchQuery = usub(searchQuery, 1, n - 1) end
    elseif code == 33 and char < 32 then       -- повторный Ctrl+F — ничего
        -- игнорируем
    elseif char >= 32 and char ~= 127 then     -- обычный символ
        searchQuery = searchQuery .. uchar(char)
    end
    draw()
end

local function handleKey(char, code)
    -- В режиме поиска весь ввод идёт в строку поиска
    if searching then
        handleSearchKey(char, code)
        return
    end

    -- Ctrl+F — открыть поиск (Ctrl даёт управляющий символ < 32)
    if code == 33 and char < 32 then
        searching = true
        searchQuery = ""
        draw()
        return
    end

    -- Ctrl+S — сохранить (Ctrl даёт управляющий символ < 32)
    if code == 31 and char < 32 then
        saveFile()
        draw()
        return
    end
    -- Ctrl+Q — выйти
    if code == 16 and char < 32 then
        tryQuit()
        if running then draw() end
        return
    end
    -- Esc — попытка выхода
    if code == 1 then
        tryQuit()
        if running then draw() end
        return
    end

    quitArmed = false
    searchMatch = nil          -- любая обычная клавиша снимает подсветку поиска

    if code == 200 then            -- Up
        cy = cy - 1; clampCursor()
    elseif code == 208 then        -- Down
        cy = cy + 1; clampCursor()
    elseif code == 203 then        -- Left
        if cx > 0 then cx = cx - 1
        elseif cy > 1 then cy = cy - 1; cx = ulen(lines[cy]) end
    elseif code == 205 then        -- Right
        if cx < ulen(lines[cy]) then cx = cx + 1
        elseif cy < #lines then cy = cy + 1; cx = 0 end
    elseif code == 201 then        -- PageUp
        cy = cy - math.max(1, H - 2); clampCursor()
    elseif code == 209 then        -- PageDown
        cy = cy + math.max(1, H - 2); clampCursor()
    elseif code == 199 then        -- Home
        cx = 0
    elseif code == 207 then        -- End
        cx = ulen(lines[cy])
    elseif code == 28 then         -- Enter
        newline()
    elseif code == 14 then         -- Backspace
        backspace()
    elseif code == 211 then        -- Delete
        deleteForward()
    elseif code == 15 then         -- Tab -> 4 пробела
        insertChar("    ")
    elseif char >= 32 and char ~= 127 then
        insertChar(uchar(char))
    end

    draw()
end

-- ===== Запуск =====
loadFile()
draw()

local okRun, errRun = pcall(function()
    while running do
        local ev, _, p2, p3 = event.pull()
        if ev == "key_down" then
            handleKey(tonumber(p2) or 0, tonumber(p3) or 0)
        elseif ev == "interrupted" or ev == "component_removed" then
            break
        end
    end
end)

-- Возвращаем экран в исходное состояние
gpu.setBackground(0x000000)
gpu.setForeground(0xFFFFFF)
gpu.fill(1, 1, W, H, " ")

if not okRun then
    print("medit: ошибка — " .. tostring(errRun))
elseif dirty then
    print("medit: выход (несохранённые изменения не записаны)")
else
    print("medit: выход")
end
