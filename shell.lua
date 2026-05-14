-- advanced_shell.lua
-- Shell с поддержкой модема и дисплея для ComputerCraft

local component = require("component")
local computer = require("computer")
local term = require("term")
local event = require("event")
local fs = require("filesystem")
local shell = require("shell")
local serialization = require("serialization")

-- Конфигурация
local config = {
    prompt = "> ",
    history_file = "/home/.shell_history",
    max_history = 50,
    modem_side = nil,  -- автоматическое определение
    display_side = nil -- автоматическое определение
}

-- Состояние оболочки
local state = {
    running = true,
    current_dir = shell.getWorkingDirectory(),
    history = {},
    history_index = 0,
    background_jobs = {},
    next_job_id = 1,
    modem = nil,
    display = nil,
    display_width = 50,
    display_height = 20
}

-- Инициализация модема
local function init_modem()
    for _, side in ipairs(component.list("modem")) do
        state.modem = component.proxy(side)
        state.modem.open(12345) -- Открываем порт по умолчанию
        print("[Shell] Модем инициализирован на порту 12345")
        break
    end
end

-- Инициализация дисплея
local function init_display()
    for _, side in ipairs(component.list("display")) do
        state.display = component.proxy(side)
        state.display_width, state.display_height = state.display.getSize()
        state.display.setTextScale(1)
        state.display.setBackground(0x000000)
        state.display.setForeground(0xFFFFFF)
        print("[Shell] Дисплей инициализирован: " .. state.display_width .. "x" .. state.display_height)
        break
    end
end

-- Загрузка истории команд
local function load_history()
    if fs.exists(config.history_file) then
        local file = io.open(config.history_file, "r")
        if file then
            for line in file:lines() do
                table.insert(state.history, line)
            end
            file:close()
            -- Ограничиваем размер истории
            while #state.history > config.max_history do
                table.remove(state.history, 1)
            end
            state.history_index = #state.history
        end
    end
end

-- Сохранение истории команд
local function save_history()
    local file = io.open(config.history_file, "w")
    if file then
        for _, cmd in ipairs(state.history) do
            file:write(cmd .. "\n")
        end
        file:close()
    end
end

-- Добавление команды в историю
local function add_to_history(cmd)
    if #state.history == 0 or state.history[#state.history] ~= cmd then
        table.insert(state.history, cmd)
        while #state.history > config.max_history do
            table.remove(state.history, 1)
        end
        state.history_index = #state.history
        save_history()
    end
end

-- Вывод сообщения на дисплей, если он доступен
local function display_write(text, x, y)
    if state.display then
        if x and y then
            state.display.setCursor(x, y)
        end
        state.display.write(text)
    else
        term.write(text)
    end
end

-- Отправка сообщения через модем
local function modem_send(target, port, message)
    if state.modem then
        state.modem.send(target, port, message)
        print("[Modem] Отправлено на " .. target .. ":" .. port .. " -> " .. message)
    else
        print("[Modem] Модем не доступен")
    end
end

-- Фоновая задача
local function run_background(job_id, command)
    local success, error = pcall(function()
        local result = shell.execute(command)
        return result
    end)
    
    if success then
        print("[Job #" .. job_id .. "] Завершён: " .. command)
    else
        print("[Job #" .. job_id .. "] Ошибка: " .. tostring(error))
    end
    
    state.background_jobs[job_id] = nil
end

-- Встроенные команды
local builtins = {
    -- Справка
    help = function(args)
        print("Доступные команды:")
        print("  help              - показать эту справку")
        print("  ls [path]         - список файлов")
        print("  cd [dir]          - сменить директорию")
        print("  pwd               - текущая директория")
        print("  clear             - очистить экран")
        print("  echo [text]       - вывести текст")
        print("  jobs              - список фоновых задач")
        print("  bg [command]      - запустить команду в фоне")
        print("  kill [job_id]     - завершить фоновую задачу")
        print("  modem [target] [port] [msg] - отправить сообщение")
        print("  display [text]    - вывести на дисплей")
        print("  exit              - выход из оболочки")
    end,
    
    -- Список файлов
    ls = function(args)
        local path = args[1] or state.current_dir
        local files = fs.list(path)
        for _, file in ipairs(files) do
            local full_path = fs.path(path) .. "/" .. file
            if fs.isDirectory(full_path) then
                print(file .. "/")
            else
                print(file)
            end
        end
    end,
    
    -- Смена директории
    cd = function(args)
        local new_dir = args[1] or "/home"
        if fs.exists(new_dir) and fs.isDirectory(new_dir) then
            state.current_dir = new_dir
            shell.setWorkingDirectory(state.current_dir)
        else
            print("Директория не найдена: " .. new_dir)
        end
    end,
    
    -- Текущая директория
    pwd = function(args)
        print(state.current_dir)
    end,
    
    -- Очистка
    clear = function(args)
        term.clear()
        if state.display then
            state.display.clear()
        end
    end,
    
    -- Echo
    echo = function(args)
        print(table.concat(args, " "))
        if state.display then
            display_write(table.concat(args, " ") .. "\n")
        end
    end,
    
    -- Список фоновых задач
    jobs = function(args)
        if next(state.background_jobs) == nil then
            print("Нет активных фоновых задач")
        else
            print("Активные фоновые задачи:")
            for id, job in pairs(state.background_jobs) do
                print("  [" .. id .. "] " .. job.command)
            end
        end
    end,
    
    -- Запуск в фоне
    bg = function(args)
        local command = table.concat(args, " ")
        if command == "" then
            print("Использование: bg <команда>")
            return
        end
        
        local job_id = state.next_job_id
        state.next_job_id = state.next_job_id + 1
        
        state.background_jobs[job_id] = {command = command}
        print("[Job #" .. job_id .. "] Запущен: " .. command)
        
        -- Запускаем в отдельном потоке
        computer.beep()
        os.execute("lua -e 'os.sleep(0.1)'") -- Небольшая задержка
        run_background(job_id, command)
    end,
    
    -- Отправить через модем
    modem = function(args)
        if #args < 3 then
            print("Использование: modem <target> <port> <message>")
            print("Пример: modem 192.168.1.10 12345 \"Hello\"")
            return
        end
        local target = args[1]
        local port = tonumber(args[2])
        local message = table.concat(args, " ", 3)
        modem_send(target, port, message)
    end,
    
    -- Вывод на дисплей
    display = function(args)
        local text = table.concat(args, " ")
        if text == "" then
            print("Использование: display <текст>")
            return
        end
        display_write(text .. "\n")
    end,
    
    -- Выход
    exit = function(args)
        print("Выход из оболочки...")
        state.running = false
        if state.modem then
            state.modem.close(12345)
        end
        save_history()
        return false
    end
}

