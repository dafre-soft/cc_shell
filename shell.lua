-- Advanced Shell for ComputerCraft (CC:Tweaked)
-- Features: Modem support, Display support, GUI interface, Background tasks, Command history

local shell = {}
local version = "2.0.0"

-- ============================================================================
-- Configuration
-- ============================================================================
local config = {
    prompt = "> ",
    historyFile = ".shell_history",
    maxHistory = 100,
    modemPort = 12345,
    guiEnabled = true,
    guiWidth = 50,
    guiHeight = 20
}

-- ============================================================================
-- Global State
-- ============================================================================
local state = {
    running = true,
    currentDir = shell.dir(),
    history = {},
    historyIndex = 0,
    backgroundJobs = {},
    nextJobId = 1,
    modem = nil,
    modemSide = nil,
    display = nil,
    displaySide = nil,
    guiWindow = nil,
    guiMonitor = nil,
    outputBuffer = {},
    inputBuffer = "",
    cursorPos = 0,
    scrollOffset = 0
}

-- ============================================================================
-- Helper Functions
-- ============================================================================
local function splitString(str, delimiter)
    delimiter = delimiter or "%s"
    local result = {}
    for match in string.gmatch(str, "[^" .. delimiter .. "]+") do
        table.insert(result, match)
    end
    return result
end

local function tableToString(tbl, indent)
    indent = indent or 0
    local str = ""
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            str = str .. string.rep("  ", indent) .. tostring(k) .. ": {\n" .. tableToString(v, indent + 1) .. string.rep("  ", indent) .. "}\n"
        else
            str = str .. string.rep("  ", indent) .. tostring(k) .. ": " .. tostring(v) .. "\n"
        end
    end
    return str
end

-- ============================================================================
- History Management
-- ============================================================================
local function loadHistory()
    if fs.exists(config.historyFile) then
        local file = fs.open(config.historyFile, "r")
        if file then
            while true do
                local line = file.readLine()
                if not line then break end
                table.insert(state.history, line)
            end
            file.close()
            
            while #state.history > config.maxHistory do
                table.remove(state.history, 1)
            end
            state.historyIndex = #state.history
        end
    end
end

local function saveHistory()
    local file = fs.open(config.historyFile, "w")
    if file then
        for _, cmd in ipairs(state.history) do
            file.writeLine(cmd)
        end
        file.close()
    end
end

local function addToHistory(cmd)
    if cmd ~= "" then
        if #state.history == 0 or state.history[#state.history] ~= cmd then
            table.insert(state.history, cmd)
            while #state.history > config.maxHistory do
                table.remove(state.history, 1)
            end
            state.historyIndex = #state.history
            saveHistory()
        end
    end
end

-- ============================================================================
-- Output Management
-- ============================================================================
local function addOutput(text)
    local lines = {}
    for line in string.gmatch(text, "[^\r\n]+") do
        table.insert(state.outputBuffer, line)
    end
    
    -- Limit buffer size
    while #state.outputBuffer > 1000 do
        table.remove(state.outputBuffer, 1)
    end
    
    -- Auto-scroll to bottom
    state.scrollOffset = 0
    
    if not config.guiEnabled or not state.guiWindow then
        print(text)
    end
end

local function clearOutput()
    state.outputBuffer = {}
    state.scrollOffset = 0
    if config.guiEnabled and state.guiWindow then
        state.guiWindow.clear()
        state.guiWindow.setCursorPos(1, 1)
    else
        term.clear()
        term.setCursorPos(1, 1)
    end
end

-- ============================================================================
-- Modem Functions
-- ============================================================================
local function initModem()
    local sides = peripheral.getNames()
    for _, side in ipairs(sides) do
        local p = peripheral.wrap(side)
        if p and p.isWirelessModem and p.isWirelessModem() then
            state.modem = p
            state.modemSide = side
            state.modem.open(config.modemPort)
            addOutput("[Shell] Modem initialized on side '" .. side .. "', port " .. config.modemPort)
            return true
        end
    end
    addOutput("[Shell] No modem found")
    return false
end

