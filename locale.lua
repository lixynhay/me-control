-- locale.lua — русские названия предметов (registry id -> имя).
--
-- Ключ — это item.name (registry id), например "minecraft:iron_ingot".
-- Формат значения:
--   ["modid:item"] = "Русское имя"                    -- общий перевод
--   ["modid:item"] = { [0] = "Имя A", [1] = "Имя B", ["*"] = "По умолчанию" }  -- по damage
--
-- Если перевода нет — используется игровое название (label), как раньше.
-- Словарь можно пополнять вручную или генерировать из языковых файлов модпака
-- (assets/<modid>/lang/ru_ru.json): ключ "item.<modid>.<path>" / "block.<modid>.<path>".

local locale = {}

locale.names = {
    -- ===== vanilla (частые) =====
    ["minecraft:iron_ingot"] = "Железный слиток",
    ["minecraft:gold_ingot"] = "Золотой слиток",
    ["minecraft:copper_ingot"] = "Медный слиток",
    ["minecraft:netherite_ingot"] = "Незеритовый слиток",
    ["minecraft:diamond"] = "Алмаз",
    ["minecraft:emerald"] = "Изумруд",
    ["minecraft:coal"] = "Уголь",
    ["minecraft:charcoal"] = "Древесный уголь",
    ["minecraft:redstone"] = "Редстоун",
    ["minecraft:lapis_lazuli"] = "Лазурит",
    ["minecraft:quartz"] = "Кварц",
    ["minecraft:amethyst_shard"] = "Осколок аметиста",
    ["minecraft:stick"] = "Палка",
    ["minecraft:string"] = "Нить",
    ["minecraft:feather"] = "Перо",
    ["minecraft:gunpowder"] = "Порох",
    ["minecraft:flint"] = "Кремень",
    ["minecraft:leather"] = "Кожа",
    ["minecraft:paper"] = "Бумага",
    ["minecraft:book"] = "Книга",
    ["minecraft:apple"] = "Яблоко",
    ["minecraft:bread"] = "Хлеб",
    ["minecraft:wheat"] = "Пшеница",
    ["minecraft:carrot"] = "Морковь",
    ["minecraft:potato"] = "Картофель",
    ["minecraft:beetroot"] = "Свёкла",
    ["minecraft:torch"] = "Факел",
    ["minecraft:chest"] = "Сундук",
    ["minecraft:furnace"] = "Печь",
    ["minecraft:crafting_table"] = "Верстак",
    ["minecraft:glass"] = "Стекло",
    ["minecraft:dirt"] = "Земля",
    ["minecraft:stone"] = "Камень",
    ["minecraft:cobblestone"] = "Булыжник",
    ["minecraft:sand"] = "Песок",
    ["minecraft:gravel"] = "Гравий",
    ["minecraft:clay_ball"] = "Комок глины",
    ["minecraft:oak_log"] = "Дубовое бревно",
    ["minecraft:spruce_log"] = "Еловое бревно",
    ["minecraft:birch_log"] = "Берёзовое бревно",
    ["minecraft:oak_planks"] = "Дубовые доски",
    ["minecraft:iron_block"] = "Железный блок",
    ["minecraft:gold_block"] = "Золотой блок",
    ["minecraft:diamond_block"] = "Алмазный блок",
    ["minecraft:emerald_block"] = "Изумрудный блок",
    ["minecraft:redstone_block"] = "Блок редстоуна",
    ["minecraft:obsidian"] = "Обсидиан",
    ["minecraft:netherrack"] = "Адский камень",
    ["minecraft:end_stone"] = "Камень Края",
    ["minecraft:ender_pearl"] = "Эндер-жемчуг",
    ["minecraft:blaze_rod"] = "Огненный стержень",
    ["minecraft:slime_ball"] = "Слизь",
    ["minecraft:glowstone_dust"] = "Светопыль",
    ["minecraft:sugar"] = "Сахар",
    ["minecraft:egg"] = "Яйцо",
    ["minecraft:bucket"] = "Ведро",
    ["minecraft:water_bucket"] = "Ведро воды",
    ["minecraft:lava_bucket"] = "Ведро лавы",
    ["minecraft:coal_block"] = "Блок угля",

    -- ===== примеры для модов (замени/дополни реальными id) =====
    -- ["appliedenergistics2:certus_quartz_crystal"] = "Кристалл истинного кварца",
    -- ["appliedenergistics2:charged_certus_quartz_crystal"] = "Заряженный кристалл истинного кварца",
    -- ["appliedenergistics2:fluix_crystal"] = "Кристалл флюикса",
    -- ["appliedenergistics2:sky_stone_block"] = "Небесный камень",
}

-- itemName — registry id (name), damage — метаданные (может быть nil), fallback — игровое имя.
function locale.getName(itemName, damage, fallback)
    if not itemName then return fallback end
    local v = locale.names[itemName]
    if v == nil then return fallback end
    if type(v) == "table" then
        local d = tonumber(damage) or 0
        return v[d] or v["*"] or fallback
    end
    return v
end

return locale