-- Получение ввода с историей
local function get_input(prompt)
    term.write(prompt)
    local input = ""
    local cursor_pos = 0
    local temp_history = nil
    
    while true do
        local _, _, key, char = event.pull("key_down")
        
        if key == 28 then -- Enter
            term.write("\n")
            break
        elseif key == 14 then -- Backspace
            if cursor_pos > 0 then
                input = input:sub(1, cursor_pos - 1) .. input:sub(cursor_pos + 1)
                cursor_pos = cursor_pos - 1
                term.write("\b \b")
            end
        elseif key == 199 then -- Home
            cursor_pos = 0
        elseif key == 207 then -- End
            cursor_pos = #input
        elseif key == 203 then -- Left
            if cursor_pos > 0 then
                cursor_pos = cursor_pos - 1
                term.write("\b")
            end
        elseif key == 205 then -- Right
            if cursor_pos < #input then
                cursor_pos = cursor_pos + 1
                term.write(string.sub(input, cursor_pos, cursor_pos))
            end
        elseif key == 72 then -- Up (история)
            if state.history_index > 0 then
                -- Сохраняем текущий ввод
                if not temp_history then
                    temp_history = input
                end
                
                input = state.history[state.history_index]
                state.history_index = state.history_index - 1
                cursor_pos = #input
                
                -- Очищаем строку и выводим заново
                term.write("\r" .. string.rep(" ", term.getCursorPos())) -- Затираем
                term.write("\r" .. prompt .. input)
            end
        elseif key == 80 then -- Down (история)
            if state.history_index < #state.history then
                state.history_index = state.history_index + 1
                if state.history_index == #state.history and temp_history then
                    input = temp_history
                    temp_history = nil
                else
                    input = state.history[state.history_index]
                end
                cursor_pos = #input
                
                term.write("\r" .. string.rep(" ", term.getCursorPos()))
                term.write("\r" .. prompt .. input)
            end
        elseif key == 1 then -- Ctrl+A
            cursor_pos = 0
        elseif key == 5 then -- Ctrl+E
            cursor_pos = #input
        elseif key == 22 then -- Ctrl+V
            -- Вставка (имитация)
        elseif char and char:byte() >= 32 then
            input = input:sub(1, cursor_pos) .. char .. input:sub(cursor_pos + 1)
            cursor_pos = cursor_pos + 1
            term.write(char)
        end
    end
    
    return input
end

-- Выполнение команды
local function execute_command(input)
    if input == "" then
        return true
    end
    
    add_to_history(input)
    
    -- Парсим команду
    local args = {}
    for arg in input:gmatch("%S+") do
        table.insert(args, arg)
    end
    
    local command = args[1]
    table.remove(args, 1)
    
    -- Встроенная команда
    if builtins[command] then
        return builtins[command](args)
    else
        -- Внешняя команда
        local success, result = pcall(function()
            return shell.execute(input)
        end)
        
        if not success then
            print("Ошибка: " .. tostring(result))
            print("Введите 'help' для списка команд")
        end
    end
    
    return true
end

-- Главный цикл
local function main_loop()
    while state.running do
        local input = get_input(config.prompt)
        if not execute_command(input) then
            break
        end
    end
end

-- Запуск
local function start()
    print("=== Advanced Shell v1.0 ===")
    print("Загрузка...")
    
    -- Инициализация устройств
    init_modem()
    init_display()
    load_history()
    
    print("Готово! Введите 'help' для списка команд")
    print("Модем: " .. (state.modem and "доступен" or "не найден"))
    print("Дисплей: " .. (state.display and "доступен" or "не найден"))
    print()
    
    -- Обработчик событий модема
    if state.modem then
        event.listen("modem_message", function(_, from, port, distance, message)
            print("\n[Modem] Сообщение от " .. from .. ":" .. port .. ": " .. message)
            term.write(config.prompt)
        end)
    end
    
    main_loop()
end

-- Запуск оболочки
local ok, err = pcall(start)
if not ok then
    print("Критическая ошибка: " .. tostring(err))
    print("Нажмите любую клавишу для выхода...")
    event.pull("key_down")
end