local function modemSend(target, port, message)
    if state.modem then
        state.modem.transmit(port, target, message)
        addOutput("[Modem] Sent to " .. tostring(target) .. ":" .. port .. " -> " .. message)
        return true
    else
        addOutput("[Modem] Modem not available")
        return false
    end
end

-- ============================================================================
-- Display Functions
-- ============================================================================
local function initDisplay()
    local sides = peripheral.getNames()
    for _, side in ipairs(sides) do
        local p = peripheral.wrap(side)
        if p and p.getSize then
            state.display = p
            state.displaySide = side
            local w, h = state.display.getSize()
            addOutput("[Shell] Display initialized on side '" .. side .. "' (" .. w .. "x" .. h .. ")")
            return true
        end
    end
    addOutput("[Shell] No display found")
    return false
end

local function displayWrite(text, x, y)
    if state.display then
        if x and y then
            state.display.setCursorPos(x, y)
        end
        state.display.write(text)
    end
end

local function displayClear()
    if state.display then
        state.display.clear()
    end
end

-- ============================================================================
-- GUI Functions
-- ============================================================================
local function drawGUI()
    if not config.guiEnabled or not state.guiWindow then
        return
    end
    
    local w, h = state.guiWindow.getSize()
    
    -- Draw title bar
    state.guiWindow.setBackgroundColor(colors.blue)
    state.guiWindow.setTextColor(colors.white)
    state.guiWindow.clearLine()
    state.guiWindow.setCursorPos(1, 1)
    local title = " Advanced Shell v" .. version .. " "
    state.guiWindow.write(title .. string.rep(" ", w - #title - 5))
    state.guiWindow.write("[X]")
    
    -- Draw status bar
    state.guiWindow.setBackgroundColor(colors.black)
    state.guiWindow.setTextColor(colors.lightGray)
    state.guiWindow.setCursorPos(1, h)
    local status = " Dir: " .. state.currentDir .. " "
    local modemStatus = state.modem and "Modem:ON " or "Modem:OFF "
    local jobCount = 0
    for _ in pairs(state.backgroundJobs) do jobCount = jobCount + 1 end
    local jobsStatus = "Jobs:" .. jobCount .. " "
    local fullStatus = status .. modemStatus .. jobsStatus
    state.guiWindow.write(fullStatus .. string.rep(" ", w - #fullStatus))
    
    -- Draw separator lines
    state.guiWindow.setBackgroundColor(colors.gray)
    for x = 1, w do
        state.guiWindow.setCursorPos(x, 2)
        state.guiWindow.write("─")
        state.guiWindow.setCursorPos(x, h - 1)
        state.guiWindow.write("─")
    end
    
    -- Draw output area (lines 3 to h-2)
    state.guiWindow.setBackgroundColor(colors.black)
    state.guiWindow.setTextColor(colors.white)
    
    local outputHeight = h - 4
    local startIdx = #state.outputBuffer - outputHeight + 1 - state.scrollOffset
    if startIdx < 1 then startIdx = 1 end
    
    for i = 1, outputHeight do
        state.guiWindow.setCursorPos(1, 2 + i)
        state.guiWindow.clearLine()
        local lineIdx = startIdx + i - 1
        if lineIdx <= #state.outputBuffer then
            local line = state.outputBuffer[lineIdx]
            if #line > w - 2 then
                line = line:sub(1, w - 5) .. "..."
            end
            state.guiWindow.write(" " .. line)
        end
    end
    
    -- Draw input line
    state.guiWindow.setCursorPos(1, h - 1)
    state.guiWindow.setBackgroundColor(colors.black)
    state.guiWindow.setTextColor(colors.yellow)
    state.guiWindow.write(" ")
    state.guiWindow.setBackgroundColor(colors.black)
    state.guiWindow.setTextColor(colors.white)
    state.guiWindow.write(config.prompt)
    state.guiWindow.setTextColor(colors.yellow)
    state.guiWindow.write(state.inputBuffer)
    state.guiWindow.clearLine()
    
    -- Position cursor
    local cursorX = 2 + #config.prompt + state.cursorPos
    if cursorX > w then cursorX = w end
    state.guiWindow.setCursorPos(cursorX, h - 1)
end

local function initGUI()
    if not config.guiEnabled then
        return false
    end
    
    local sides = peripheral.getNames()
    for _, side in ipairs(sides) do
        local p = peripheral.wrap(side)
        if p and p.getSize and p.getSize() then
            state.guiMonitor = p
            local w, h = state.guiMonitor.getSize()
            if w >= config.guiWidth and h >= config.guiHeight then
                state.guiWindow = window.create(state.guiMonitor, 1, 1, w, h, false)
                state.guiWindow.setBackgroundColor(colors.black)
                state.guiWindow.setTextColor(colors.white)
                state.guiWindow.clear()
                addOutput("[Shell] GUI initialized on monitor '" .. side .. "'")
                drawGUI()
                return true
            end
        end
    end
    
    addOutput("[Shell] No suitable monitor found for GUI")
    config.guiEnabled = false
    return false
end

-- ============================================================================
-- Command Execution
-- ============================================================================
local function executeExternalCommand(cmd, args)
    local command = cmd
    for _, arg in ipairs(args) do
        command = command .. " " .. arg
    end
    
    local success, result = pcall(function()
        return shell.run(command)
    end)
    
    if not success then
        addOutput("Error: " .. tostring(result))
        return false
    end
    return true
end

local function listFiles(path)
    path = path or state.currentDir
    if not fs.exists(path) then
        addOutput("Directory not found: " .. path)
        return
    end
    
    local items = fs.list(path)
    local files = {}
    local dirs = {}
    
    for _, item in ipairs(items) do
        local fullPath = fs.combine(path, item)
        if fs.isDir(fullPath) then
            table.insert(dirs, item .. "/")
        else
            table.insert(files, item)
        end
    end
    
    table.sort(dirs)
    table.sort(files)
    
    for _, dir in ipairs(dirs) do
        addOutput(dir)
    end
    for _, file in ipairs(files) do
        addOutput(file)
    end
end

-- ============================================================================
-- Built-in Commands
-- ============================================================================
local builtins = {
    help = function(args)
        addOutput("=== Advanced Shell Commands ===")
        addOutput("  help                    - Show this help")
        addOutput("  ls [path]              - List files/directories")
        addOutput("  cd [dir]               - Change directory")
        addOutput("  pwd                    - Print working directory")
        addOutput("  clear / cls            - Clear screen")
        addOutput("  echo [text]            - Print text")
        addOutput("  jobs                   - List background jobs")
        addOutput("  bg [command]           - Run command in background")
        addOutput("  kill <job_id>          - Kill background job")
        addOutput("  modem <target> <port> <msg> - Send modem message")
        addOutput("  display [text]         - Write to external display")
        addOutput("  history                - Show command history")
        addOutput("  exit / quit            - Exit shell")
    end,
    
    ls = function(args)
        listFiles(args[1])
    end,
    
    dir = function(args)
        listFiles(args[1])
    end,
    
    cd = function(args)
        local newDir = args[1] or "/"
        if fs.isDir(newDir) then
            shell.setDir(newDir)
            state.currentDir = shell.dir()
            addOutput("Changed to: " .. state.currentDir)
        else
            addOutput("Directory not found: " .. newDir)
        end
    end,
    
    pwd = function(args)
        addOutput(state.currentDir)
    end,
    
    clear = function(args)
        clearOutput()
    end,
    
    cls = function(args)
        clearOutput()
    end,
    
    echo = function(args)
        local text = table.concat(args, " ")
        addOutput(text)
        if state.display then
            displayWrite(text .. "\n")
        end
    end,
    
    jobs = function(args)
        if next(state.backgroundJobs) == nil then
            addOutput("No active background jobs")
        else
            addOutput("Active background jobs:")
            for id, job in pairs(state.backgroundJobs) do
                addOutput("  [" .. id .. "] " .. job.command)
            end
        end
    end,
    
    bg = function(args)
        local command = table.concat(args, " ")
        if command == "" then
            addOutput("Usage: bg <command>")
            return
        end
        
        local jobId = state.nextJobId
        state.nextJobId = state.nextJobId + 1
        state.backgroundJobs[jobId] = {command = command, running = true}
        addOutput("[Job #" .. jobId .. "] Started: " .. command)
        
        parallel.waitForAny(function()
            os.sleep(0.1)
            local success, err = pcall(function()
                shell.run(command)
            end)
            if state.backgroundJobs[jobId] then
                state.backgroundJobs[jobId] = nil
                if not success then
                    addOutput("[Job #" .. jobId .. "] Error: " .. tostring(err))
                else
                    addOutput("[Job #" .. jobId .. "] Completed")
                end
            end
        end)
    end,
    
    kill = function(args)
        local jobId = tonumber(args[1])
        if not jobId or not state.backgroundJobs[jobId] then
            addOutput("Job not found: " .. tostring(args[1]))
            return
        end
        state.backgroundJobs[jobId] = nil
        addOutput("[Job #" .. jobId .. "] Killed")
    end,
    
    modem = function(args)
        if #args < 3 then
            addOutput("Usage: modem <target> <port> <message>")
            addOutput("Example: modem @Everyone 12345 Hello")
            return
        end
        local target = args[1]
        local port = tonumber(args[2])
        local message = table.concat(args, " ", 3)
        modemSend(target, port, message)
    end,
    
    display = function(args)
        local text = table.concat(args, " ")
        if text == "" then
            addOutput("Usage: display <text>")
            return
        end
        displayWrite(text .. "\n")
    end,
    
    history = function(args)
        for i, cmd in ipairs(state.history) do
            addOutput(string.format("%3d: %s", i, cmd))
        end
    end,
    
    exit = function(args)
        addOutput("Goodbye!")
        state.running = false
        saveHistory()
        if state.modem then
            state.modem.close(config.modemPort)
        end
        if state.guiWindow then
            state.guiWindow.clear()
            state.guiWindow.setCursorPos(1, 1)
            state.guiWindow.write("Shell closed. Press any key to exit...")
        end
        return false
    end,
    
    quit = function(args)
        return builtins.exit(args)
    end
}

-- ============================================================================
-- Input Handling
-- ============================================================================
local function handleInput(char)
    if char == string.char(13) then -- Enter
        addOutput(config.prompt .. state.inputBuffer)
        local cmd = state.inputBuffer
        state.inputBuffer = ""
        state.cursorPos = 0
        
        if cmd ~= "" then
            addToHistory(cmd)
            local args = splitString(cmd)
            local command = table.remove(args, 1)
            
            if builtins[command] then
                local result = builtins[command](args)
                if result == false then
                    return false
                end
            else
                executeExternalCommand(command, args)
            end
        end
        
        if config.guiEnabled and state.guiWindow then
            drawGUI()
        end
    elseif char == string.char(8) then -- Backspace
        if state.cursorPos > 0 then
            state.inputBuffer = state.inputBuffer:sub(1, state.cursorPos - 1) .. state.inputBuffer:sub(state.cursorPos + 1)
            state.cursorPos = state.cursorPos - 1
            if config.guiEnabled and state.guiWindow then
                drawGUI()
            end
        end
    elseif char:byte() and char:byte() >= 32 then -- Printable characters
        state.inputBuffer = state.inputBuffer:sub(1, state.cursorPos) .. char .. state.inputBuffer:sub(state.cursorPos + 1)
        state.cursorPos = state.cursorPos + 1
        if config.guiEnabled and state.guiWindow then
            drawGUI()
        end
    end
    
    return true
end

local function handleKey(key)
    if key == keys.up then -- Up arrow
        if state.historyIndex > 0 then
            state.inputBuffer = state.history[state.historyIndex]
            state.historyIndex = state.historyIndex - 1
            state.cursorPos = #state.inputBuffer
            if config.guiEnabled and state.guiWindow then
                drawGUI()
            end
        end
    elseif key == keys.down then -- Down arrow
        if state.historyIndex < #state.history then
            state.historyIndex = state.historyIndex + 1
            if state.historyIndex == #state.history then
                state.inputBuffer = ""
            else
                state.inputBuffer = state.history[state.historyIndex + 1]
            end
            state.cursorPos = #state.inputBuffer
            if config.guiEnabled and state.guiWindow then
                drawGUI()
            end
        end
    elseif key == keys.left then -- Left arrow
        if state.cursorPos > 0 then
            state.cursorPos = state.cursorPos - 1
            if config.guiEnabled and state.guiWindow then
                drawGUI()
            end
        end
    elseif key == keys.right then -- Right arrow
        if state.cursorPos < #state.inputBuffer then
            state.cursorPos = state.cursorPos + 1
            if config.guiEnabled and state.guiWindow then
                drawGUI()
            end
        end
    elseif key == keys.home then -- Home
        state.cursorPos = 0
        if config.guiEnabled and state.guiWindow then
            drawGUI()
        end
    elseif key == keys["end"] then -- End
        state.cursorPos = #state.inputBuffer
        if config.guiEnabled and state.guiWindow then
            drawGUI()
        end
    elseif key == keys.pageUp then -- Page Up
        state.scrollOffset = state.scrollOffset + 10
        if config.guiEnabled and state.guiWindow then
            drawGUI()
        end
    elseif key == keys.pageDown then -- Page Down
        state.scrollOffset = math.max(0, state.scrollOffset - 10)
        if config.guiEnabled and state.guiWindow then
            drawGUI()
        end
    end
end

-- ============================================================================
-- Modem Event Handler
-- ============================================================================
local function handleModemEvent(event, side, channel, replyChannel, message, distance)
    if event == "modem_message" then
        addOutput("\n[Modem] From " .. side .. ":" .. channel .. " -> " .. message)
        if config.guiEnabled and state.guiWindow then
            drawGUI()
        end
    end
end

-- ============================================================================
-- Main Loop
-- ============================================================================
local function mainLoop()
    -- Register modem event handler
    if state.modem then
        os.loadAPI("event")
        event.listen("modem_message", handleModemEvent)
    end
    
    while state.running do
        if config.guiEnabled and state.guiWindow then
            drawGUI()
            local eventData = {os.pullEvent()}
            local eventType = eventData[1]
            
            if eventType == "key" then
                local key = eventData[2]
                if key == keys.enter then
                    if not handleInput(string.char(13)) then
                        break
                    end
                elseif key == keys.backspace then
                    handleInput(string.char(8))
                else
                    handleKey(key)
                end
            elseif eventType == "char" then
                local char = eventData[2]
                if not handleInput(char) then
                    break
                end
            elseif eventType == "modem_message" then
                handleModemEvent(unpack(eventData))
            end
        else
            -- Terminal mode
            term.write(config.prompt)
            local input = read()
            
            if input then
                addOutput(config.prompt .. input)
                
                if input ~= "" then
                    addToHistory(input)
                    local args = splitString(input)
                    local command = table.remove(args, 1)
                    
                    if builtins[command] then
                        local result = builtins[command](args)
                        if result == false then
                            break
                        end
                    else
                        executeExternalCommand(command, args)
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- Initialization
-- ============================================================================
local function init()
    print("=== Advanced Shell v" .. version .. " ===")
    print("Initializing...")
    
    loadHistory()
    initModem()
    initDisplay()
    
    -- Try to initialize GUI
    if config.guiEnabled then
        initGUI()
    end
    
    if config.guiEnabled and state.guiWindow then
        print("GUI mode enabled on monitor")
        addOutput("=== Advanced Shell v" .. version .. " ===")
        addOutput("Type 'help' for available commands")
        addOutput("Modem: " .. (state.modem and "Connected" or "Not found"))
        addOutput("Display: " .. (state.display and "Connected" or "Not found"))
    else
        print("Terminal mode enabled")
        print("Type 'help' for available commands")
        print("Modem: " .. (state.modem and "Connected" or "Not found"))
        print("Display: " .. (state.display and "Connected" or "Not found"))
        print("")
    end
end

-- ============================================================================
-- Start Shell
-- ============================================================================
local function start()
    init()
    mainLoop()
end

-- Run the shell
local ok, err = pcall(start)
if not ok then
    print("Fatal error: " .. tostring(err))
    print("Press any key to exit...")
    os.pullEvent("key")
end
