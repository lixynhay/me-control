-- medit.lua — простой текстовый редактор для OpenComputers.
-- Запуск:  medit <файл>   (например: medit test.lua)
-- Если файл существует — он загружается, иначе редактор открывается пустым.
--
-- Горячие клавиши:
--   Ctrl+S (код 31)  — сохранить файл в текущую директорию
--   Ctrl+Q (код 16)  — выйти (с предупреждением, если есть несохранённые правки)
--   Ctrl+F (код 33)  — поиск по тексту (Enter — найти, Esc — отмена)
--   Ctrl+Z (код 44)  — отменить последнее действие (Undo)
--   Ctrl+Y (код 21)  — повторить отменённое действие (Redo)
--   Ctrl+G (код 34)  — переход к строке (Enter — перейти, Esc — отмена)
--   Esc              — то же, что Ctrl+Q
--
-- Навигация: стрелки, PageUp/PageDown, Home/End, клик мышью по тексту.
-- Мышь: колесо (scroll) прокручивает текст; клик ставит курсор в позицию.
-- Ввод: обычные символы и цифры, Enter — новая строка с умным отступом,
-- Backspace — удаление (с поддержкой UTF-8, включая кириллицу).
--
-- Undo/Redo: история до 50 действий; новое действие очищает Redo.
-- Умный отступ: после then/do/function/{/(/repeat Enter добавляет 4 пробела,
-- а при вводе end/else/elseif/}/)/until отступ автоматически убирается.
--
-- Перерисовка ограничена по частоте (throttling): не чаще одного кадра
-- в 0.05 секунды — при зажатой клавише видеокарта не перегружается.
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

-- Undo / Redo: снимки состояния до каждого изменения текста.
local undoStack, redoStack = {}, {}
local UNDO_LIMIT = 50

-- Переход к строке (Ctrl+G)
local gotoMode = false
local gotoQuery = ""

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
    undoStack, redoStack = {}, {}
    gotoMode, gotoQuery = false, ""
    searchMatch = nil
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

-- ===== Undo / Redo =====
-- Снимок состояния: копия массива строк + позиция курсора. Строки в Lua
-- неизменяемы, поэтому копии массива достаточно (глубокая копия не нужна).
local function snapshot()
    local copy = {}
    for i = 1, #lines do copy[i] = lines[i] end
    return { lines = copy, cy = cy, cx = cx }
end

