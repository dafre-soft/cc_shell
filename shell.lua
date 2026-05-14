-- ComputerCraft Advanced Shell with GUI
-- Save as "shell.lua" and run

-- Configuration
local config = {
    prompt = "> ",
    historyFile = ".shell_history",
    maxHistory = 50,
    modemPort = 12345
}

-- GUI Colors
local colors = {
    background = colors.black,
    text = colors.white,
    prompt = colors.lime,
    error = colors.red,
    success = colors.green,
    info = colors.cyan,
    border = colors.gray
}

-- State
local state = {
    running = true,
    currentDir = shell.dir(),
    history = {},
    historyIndex = 0,
    currentInput = "",
    cursorPos = 0,
    scrollOffset = 0,
    outputLines = {},
    maxOutputLines = 100,
    modem = nil,
    display = nil,
    displayMonitor = nil,
    termW = 0,
    termH = 0,
    currentX = 0,
    currentY = 0
}

-- GUI Functions
local function setColor(color)
    term.setTextColor(color)
end

local function setBgColor(color)
    term.setBackgroundColor(color)
end

local function clearScreen()
    term.clear()
    setColor(colors.text)
    setBgColor(colors.background)
    term.setCursorPos(1, 1)
end

local function drawBorder()
    local w, h = term.getSize()
    setColor(colors.border)
    for x = 1, w do
        term.setCursorPos(x, 1)
        term.write("=")
        term.setCursorPos(x, h)
        term.write("=")
    end
    for y = 2, h-1 do
        term.setCursorPos(1, y)
        term.write("|")
        term.setCursorPos(w, y)
        term.write("|")
    end
    setColor(colors.text)
end

