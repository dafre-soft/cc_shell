-- advanced_shell.lua
-- Advanced Shell for ComputerCraft with Modem and Display support

-- Configuration
local config = {
    prompt = "> ",
    history_file = ".shell_history",
    max_history = 50,
    modem_port = 12345
}

-- State
local state = {
    running = true,
    current_dir = shell.dir(),
    history = {},
    history_index = 0,
    background_jobs = {},
    next_job_id = 1,
    modem = nil,
    modem_side = nil,
    display = nil,
    display_side = nil,
    monitor = nil
}

-- Helper: Load history
local function load_history()
    if fs.exists(config.history_file) then
        local file = fs.open(config.history_file, "r")
        if file then
            while true do
                local line = file.readLine()
                if not line then break end
                table.insert(state.history, line)
            end
            file.close()
            
            while #state.history > config.max_history do
                table.remove(state.history, 1)
            end
            state.history_index = #state.history
        end
    end
end

-- Helper: Save history
local function save_history()
    local file = fs.open(config.history_file, "w")
    if file then
        for _, cmd in ipairs(state.history) do
            file.writeLine(cmd)
        end
        file.close()
    end
end

-- Helper: Add to history
local function add_to_history(cmd)
    if cmd ~= "" and (#state.history == 0 or state.history[#state.history] ~= cmd) then
        table.insert(state.history, cmd)
        while #state.history > config.max_history do
            table.remove(state.history, 1)
        end
        state.history_index = #state.history
        save_history()
    end
end

-- Initialize modem
local function init_modem()
    local sides = { "left", "right", "front", "back", "top", "bottom" }
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            state.modem = peripheral.wrap(side)
            state.modem_side = side
            state.modem.open(config.modem_port)
            print("[Shell] Modem initialized on " .. side .. " (port " .. config.modem_port .. ")")
            return true
        end
    end
    
    -- Also check for wired modems
    for _, side in ipairs(sides) do
        local pType = peripheral.getType(side)
        if pType == "wired_modem" or pType == "modem" then
            state.modem = peripheral.wrap(side)
            state.modem_side = side
            state.modem.open(config.modem_port)
            print("[Shell] Modem initialized on " .. side .. " (port " .. config.modem_port .. ")")
            return true
        end
    end
    
    print("[Shell] No modem found")
    return false
end

-- Initialize display/monitor
local function init_display()
    local sides = { "left", "right", "front", "back", "top", "bottom" }
    for _, side in ipairs(sides) do
        local pType = peripheral.getType(side)
        if pType == "monitor" or pType == "display" then
            state.display = peripheral.wrap(side)
            state.display_side = side
            local w, h = state.display.getSize()
            state.display.setTextScale(1)
            state.display.setBackgroundColor(colors.black)
            state.display.setTextColor(colors.white)
            state.display.clear()
            print("[Shell] Display initialized on " .. side .. " (" .. w .. "x" .. h .. ")")
            return true
        end
    end
    print("[Shell] No display found")
    return false
end

-- Write to display
local function display_write(text, wrap)
    if state.display then
        if wrap then
            state.display.write(text)
        else
            state.display.write(text .. "\n")
        end
    end
end

-- Clear display
local function display_clear()
    if state.display then
        state.display.clear()
    end
end

-- Send message via modem
local function modem_send(target, port, message)
    if state.modem then
        local success = state.modem.transmit(port, target, message)
        if success then
            print("[Modem] Sent to " .. tostring(target) .. ":" .. port .. " -> " .. message)
        else
            print("[Modem] Failed to send message")
        end
    else
        print("[Modem] Modem not available")
    end
end

-- Broadcast via modem
local function modem_broadcast(port, message)
    if state.modem then
        state.modem.transmit(port, nil, message)
        print("[Modem] Broadcast on port " .. port .. " -> " .. message)
    else
        print("[Modem] Modem not available")
    end
end

-- Background job runner
local function run_background(job_id, command)
    local success, error = pcall(function()
        local result = shell.run(command)
        return result
    end)
    
    if success then
        print("[Job #" .. job_id .. "] Completed: " .. command)
    else
        print("[Job #" .. job_id .. "] Error: " .. tostring(error))
    end
    
    state.background_jobs[job_id] = nil
end

-- Built-in commands
local builtins = {
    -- Help command
    help = function(args)
        print("Available commands:")
        print("  help                    - Show this help")
        print("  ls [path]               - List files")
        print("  cd [dir]                - Change directory")
        print("  pwd                     - Print working directory")
        print("  clear                   - Clear screen")
        print("  echo [text]             - Print text")
        print("  jobs                    - List background jobs")
        print("  bg [command]            - Run command in background")
        print("  kill [job_id]           - Kill background job")
        print("  modem send [target] [port] [msg] - Send modem message")
        print("  modem broadcast [port] [msg]      - Broadcast modem message")
        print("  display [text]          - Write to external display")
        print("  display clear           - Clear external display")
        print("  display line [n] [text] - Write to specific line")
        print("  rednet [command]        - Rednet commands")
        print("  exit                    - Exit shell")
    end,
    
    -- List files
    ls = function(args)
        local path = args[1] or state.current_dir
        local files = fs.list(path)
        local list = {}
        for _, file in ipairs(files) do
            if fs.isDir(fs.combine(path, file)) then
                table.insert(list, file .. "/")
            else
                table.insert(list, file)
            end
        end
        table.sort(list)
        for _, item in ipairs(list) do
            print(item)
        end
    end,
    
    -- Change directory
    cd = function(args)
        local new_dir = args[1] or "/"
        if fs.isDir(new_dir) then
            shell.setDir(new_dir)
            state.current_dir = shell.dir()
        else
            print("Directory not found: " .. new_dir)
        end
    end,
    
    -- Print working directory
    pwd = function(args)
        print(state.current_dir)
    end,
    
    -- Clear screen
    clear = function(args)
        term.clear()
        term.setCursorPos(1, 1)
    end,
    
    -- Echo command
    echo = function(args)
        local text = table.concat(args, " ")
        print(text)
        if state.display then
            display_write(text .. "\n", false)
        end
    end,
    
    -- List background jobs
    jobs = function(args)
        if next(state.background_jobs) == nil then
            print("No active background jobs")
        else
            print("Active background jobs:")
            for id, job in pairs(state.background_jobs) do
                print("  [" .. id .. "] " .. job.command)
            end
        end
    end,
    
    -- Run background job
    bg = function(args)
        local command = table.concat(args, " ")
        if command == "" then
            print("Usage: bg <command>")
            return
        end
        
        local job_id = state.next_job_id
        state.next_job_id = state.next_job_id + 1
        
        state.background_jobs[job_id] = {command = command}
        print("[Job #" .. job_id .. "] Started: " .. command)
        
        -- Run in parallel
        parallel.waitForAny(function()
            run_background(job_id, command)
        end)
    end,
    
    -- Kill background job
    kill = function(args)
        local job_id = tonumber(args[1])
        if not job_id or not state.background_jobs[job_id] then
            print("Invalid job ID")
            return
        end
        state.background_jobs[job_id] = nil
        print("[Job #" .. job_id .. "] Killed")
    end,
    
    -- Modem commands
    modem = function(args)
        if #args < 1 then
            print("Usage:")
            print("  modem send <target> <port> <message>")
            print("  modem broadcast <port> <message>")
            return
        end
        
        local subcmd = args[1]
        table.remove(args, 1)
        
        if subcmd == "send" then
            if #args < 3 then
                print("Usage: modem send <target> <port> <message>")
                print("Example: modem send 0 12345 Hello")
                print("Target: 0 = all, or computer ID")
                return
            end
            local target = tonumber(args[1]) or args[1]
            local port = tonumber(args[2])
            local message = table.concat(args, " ", 3)
            modem_send(target, port, message)
        elseif subcmd == "broadcast" then
            if #args < 2 then
                print("Usage: modem broadcast <port> <message>")
                return
            end
            local port = tonumber(args[1])
            local message = table.concat(args, " ", 2)
            modem_broadcast(port, message)
        else
            print("Unknown modem subcommand: " .. subcmd)
        end
    end,
    
    -- Display commands
    display = function(args)
        if #args < 1 then
            print("Usage:")
            print("  display <text>           - Write text to display")
            print("  display clear            - Clear display")
            print("  display line <n> <text>  - Write to specific line")
            return
        end
        
        if args[1] == "clear" then
            display_clear()
        elseif args[1] == "line" and #args >= 3 then
            local line_num = tonumber(args[2])
            local text = table.concat(args, " ", 3)
            if state.display and line_num then
                state.display.setCursorPos(1, line_num)
                state.display.write(text)
            end
        else
            local text = table.concat(args, " ")
            display_write(text .. "\n", false)
        end
    end,
    
    -- Rednet commands
    rednet = function(args)
        if not state.modem then
            print("Rednet requires a modem")
            return
        end
        
        if not rednet then
            os.loadAPI("rednet")
        end
        
        if #args < 1 then
            print("Rednet commands:")
            print("  rednet send <id> <message>")
            print("  rednet broadcast <message>")
            print("  rednet lookup <name>")
            print("  rednet host <name>")
            print("  rednet unhost")
            return
        end
        
        local subcmd = args[1]
        table.remove(args, 1)
        
        if subcmd == "send" and #args >= 2 then
            local target = tonumber(args[1])
            local message = table.concat(args, " ", 2)
            rednet.send(target, message)
            print("[Rednet] Sent to " .. target)
        elseif subcmd == "broadcast" and #args >= 1 then
            local message = table.concat(args, " ")
            rednet.broadcast(message)
            print("[Rednet] Broadcast sent")
        elseif subcmd == "lookup" and #args >= 1 then
            local id = rednet.lookup(args[1])
            if id then
                print("Computer ID: " .. id)
            else
                print("Not found")
            end
        elseif subcmd == "host" and #args >= 1 then
            rednet.host(args[1], os.getComputerID())
            print("[Rednet] Hosting as " .. args[1])
        elseif subcmd == "unhost" then
            rednet.unhost()
            print("[Rednet] Unhosted")
        end
    end,
    
    -- Exit shell
    exit = function(args)
        print("Exiting shell...")
        state.running = false
        if state.modem then
            state.modem.close(config.modem_port)
        end
        save_history()
        return false
    end
}

-- Get user input with history support
local function get_input(prompt)
    term.write(prompt)
    local input = ""
    local cursor_pos = 0
    local temp_history = nil
    
    while true do
        local event, key, char = os.pullEvent("key")
        
        if key == keys.enter then
            term.write("\n")
            break
        elseif key == keys.backspace then
            if cursor_pos > 0 then
                input = input:sub(1, cursor_pos - 1) .. input:sub(cursor_pos + 1)
                cursor_pos = cursor_pos - 1
                term.write("\b \b")
            end
        elseif key == keys.left then
            if cursor_pos > 0 then
                cursor_pos = cursor_pos - 1
                term.setCursorPos(term.getCursorPos() - 1, term.getCursorPos())
            end
        elseif key == keys.right then
            if cursor_pos < #input then
                cursor_pos = cursor_pos + 1
                term.setCursorPos(term.getCursorPos() + 1, term.getCursorPos())
            end
        elseif key == keys.up then
            if state.history_index > 0 then
                if not temp_history then
                    temp_history = input
                end
                input = state.history[state.history_index]
                state.history_index = state.history_index - 1
                cursor_pos = #input
                term.clearLine()
                term.setCursorPos(1, term.getCursorPos())
                term.write(prompt .. input)
            end
        elseif key == keys.down then
            if state.history_index < #state.history then
                state.history_index = state.history_index + 1
                if state.history_index == #state.history and temp_history then
                    input = temp_history
                    temp_history = nil
                else
                    input = state.history[state.history_index]
                end
                cursor_pos = #input
                term.clearLine()
                term.setCursorPos(1, term.getCursorPos())
                term.write(prompt .. input)
            elseif temp_history then
                input = temp_history
                temp_history = nil
                cursor_pos = #input
                term.clearLine()
                term.setCursorPos(1, term.getCursorPos())
                term.write(prompt .. input)
            end
        elseif key == keys.home then
            cursor_pos = 0
            term.setCursorPos(#prompt + 1, term.getCursorPos())
        elseif key == keys["end"] then
            cursor_pos = #input
            term.setCursorPos(#prompt + #input + 1, term.getCursorPos())
        elseif char then
            input = input:sub(1, cursor_pos) .. char .. input:sub(cursor_pos + 1)
            cursor_pos = cursor_pos + 1
            term.write(char)
        end
    end
    
    return input
end

-- Execute command
local function execute_command(input)
    if input == "" then
        return true
    end
    
    add_to_history(input)
    
    -- Parse command
    local args = {}
    for arg in input:gmatch("%S+") do
        table.insert(args, arg)
    end
    
    local command = args[1]
    table.remove(args, 1)
    
    -- Check built-in commands
    if builtins[command] then
        local result = builtins[command](args)
        return result ~= false
    else
        -- External command
        local success, error = pcall(function()
            shell.run(command, table.unpack(args))
        end)
        
        if not success then
            print("Error: " .. tostring(error))
            print("Type 'help' for available commands")
        end
    end
    
    return true
end

-- Modem message handler
local function handle_modem_messages()
    while state.running do
        local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if event == "modem_message" then
            print("\n[Modem] From " .. channel .. ":" .. replyChannel .. " -> " .. tostring(message))
            term.write(config.prompt)
        end
    end
end

-- Main loop
local function main_loop()
    -- Start modem listener in parallel if modem exists
    if state.modem then
        parallel.waitForAny(function()
            handle_modem_messages()
        end, function()
            while state.running do
                local input = get_input(config.prompt)
                if not execute_command(input) then
                    break
                end
            end
        end)
    else
        while state.running do
            local input = get_input(config.prompt)
            if not execute_command(input) then
                break
            end
        end
    end
end

-- Initialize and start
local function start()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Advanced Shell for ComputerCraft v2.0 ===")
    print("Loading...")
    
    init_modem()
    init_display()
    load_history()
    
    print("\nReady! Type 'help' for commands")
    print("Modem: " .. (state.modem and "Available on " .. state.modem_side or "Not found"))
    print("Display: " .. (state.display and "Available on " .. state.display_side or "Not found"))
    print("")
    
    if state.modem and rednet then
        print("Rednet is available")
    end
    
    print("")
    main_loop()
end

-- Run shell
local ok, err = pcall(start)
if not ok then
    print("Fatal error: " .. tostring(err))
    print("Press any key to exit...")
    os.pullEvent("key")
end