-- Сохраняет состояние перед изменением текста. Новое действие сбрасывает Redo.
local function pushUndo()
    undoStack[#undoStack + 1] = snapshot()
    if #undoStack > UNDO_LIMIT then table.remove(undoStack, 1) end
    redoStack = {}
end

local function restoreSnapshot(s)
    if not s then return end
    local copy = {}
    for i = 1, #s.lines do copy[i] = s.lines[i] end
    lines = copy
    cy, cx = s.cy or 1, s.cx or 0
    clampCursor()          -- курсор в пределах длины строки
    dirty = true
    searchMatch = nil
end

local function undo()
    if #undoStack == 0 then
        setStatus("Отменять нечего", false, 3)
        return
    end
    redoStack[#redoStack + 1] = snapshot()
    restoreSnapshot(table.remove(undoStack))
    setStatus("Отменено", false, 3)
end

local function redo()
    if #redoStack == 0 then
        setStatus("Повторять нечего", false, 3)
        return
    end
    undoStack[#undoStack + 1] = snapshot()
    if #undoStack > UNDO_LIMIT then table.remove(undoStack, 1) end
    restoreSnapshot(table.remove(redoStack))
    setStatus("Повторено", false, 3)
end

-- ===== Умные отступы =====
-- Строка до курсора заканчивается на then/do/function/repeat/{/( ?
local function needsIndent(before)
    local s = before:gsub("%s+$", "")
    if s == "" then return false end
    -- %f[%w] — граница слова, чтобы "todo" не считался за "do".
    if s:match("%f[%w]then$") or s:match("%f[%w]do$")
        or s:match("%f[%w]function$") or s:match("%f[%w]repeat$") then
        return true
    end
    local last = s:sub(-1)
    return last == "{" or last == "("
end

local CLOSERS = {
    ["end"] = true, ["else"] = true, ["elseif"] = true,
    ["until"] = true, ["}"] = true, [")"] = true,
}

-- После ввода закрывающего слова/скобки в начале строки убирает один
-- отступ (4 пробела), сдвигая строку влево.
local function maybeDedent()
    local line = lines[cy]
    local before = usub(line, 1, cx)
    local indent, word = before:match("^( +)([%a_]+)$")
    if not word then
        indent, word = before:match("^( +)([})])$")
    end
    if not word or not CLOSERS[word] then return end
    local n = #indent
    if n < 4 then return end
    -- Не сдвигаем, если дальше идёт продолжение слова (например, "ending").
    local rest = usub(line, cx + 1, ulen(line))
    if rest ~= "" and rest:match("^[%w_]") then return end
    lines[cy] = indent:sub(1, n - 4) .. usub(line, n + 1, ulen(line))
    cx = cx - 4
end

local function insertChar(ch)
    pushUndo()
    local line = lines[cy]
    lines[cy] = usub(line, 1, cx) .. ch .. usub(line, cx + 1, ulen(line))
    cx = cx + ulen(ch)
    dirty = true
end

local function newline()
    pushUndo()
    local line = lines[cy]
    local left = usub(line, 1, cx)
    local right = usub(line, cx + 1, ulen(line))
    -- Умный отступ: после then/do/function/{/(/repeat новая строка начинается
    -- с 4 пробелов. Отступ переносится и на правую часть (если курсор в середине).
    local indent = needsIndent(left) and "    " or ""
    lines[cy] = left
    table.insert(lines, cy + 1, indent .. right)
    cy = cy + 1
    cx = ulen(indent)
    dirty = true
end

local function backspace()
    if cx == 0 and cy <= 1 then return end
    pushUndo()
    if cx > 0 then
        local line = lines[cy]
        lines[cy] = usub(line, 1, cx - 1) .. usub(line, cx + 1, ulen(line))
        cx = cx - 1
    else
        local prev = lines[cy - 1]
        local n = ulen(prev)
        lines[cy - 1] = prev .. lines[cy]
        table.remove(lines, cy)
        cy = cy - 1
        cx = n
    end
    dirty = true
end

local function deleteForward()
    local line = lines[cy]
    if cx >= ulen(line) and cy >= #lines then return end
    pushUndo()
    if cx < ulen(line) then
        lines[cy] = usub(line, 1, cx) .. usub(line, cx + 2, ulen(line))
    else
        lines[cy] = line .. lines[cy + 1]
        table.remove(lines, cy + 1)
    end
    dirty = true
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

-- ===== Throttling перерисовки (защита видеокарты) =====
-- Не чаще одного кадра в MIN_REDRAW_DT секунд; если пришло слишком много
-- key_down/scroll подряд — кадр откладывается и рисуется по таймауту.
local MIN_REDRAW_DT = 0.05
local redrawPending = false
local lastDrawAt = -1

-- ===== Статус-бар (последняя строка H) =====
local function drawStatusBar()
    local bar
    if searching then
        bar = " Поиск: " .. searchQuery .. "_   (Enter — найти, Esc — отмена)"
    elseif gotoMode then
        bar = " Перейти к строке: " .. gotoQuery .. "_   (Enter — перейти, Esc — отмена)"
    elseif statusMsg and computer.uptime() < statusUntil then
        bar = " " .. statusMsg
    else
        bar = string.format(" Стр: %d, Кол: %d | Файл: %s%s | Ctrl+S - Сохранить, Ctrl+Q - Выйти",
            cy, cx + 1, dirty and "[*] " or "", fname)
    end
    bar = clip(bar, W)
    local pad = W - ulen(bar)
    if pad > 0 then bar = bar .. string.rep(" ", pad) end

    gpu.setBackground(C.tab_active or 0x0055AA)
    if statusErr and not searching and statusMsg and computer.uptime() < statusUntil then
        gpu.setForeground(0xFFB0B0)
    else
        gpu.setForeground(C.white)
    end
    gpu.set(1, H, bar)   -- полную строку пишем одним set (без очистки — меньше мерцания)
    gpu.setBackground(C.bg)
    gpu.setForeground(C.fg)
end

-- ===== Кадр редактора =====
-- Порядок отрисовки: очистка ТОЛЬКО текстовой области (1..H-1) → текст →
-- подсветка поиска → курсор → в самом конце статус-бар (строка H не затирается).
local function drawEditor()
    local viewH = H - 1
    lastDrawAt = computer.uptime()

    -- Держим курсор в видимой области
    if cy < topLine then topLine = cy end
    if cy > topLine + viewH - 1 then topLine = cy - viewH + 1 end
    if topLine < 1 then topLine = 1 end
    local maxTop = #lines - viewH + 1
    if maxTop < 1 then maxTop = 1 end
    if topLine > maxTop then topLine = maxTop end
    if cx < leftCol then leftCol = cx end
    if cx > leftCol + TEXT_W - 1 then leftCol = cx - TEXT_W + 1 end
    if leftCol < 0 then leftCol = 0 end

    gpu.setBackground(C.bg)
    gpu.fill(1, 1, W, H - 1, " ")   -- очищаем только текстовую область (1..H-1)

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

    -- Курсор — инверсией цвета (символ под курсором, либо пробел в конце строки).
    -- Только в текстовой области: строка <= H-1.
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

    -- Статус-бар рисуется в самом конце
    drawStatusBar()
end

-- Запрос перерисовки с ограничением частоты (throttling)
local function requestDraw()
    if computer.uptime() - lastDrawAt >= MIN_REDRAW_DT then
        redrawPending = false
        drawEditor()
    else
        redrawPending = true   -- кадр отложен до таймаута event.pull
    end
end

-- ===== Прокрутка колесом мыши (scroll) =====
-- Сигнатура события: scroll(screenAddress, x, y, direction, playerName),
-- direction: 1 — вверх, -1 — вниз.
local SCROLL_STEP = 3
local function handleScroll(direction)
    if direction ~= 1 and direction ~= -1 then return end
    local viewH = H - 1
    local maxTop = math.max(1, #lines - viewH + 1)

    topLine = topLine - direction * SCROLL_STEP   -- 1 = вверх, -1 = вниз
    if topLine < 1 then topLine = 1 end
    if topLine > maxTop then topLine = maxTop end

    -- Курсор остаётся в зоне видимости
    if cy < topLine then cy = topLine end
    if cy > topLine + viewH - 1 then cy = topLine + viewH - 1 end

    clampCursor()
    searchMatch = nil
    requestDraw()
end

-- ===== Клик мышью по тексту (touch) =====
-- Сигнатура события: touch(screenAddress, x, y, button, playerName).
-- Клик правее поля номеров строк ставит курсор в соответствующую позицию.
local function handleTouch(x, y)
    x, y = tonumber(x) or 0, tonumber(y) or 0
    if y < 1 or y > H - 1 then return end   -- статус-бар и низ экрана
    if x < TEXT_X then return end           -- поле номеров строк

    local li = topLine + (y - 1)
    if li < 1 or li > #lines then return end
    local col = leftCol + (x - TEXT_X)

    cy, cx = li, col
    clampCursor()          -- курсор в пределах длины строки
    searchMatch = nil
    quitArmed = false
    requestDraw()
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
    requestDraw()
end

-- Ввод номера строки (режим Ctrl+G)
local function handleGotoKey(char, code)
    if code == 1 then                          -- Esc — отменить
        gotoMode = false
        gotoQuery = ""
        setStatus("Переход к строке отменён", false, 3)
    elseif code == 28 then                     -- Enter — перейти
        local n = tonumber(gotoQuery)
        gotoMode = false
        gotoQuery = ""
        if n then
            if n < 1 then n = 1 end
            if n > #lines then n = #lines end
            cy = n
            cx = 0
            clampCursor()
            -- Прокрутка: строка по центру видимой области
            local viewH = H - 1
            local maxTop = math.max(1, #lines - viewH + 1)
            topLine = cy - math.floor(viewH / 2)
            if topLine < 1 then topLine = 1 end
            if topLine > maxTop then topLine = maxTop end
            searchMatch = nil
            setStatus("Строка " .. n, false, 3)
        else
            setStatus("Неверный номер строки", true, 3)
        end
    elseif code == 14 then                     -- Backspace — стереть цифру
        local n = ulen(gotoQuery)
        if n > 0 then gotoQuery = usub(gotoQuery, 1, n - 1) end
    elseif char >= 48 and char <= 57 then      -- только цифры (не больше 9)
        if ulen(gotoQuery) < 9 then gotoQuery = gotoQuery .. uchar(char) end
    end
    requestDraw()
end

local function handleKey(char, code)
    -- В режиме поиска весь ввод идёт в строку поиска
    if searching then
        handleSearchKey(char, code)
        return
    end
    -- В режиме перехода к строке — только цифры/Enter/Esc
    if gotoMode then
        handleGotoKey(char, code)
        return
    end

    -- Ctrl+F — открыть поиск (Ctrl даёт управляющий символ < 32)
    if code == 33 and char < 32 then
        searching = true
        searchQuery = ""
        requestDraw()
        return
    end

    -- Ctrl+G — переход к строке
    if code == 34 and char < 32 then
        gotoMode = true
        gotoQuery = ""
        requestDraw()
        return
    end

    -- Ctrl+Z — отменить
    if code == 44 and char < 32 then
        undo()
        requestDraw()
        return
    end
    -- Ctrl+Y — повторить
    if code == 21 and char < 32 then
        redo()
        requestDraw()
        return
    end

    -- Ctrl+S — сохранить (Ctrl даёт управляющий символ < 32)
    if code == 31 and char < 32 then
        saveFile()
        requestDraw()
        return
    end
    -- Ctrl+Q — выйти
    if code == 16 and char < 32 then
        tryQuit()
        if running then requestDraw() end
        return
    end
    -- Esc — попытка выхода
    if code == 1 then
        tryQuit()
        if running then requestDraw() end
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
        maybeDedent()              -- закрывающее слово/скобка в начале строки
    end

    requestDraw()
end

-- ===== Запуск =====
loadFile()
drawEditor()

local okRun, errRun = pcall(function()
    while running do
        local ev, _, p2, p3, p4 = event.pull(0.05)
        if ev == "key_down" then
            handleKey(tonumber(p2) or 0, tonumber(p3) or 0)
        elseif ev == "touch" then
            handleTouch(p2, p3)
        elseif ev == "scroll" then
            handleScroll(tonumber(p4) or 0)
        elseif ev == nil then
            -- Таймаут: если кадр был отложен throttling'ом — рисуем его сейчас
            if redrawPending then
                redrawPending = false
                drawEditor()
            end
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