local function drawStatusBar()
    local w, h = term.getSize()
    term.setCursorPos(2, h)
    setColor(colors.info)
    term.write(" Modem:" .. (state.modem and "ON" or "OFF"))
    term.write(" | Display:" .. (state.display and "ON" or "OFF"))
    term.write(" | Dir:" .. state.currentDir)
    
    -- Show clock
    local timeText = textutils.formatTime(os.time(), false)
    term.setCursorPos(w - #timeText - 2, h)
    term.write(timeText)
    
    setColor(colors.text)
end

local function scrollOutput()
    local w, h = term.getSize()
    local outputArea = h - 3 -- Leave space for prompt and status
    
    term.setCursorPos(2, 2)
    
    -- Calculate visible lines
    local visibleLines = {}
    for i = #state.outputLines - state.scrollOffset, 1, -1 do
        table.insert(visibleLines, 1, state.outputLines[i])
        if #visibleLines >= outputArea then break end
    end
    
    -- Clear output area
    for y = 2, h-2 do
        term.setCursorPos(2, y)
        term.write(string.rep(" ", w-2))
    end
    
    -- Draw visible lines
    term.setCursorPos(2, 2)
    for i, line in ipairs(visibleLines) do
        if i <= outputArea then
            term.setCursorPos(2, 1 + i)
            local displayLine = line
            if #displayLine > w - 3 then
                displayLine = displayLine:sub(1, w-6) .. "..."
            end
            term.write(displayLine)
            term.write(string.rep(" ", w - #displayLine - 3))
        end
    end
end

local function addOutput(text, color)
    if color then
        setColor(color)
    else
        setColor(colors.text)
    end
    
    -- Split long lines
    local w, h = term.getSize()
    local lines = {}
    while #text > w - 4 do
        local line = text:sub(1, w-4)
        table.insert(lines, line)
        text = text:sub(w-3)
    end
    table.insert(lines, text)
    
    for _, line in ipairs(lines) do
        table.insert(state.outputLines, line)
        if #state.outputLines > state.maxOutputLines then
            table.remove(state.outputLines, 1)
        end
    end
    
    scrollOutput()
    setColor(colors.text)
end

-- Input handling with cursor
local function drawPrompt()
    local w, h = term.getSize()
    term.setCursorPos(2, h-1)
    setColor(colors.prompt)
    term.write(config.prompt)
    setColor(colors.text)
    term.write(state.currentInput)
    term.write(string.rep(" ", w - #config.prompt - #state.currentInput - 2))
    term.setCursorPos(2 + #config.prompt + state.cursorPos, h-1)
end

local function clearInputLine()
    local w, h = term.getSize()
    term.setCursorPos(2, h-1)
    term.write(string.rep(" ", w-2))
end

-- Modem functions
local function initModem()
    if peripheral.find("modem") then
        state.modem = peripheral.find("modem")
        state.modem.open(config.modemPort)
        addOutput("[System] Modem initialized on port " .. config.modemPort, colors.success)
        return true
    else
        addOutput("[System] No modem found", colors.error)
        return false
    end
end

local function sendModemMessage(target, port, message)
    if state.modem then
        state.modem.transmit(port, target, message)
        addOutput("[Modem] Sent to " .. target .. ":" .. port .. " -> " .. message, colors.info)
        return true
    else
        addOutput("[Modem] No modem available", colors.error)
        return false
    end
end

-- Display functions
local function initDisplay()
    for _, side in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(side)
        if p.getType and p.getType() == "monitor" then
            state.display = p
            state.display.setTextColor(colors.white)
            state.display.setBackgroundColor(colors.black)
            state.display.clear()
            state.display.setCursorPos(1, 1)
            state.display.write("=== ComputerCraft Shell ===")
            addOutput("[System] Display connected on " .. side, colors.success)
            return true
        end
    end
    addOutput("[System] No display found", colors.warning)
    return false
end

local function writeToDisplay(text, x, y)
    if state.display then
        if x and y then
            state.display.setCursorPos(x, y)
        end
        state.display.write(text)
    end
end

-- History functions
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
            state.historyIndex = #state.history
        end
    end
end

local function saveHistory()
    local file = fs.open(config.historyFile, "w")
    if file then
        for i = math.max(1, #state.history - config.maxHistory), #state.history do
            file.writeLine(state.history[i])
        end
        file.close()
    end
end

local function addToHistory(cmd)
    if cmd ~= "" and (#state.history == 0 or state.history[#state.history] ~= cmd) then
        table.insert(state.history, cmd)
        if #state.history > config.maxHistory then
            table.remove(state.history, 1)
        end
        state.historyIndex = #state.history
        saveHistory()
    end
end

-- Built-in commands
local builtins = {
    help = function(args)
        addOutput("=== Available Commands ===", colors.info)
        addOutput("  help              - Show this help", colors.text)
        addOutput("  ls [path]         - List files", colors.text)
        addOutput("  cd [dir]          - Change directory", colors.text)
        addOutput("  pwd               - Show current directory", colors.text)
        addOutput("  clear / cls       - Clear screen", colors.text)
        addOutput("  echo [text]       - Print text", colors.text)
        addOutput("  history           - Show command history", colors.text)
        addOutput("  modem send <target> <port> <msg> - Send modem message", colors.text)
        addOutput("  modem status      - Show modem status", colors.text)
        addOutput("  display <text>    - Write to external display", colors.text)
        addOutput("  display clear     - Clear external display", colors.text)
        addOutput("  exit / quit       - Exit shell", colors.text)
        return true
    end,
    
    ls = function(args)
        local path = args[1] or state.currentDir
        if not fs.exists(path) then
            addOutput("Path not found: " .. path, colors.error)
            return true
        end
        
        local files = fs.list(path)
        if #files == 0 then
            addOutput("Directory is empty", colors.warning)
            return true
        end
        
        table.sort(files)
        for _, file in ipairs(files) do
            local fullPath = fs.combine(path, file)
            if fs.isDir(fullPath) then
                addOutput(file .. "/", colors.info)
            else
                addOutput(file, colors.text)
            end
        end
        return true
    end,
    
    cd = function(args)
        local newDir = args[1] or "/"
        if fs.isDir(newDir) then
            shell.setDir(newDir)
            state.currentDir = shell.dir()
            addOutput("Changed to: " .. state.currentDir, colors.success)
        elseif newDir == ".." then
            shell.setDir(shell.dir() .. "/..")
            state.currentDir = shell.dir()
            addOutput("Changed to: " .. state.currentDir, colors.success)
        else
            addOutput("Directory not found: " .. newDir, colors.error)
        end
        return true
    end,
    
    pwd = function(args)
        addOutput(state.currentDir, colors.info)
        return true
    end,
    
    clear = function(args)
        clearScreen()
        state.outputLines = {}
        return true
    end,
    
    cls = function(args)
        return builtins.clear(args)
    end,
    
    echo = function(args)
        local text = table.concat(args, " ")
        addOutput(text, colors.text)
        if state.display then
            writeToDisplay(text .. "\n")
        end
        return true
    end,
    
    history = function(args)
        for i = math.max(1, #state.history - 20), #state.history do
            addOutput(string.format("%5d  %s", i, state.history[i]), colors.text)
        end
        return true
    end,
    
    modem = function(args)
        if #args == 0 then
            addOutput("Usage: modem send <target> <port> <message>", colors.warning)
            addOutput("       modem status", colors.warning)
            return true
        end
        
        if args[1] == "status" then
            if state.modem then
                addOutput("Modem: Connected on port " .. config.modemPort, colors.success)
            else
                addOutput("Modem: Not connected", colors.error)
            end
            return true
        elseif args[1] == "send" and #args >= 4 then
            local target = args[2]
            local port = tonumber(args[3])
            local message = table.concat(args, " ", 4)
            sendModemMessage(target, port, message)
            return true
        else
            addOutput("Invalid modem command", colors.error)
            return true
        end
    end,
    
    display = function(args)
        if not state.display then
            addOutput("No display connected", colors.error)
            return true
        end
        
        if #args == 0 then
            addOutput("Usage: display <text>", colors.warning)
            addOutput("       display clear", colors.warning)
            return true
        end
        
        if args[1] == "clear" then
            state.display.clear()
            addOutput("Display cleared", colors.success)
        else
            local text = table.concat(args, " ")
            writeToDisplay(text .. "\n")
            addOutput("Sent to display: " .. text, colors.success)
        end
        return true
    end,
    
    exit = function(args)
        addOutput("Goodbye!", colors.info)
        state.running = false
        return false
    end,
    
    quit = function(args)
        return builtins.exit(args)
    end
}

-- Execute command
local function executeCommand(input)
    if input == "" then return true end
    
    addToHistory(input)
    
    -- Parse command
    local args = {}
    for arg in input:gmatch("%S+") do
        table.insert(args, arg)
    end
    
    local command = args[1]
    table.remove(args, 1)
    
    -- Check builtin commands
    if builtins[command] then
        return builtins[command](args)
    else
        -- Try to run as external program
        local success, result = pcall(function()
            return shell.run(input)
        end)
        
        if not success then
            addOutput("Command not found: " .. command, colors.error)
            addOutput("Type 'help' for available commands", colors.warning)
        end
        return true
    end
end

-- Handle input
local function handleInput()
    local eventData = {os.pullEvent()}
    local event = eventData[1]
    
    if event == "key" then
        local key = eventData[2]
        
        -- Enter key
        if key == keys.enter then
            if state.currentInput ~= "" then
                addOutput(config.prompt .. state.currentInput, colors.prompt)
                executeCommand(state.currentInput)
                state.currentInput = ""
                state.cursorPos = 0
                clearInputLine()
                drawPrompt()
            end
        -- Backspace
        elseif key == keys.backspace then
            if state.cursorPos > 0 then
                state.currentInput = state.currentInput:sub(1, state.cursorPos-1) .. 
                                    state.currentInput:sub(state.cursorPos+1)
                state.cursorPos = state.cursorPos - 1
                clearInputLine()
                drawPrompt()
            end
        -- Delete
        elseif key == keys.delete then
            if state.cursorPos < #state.currentInput then
                state.currentInput = state.currentInput:sub(1, state.cursorPos) .. 
                                    state.currentInput:sub(state.cursorPos+2)
                clearInputLine()
                drawPrompt()
            end
        -- Left arrow
        elseif key == keys.left then
            if state.cursorPos > 0 then
                state.cursorPos = state.cursorPos - 1
                drawPrompt()
            end
        -- Right arrow
        elseif key == keys.right then
            if state.cursorPos < #state.currentInput then
                state.cursorPos = state.cursorPos + 1
                drawPrompt()
            end
        -- Up arrow (history)
        elseif key == keys.up then
            if state.historyIndex > 0 then
                state.currentInput = state.history[state.historyIndex]
                state.cursorPos = #state.currentInput
                state.historyIndex = state.historyIndex - 1
                clearInputLine()
                drawPrompt()
            end
        -- Down arrow (history)
        elseif key == keys.down then
            if state.historyIndex < #state.history then
                state.historyIndex = state.historyIndex + 1
                state.currentInput = state.history[state.historyIndex] or ""
                state.cursorPos = #state.currentInput
                clearInputLine()
                drawPrompt()
            elseif state.historyIndex == #state.history then
                state.currentInput = ""
                state.cursorPos = 0
                state.historyIndex = state.historyIndex + 1
                clearInputLine()
                drawPrompt()
            end
        -- Home key
        elseif key == keys.home then
            state.cursorPos = 0
            drawPrompt()
        -- End key
        elseif key == keys.end then
            state.cursorPos = #state.currentInput
            drawPrompt()
        end
    elseif event == "char" then
        local char = eventData[2]
        if char and #char == 1 and char:byte() >= 32 then
            state.currentInput = state.currentInput:sub(1, state.cursorPos) .. char .. 
                                state.currentInput:sub(state.cursorPos+1)
            state.cursorPos = state.cursorPos + 1
            clearInputLine()
            drawPrompt()
        end
    elseif event == "modem_message" then
        local side, channel, replyChannel, message, distance = eventData[2], eventData[3], eventData[4], eventData[5], eventData[6]
        addOutput("[Modem] From " .. channel .. ":" .. replyChannel .. " -> " .. tostring(message), colors.info)
        drawPrompt()
        return true
    end
    
    return true
end

-- Main shell loop
local function shellLoop()
    clearScreen()
    addOutput("=== ComputerCraft Advanced Shell ===", colors.info)
    addOutput("Type 'help' for commands", colors.success)
    addOutput("Modem and Display support enabled", colors.text)
    addOutput("", colors.text)
    
    drawPrompt()
    
    while state.running do
        local continue = handleInput()
        if not continue then break end
        os.sleep(0.05)
    end
end

-- Initialize and start
local function start()
    -- Get terminal size
    state.termW, state.termH = term.getSize()
    
    -- Initialize peripherals
    initModem()
    initDisplay()
    
    -- Load command history
    loadHistory()
    
    -- Set up modem event handler
    if state.modem then
        os.queueEvent("modem_message")
    end
    
    -- Start main loop
    shellLoop()
    
    -- Cleanup
    saveHistory()
    if state.modem then
        state.modem.close(config.modemPort)
    end
    if state.display then
        state.display.clear()
    end
end

-- Run with error handling
local ok, err = pcall(start)
if not ok then
    term.clear()
    term.setCursorPos(1, 1)
    print("Error: " .. tostring(err))
    print("Press any key to exit...")
    os.pullEvent("key")
end
