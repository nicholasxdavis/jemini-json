local json = require "json"
local ui = require "ui"
local utf8 = require "utf8"
-- Wrap icon loading in pcall to prevent crash if assets are missing
local status, icon = pcall(love.image.newImageData, "assets/icon.png")
if status then love.window.setIcon(icon) end

local state = {
    screen = "MENU", 
    project = nil,
    selected_file = 1,
    scroll = 0,
    
    -- Text Editor State
    lines = {},          
    cursor = {line=1, col=0}, 
    selection = nil,     
    mouse_selecting = false,
    blink_timer = 0,
    
    -- Timers
    copy_btn_timer = 0,
    copy_fmt_btn_timer = 0,
    console_copy_btn_timer = 0,
    
    -- Console
    console_open = false,
    console_h = 150,
    console_bar_h = 25,
    console_dragging = false,
    logs = {"System initialized.", "Text Editor Ready."},
    
    -- Scrollbar
    scrollbar_dragging = false,
    
    -- Cursors
    cursor_arrow = love.mouse.getSystemCursor("arrow"),
    cursor_size = love.mouse.getSystemCursor("sizens"),
    cursor_hand = love.mouse.getSystemCursor("hand"),
    cursor_ibeam = love.mouse.getSystemCursor("ibeam")
}

-- --- COLORS & HIGHLIGHTING ---
local colors = {
    keyword = {0.78, 0.47, 0.87}, 
    string  = {0.60, 0.76, 0.47}, 
    comment = {0.36, 0.39, 0.44}, 
    number  = {0.82, 0.60, 0.40}, 
    default = {0.67, 0.70, 0.75}, 
    symbol  = {0.67, 0.70, 0.75},
    
    -- Console Colors
    log_time = {0.8, 0.3, 0.3},
    log_text = {0.7, 0.7, 0.7}
}

local keywords = {
    ["local"]=true, ["function"]=true, ["return"]=true, ["end"]=true, 
    ["if"]=true, ["then"]=true, ["else"]=true, ["elseif"]=true, 
    ["for"]=true, ["while"]=true, ["do"]=true, ["break"]=true,
    ["import"]=true, ["from"]=true, ["def"]=true, ["class"]=true,
    ["try"]=true, ["except"]=true, ["var"]=true, ["let"]=true, ["const"]=true,
    ["true"]=true, ["false"]=true, ["nil"]=true, ["None"]=true
}

function syntax_highlight(line)
    local t = {}
    local i = 1
    local len = #line
    
    while i <= len do
        local char_byte = string.byte(line, i)
        local char = line:sub(i, i)
        
        if char_byte > 127 then
            local offset = utf8.offset(line, 2, i) or (i + 1)
            local seg = line:sub(i, offset - 1)
            table.insert(t, colors.default)
            table.insert(t, seg)
            i = offset
        
        elseif char == "-" and line:sub(i,i+1) == "--" then
            table.insert(t, colors.comment)
            table.insert(t, line:sub(i))
            break
        elseif char == "/" and line:sub(i,i+1) == "//" then
            table.insert(t, colors.comment)
            table.insert(t, line:sub(i))
            break
        elseif char == "#" then
            table.insert(t, colors.comment)
            table.insert(t, line:sub(i))
            break
            
        elseif char == '"' or char == "'" then
            local start = i
            i = i + 1
            while i <= len do
                local c = line:sub(i,i)
                if c == char and line:sub(i-1,i-1) ~= "\\" then break end
                i = i + 1
            end
            table.insert(t, colors.string)
            table.insert(t, line:sub(start, i))
            i = i + 1 
            
        elseif char:match("[%a_]") then
            local start = i
            while i <= len do
                local c = line:sub(i,i)
                if not c:match("[%w_]") then break end
                i = i + 1
            end
            local word = line:sub(start, i-1)
            if keywords[word] then table.insert(t, colors.keyword)
            else table.insert(t, colors.default) end
            table.insert(t, word)
            
        elseif char:match("%d") then
            local start = i
            while i <= len do
                local c = line:sub(i,i)
                if not c:match("[%d%.xX]") then break end
                i = i + 1
            end
            table.insert(t, colors.number)
            table.insert(t, line:sub(start, i-1))
            
        else
            table.insert(t, colors.symbol)
            table.insert(t, char)
            i = i + 1
        end
    end
    return t
end

function colorize_log(msg)
    local t = {}
    local s, e = msg:find("%[%d%d:%d%d:%d%d%]")
    if s then
        table.insert(t, colors.log_time) 
        table.insert(t, msg:sub(s, e) .. " ")
        msg = msg:sub(e + 2)
    end
    table.insert(t, colors.log_text)
    table.insert(t, msg)
    return t
end

-- --- CORE ---

function log(msg)
    table.insert(state.logs, "[" .. os.date("%H:%M:%S") .. "] " .. tostring(msg))
    if #state.logs > 50 then table.remove(state.logs, 1) end 
end

function love.load()
    ui.load()
    love.keyboard.setKeyRepeat(true)
end

function split_lines(str)
    local t = {}
    local function helper(line) table.insert(t, line) return "" end
    helper((str:gsub("(.-)\r?\n", helper)))
    if #t == 0 then table.insert(t, "") end
    return t
end

function update_file_content()
    if state.project and state.project.files[state.selected_file] then
        state.project.files[state.selected_file].content = table.concat(state.lines, "\n")
    end
end

function normalize_project(decoded)
    local project = { project_name = "Imported Project", files = {} }
    if decoded.files and type(decoded.files) == "table" then
        project = decoded
        if not project.project_name then project.project_name = "Untitled" end
    else
        for filename, content in pairs(decoded) do
            if type(filename) == "string" and type(content) == "string" then
                table.insert(project.files, { filename = filename, content = content })
            end
        end
    end
    
    -- Normalize paths: Convert backslashes to forward slashes for consistency
    for _, file in ipairs(project.files) do
        if file.filename then 
            file.filename = file.filename:gsub("\\", "/"):gsub("%.%.", ".") 
        end
    end
    
    table.sort(project.files, function(a,b) return a.filename < b.filename end)
    return project
end

-- ============================================================

function get_char_at_x(line_str, target_x, scale)
    local font = ui.get_font()
    local current_x = 0
    local len = #line_str
    
    local i = 1
    while i <= len do
        local offset = utf8.offset(line_str, 2, i) or (len + 1)
        local char = line_str:sub(i, offset - 1)
        
        local w = 10 
        if pcall(function() w = font:getWidth(char) * scale end) then end
        
        if target_x < current_x + (w/2) then return i - 1 end
        current_x = current_x + w
        i = offset
    end
    return len
end

function get_editor_metrics()
    local w, h = love.graphics.getDimensions()
    local console_h = state.console_open and state.console_h or 0
    local editor_h = h - 40 - console_h
    local line_h = ui.get_line_height(3) 
    return 220, 40, w - 220, editor_h, line_h
end

function get_mouse_text_pos(mx, my)
    local bx, by, bw, bh, line_h = get_editor_metrics()
    local rel_y = my - by - state.scroll - 42 
    local line_idx = math.floor(rel_y / line_h) + 1
    if line_idx < 1 then line_idx = 1 end
    if line_idx > #state.lines then line_idx = #state.lines end
    local line_str = state.lines[line_idx] or ""
    local col_idx = get_char_at_x(line_str, mx - (bx + 20), 3)
    return line_idx, col_idx
end

function get_selection_range()
    if not state.selection then return nil end
    local s, e = state.selection.start_pos, state.selection.end_pos
    if s.line > e.line or (s.line == e.line and s.col > e.col) then return e, s end
    return s, e
end

function delete_selection()
    local s, e = get_selection_range()
    if not s then return end
    if s.line == e.line then
        local line = state.lines[s.line]
        local pre = line:sub(1, s.col)
        local post = line:sub(e.col + 1)
        state.lines[s.line] = pre .. post
    else
        local first = state.lines[s.line]:sub(1, s.col)
        local last = state.lines[e.line]:sub(e.col + 1)
        state.lines[s.line] = first .. last
        for i = 1, e.line - s.line do table.remove(state.lines, s.line + 1) end
    end
    state.cursor = {line = s.line, col = s.col}
    state.selection = nil
    update_file_content()
end

function get_selected_text()
    local s, e = get_selection_range()
    if not s then return "" end
    if s.line == e.line then return state.lines[s.line]:sub(s.col + 1, e.col) end
    local str = state.lines[s.line]:sub(s.col + 1) .. "\n"
    for i = s.line + 1, e.line - 1 do str = str .. state.lines[i] .. "\n" end
    str = str .. state.lines[e.line]:sub(1, e.col)
    return str
end

function ensure_cursor_visible()
    local bx, by, bw, bh, line_h = get_editor_metrics()
    local cursor_y = (state.cursor.line - 1) * line_h
    local relative_y = cursor_y + state.scroll 
    
    if relative_y < 0 then
        state.scroll = -cursor_y
    elseif relative_y + line_h > bh then
        state.scroll = -(cursor_y + line_h - bh)
    end
end

function love.textinput(t)
    if state.screen ~= "EDITOR" then return end
    if state.selection then delete_selection() end
    local line = state.lines[state.cursor.line]
    local pre = line:sub(1, state.cursor.col)
    local post = line:sub(state.cursor.col + 1)
    state.lines[state.cursor.line] = pre .. t .. post
    state.cursor.col = state.cursor.col + #t
    update_file_content()
    ensure_cursor_visible()
end

function love.keypressed(key)
    if state.screen ~= "EDITOR" then return end
    local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    
    if key == "backspace" then
        if state.selection then delete_selection()
        elseif state.cursor.col > 0 then
            local line = state.lines[state.cursor.line]
            local pre = line:sub(1, state.cursor.col - 1)
            local post = line:sub(state.cursor.col + 1)
            state.lines[state.cursor.line] = pre .. post
            state.cursor.col = state.cursor.col - 1
        elseif state.cursor.line > 1 then
            local curr = state.lines[state.cursor.line]
            local prev = state.lines[state.cursor.line - 1]
            state.cursor.line = state.cursor.line - 1
            state.cursor.col = #prev
            state.lines[state.cursor.line] = prev .. curr
            table.remove(state.lines, state.cursor.line + 1)
        end
        update_file_content()
    elseif key == "return" then
        if state.selection then delete_selection() end
        local line = state.lines[state.cursor.line]
        local pre = line:sub(1, state.cursor.col)
        local post = line:sub(state.cursor.col + 1)
        state.lines[state.cursor.line] = pre
        table.insert(state.lines, state.cursor.line + 1, post)
        state.cursor.line = state.cursor.line + 1
        state.cursor.col = 0
        update_file_content()
    elseif key == "up" then
        if state.cursor.line > 1 then
            state.cursor.line = state.cursor.line - 1
            if state.cursor.col > #state.lines[state.cursor.line] then state.cursor.col = #state.lines[state.cursor.line] end
        end
    elseif key == "down" then
        if state.cursor.line < #state.lines then
            state.cursor.line = state.cursor.line + 1
            if state.cursor.col > #state.lines[state.cursor.line] then state.cursor.col = #state.lines[state.cursor.line] end
        end
    elseif key == "left" then
        if state.cursor.col > 0 then state.cursor.col = state.cursor.col - 1 end
    elseif key == "right" then
        if state.cursor.col < #state.lines[state.cursor.line] then state.cursor.col = state.cursor.col + 1 end
    end
    
    ensure_cursor_visible()
    
    if ctrl and key == "c" then
        love.system.setClipboardText(get_selected_text())
        state.copy_btn_timer = 3.0
        log("Copied selection")
    elseif ctrl and key == "v" then
        local text = love.system.getClipboardText()
        if text then
            if state.selection then delete_selection() end
            local line = state.lines[state.cursor.line]
            local pre = line:sub(1, state.cursor.col)
            local post = line:sub(state.cursor.col + 1)
            state.lines[state.cursor.line] = pre .. text .. post
            state.cursor.col = state.cursor.col + #text
            update_file_content()
            ensure_cursor_visible()
        end
    elseif ctrl and key == "a" then
        state.selection = {start_pos = {line=1, col=0}, end_pos = {line=#state.lines, col=#state.lines[#state.lines]}}
    end
end

function get_support_rect(h)
    local sup_scale = 1.6
    local sup_text_w = ui.width("Support me", sup_scale)
    local heart_size = 17
    local padding = 8
    local total_w = sup_text_w + 5 + heart_size + (padding * 2)
    local total_h = 24
    local x = 12
    local y = h - 35
    return x, y, total_w, total_h, sup_scale, heart_size
end

function love.update(dt)
    state.blink_timer = state.blink_timer + dt
    
    if state.copy_btn_timer > 0 then state.copy_btn_timer = state.copy_btn_timer - dt end
    if state.copy_fmt_btn_timer > 0 then state.copy_fmt_btn_timer = state.copy_fmt_btn_timer - dt end
    if state.console_copy_btn_timer > 0 then state.console_copy_btn_timer = state.console_copy_btn_timer - dt end
    
    local w, h = love.graphics.getDimensions()
    local mx, my = love.mouse.getPosition()
    local current_cursor = state.cursor_arrow
    
    if state.screen == "EDITOR" then
        local bx, by, bw, bh = get_editor_metrics()
        
        -- Text Selection Cursor
        if mx >= bx and mx <= bx + bw - 15 and my >= by and my <= by + bh then
            current_cursor = state.cursor_ibeam
        end
        
        -- Support Group Cursor
        local sx, sy, sw, sh = get_support_rect(h)
        if mx >= sx and mx <= sx + sw and my >= sy and my <= sy + sh then
            current_cursor = state.cursor_hand
        end

        -- Scrollbar dragging logic (Robustified)
        if state.scrollbar_dragging then
            local total_h = #state.lines * ui.get_line_height(3) + 100
            if total_h > bh then
                -- Allow dragging even if mouse drifts outside bar width
                local rel_y = my - 40
                local pct = rel_y / bh
                if pct < 0 then pct = 0 end
                if pct > 1 then pct = 1 end
                state.scroll = -pct * (total_h - bh)
            end
        end
    end
    
    if state.console_open then
        local bar_y = h - state.console_h
        if my >= bar_y and my <= bar_y + state.console_bar_h then
            current_cursor = state.cursor_size
        end
        if state.console_dragging then
            state.console_h = h - my
            if state.console_h < 50 then state.console_h = 50 end
            if state.console_h > h - 100 then state.console_h = h - 100 end
            current_cursor = state.cursor_size
        end
    end

    local function check_btn(x, y, btn_w, btn_h)
        if mx >= x and mx <= x + btn_w and my >= y and my <= y + btn_h then
            current_cursor = state.cursor_hand
        end
    end

    check_btn(w - 160, 5, 150, 30) -- Console Toggle
    if state.screen == "EDITOR" then
        check_btn(w - 320, 5, 150, 30) -- Export
        check_btn(w - 150, 45, 130, 30) -- Copy Content
    end
    
    if state.console_open then
         check_btn(w - 104, h - state.console_h + 2, 95, 20)
    end
    
    if state.screen == "MENU" then
        check_btn(w/2 - 160, h/2 + 50, 150, 50)
        check_btn(w/2 + 10, h/2 + 50, 150, 50)
    end

    if state.mouse_selecting and state.selection then
        local l, c = get_mouse_text_pos(mx, my)
        state.selection.end_pos = {line=l, col=c}
        state.cursor = {line=l, col=c}
        ensure_cursor_visible()
    end
    
    love.mouse.setCursor(current_cursor)
    
    if not love.mouse.isDown(1) then 
        state.console_dragging = false 
        state.scrollbar_dragging = false
        state.mouse_selecting = false
    end
end

function love.filedropped(file)
    file:open("r")
    local data = file:read()
    file:close()
    log("File dropped.")
    local decoded, err = json.decode(data)
    if decoded then
        state.project = normalize_project(decoded)
        state.screen = "EDITOR"
        state.selected_file = 1
        state.lines = split_lines(state.project.files[1].content)
        state.cursor = {line=1, col=0}
        state.selection = nil
        log("Project loaded.")
    else log("JSON Error: " .. tostring(err)) end
end

function load_project_file(filename)
    local contents, _ = love.filesystem.read(filename)
    if contents then
        local decoded, err = json.decode(contents)
        if decoded then
            state.project = normalize_project(decoded)
            state.screen = "EDITOR"
            state.lines = split_lines(state.project.files[1].content)
            log("Loaded " .. filename)
        else
             log("Failed to parse " .. filename .. ": " .. tostring(err))
        end
    end
end

function export_project()
    if not state.project then return end
    update_file_content()
    local save_dir = love.filesystem.getSaveDirectory()
    local export_base = save_dir .. "/Exports"
    local folder_name = state.project.project_name:gsub("[^%w%-_]", "_")
    local full_path = export_base .. "/" .. folder_name
    log("Exporting to: " .. full_path)
    
    local os_name = love.system.getOS()
    
    -- Detect required subdirectories from filenames
    local dirs_to_create = {}
    for _, file in ipairs(state.project.files) do
        local dir = file.filename:match("(.*)/")
        if dir then dirs_to_create[dir] = true end
    end
    
    local batch_content = ""
    
    if os_name == "Windows" then
        -- Windows: Create root dir
        os.execute('mkdir "' .. full_path:gsub("/", "\\") .. '" >nul 2>nul')
        
        batch_content = "@echo off\n"
        batch_content = batch_content .. 'mkdir "' .. full_path:gsub("/", "\\") .. '" >nul 2>nul\n'
        
        -- Windows: Create subdirectories in batch
        for dir, _ in pairs(dirs_to_create) do
            local dir_path = full_path .. "/" .. dir
            -- Run locally to ensure they exist before copying if not using batch immediately
            os.execute('mkdir "' .. dir_path:gsub("/", "\\") .. '" >nul 2>nul')
            -- Add to batch
            batch_content = batch_content .. 'mkdir "' .. dir_path:gsub("/", "\\") .. '" >nul 2>nul\n'
        end
        
    else
        -- Linux/Mac: Create root dir and subdirs
        os.execute('mkdir -p "' .. full_path .. '"')
        for dir, _ in pairs(dirs_to_create) do
            os.execute('mkdir -p "' .. full_path .. '/' .. dir .. '"')
        end
    end
    
    -- Write temp files and copy them
    for i, file in ipairs(state.project.files) do
        local temp_name = "temp_" .. i .. ".dat"
        love.filesystem.write(temp_name, file.content)
        local src = save_dir .. "/" .. temp_name
        local dst = full_path .. "/" .. file.filename
        
        if os_name == "Windows" then
            src = src:gsub("/", "\\")
            dst = dst:gsub("/", "\\")
            batch_content = batch_content .. 'copy /Y "' .. src .. '" "' .. dst .. '" >nul\n'
        else 
            os.execute('cp "' .. src .. '" "' .. dst .. '"') 
        end
    end
    
    if os_name == "Windows" then
        batch_content = batch_content .. 'start "" "' .. full_path:gsub("/", "\\") .. '"\n'
        love.filesystem.write("export_job.bat", batch_content)
        love.system.openURL("file://" .. save_dir .. "/export_job.bat")
        log("Export script started!")
    else
        love.system.openURL("file://" .. full_path)
        log("Export Complete!")
    end
end

function copy_logs_to_clipboard()
    love.system.setClipboardText(table.concat(state.logs, "\n"))
    state.console_copy_btn_timer = 3.0
    log("Logs copied!")
end

function love.wheelmoved(x, y)
    state.scroll = state.scroll + (y * 40)
    if state.scroll > 0 then state.scroll = 0 end
    if state.screen == "EDITOR" then
        local bx, by, bw, bh, line_h = get_editor_metrics()
        local total_h = #state.lines * line_h + 100
        if total_h > bh then
             if state.scroll < -(total_h - bh) then state.scroll = -(total_h - bh) end
        else state.scroll = 0 end
    end
end

function love.mousepressed(x, y, button)
    local w, h = love.graphics.getDimensions()
    
    if state.console_open then
        local bar_y = h - state.console_h
        if x > w - 104 and x < w - 9 and y >= bar_y + 2 and y <= bar_y + 22 then
            copy_logs_to_clipboard() return
        end
        if y >= bar_y and y <= bar_y + state.console_bar_h then
            state.console_dragging = true return 
        end
    end

    if x > w - 160 and y < 40 then
        state.console_open = not state.console_open return
    end

    if state.screen == "EDITOR" then
        if x > w - 300 and x < w - 170 and y < 40 then export_project() return end
        
        if x > w - 150 and x < w - 20 and y > 45 and y < 75 then
            local text_to_copy = get_selected_text()
            if text_to_copy == "" then text_to_copy = table.concat(state.lines, "\n") end
            love.system.setClipboardText(text_to_copy)
            state.copy_btn_timer = 3.0 
            log("Content Copied!")
            return
        end
        
        -- Scroll Bar Check (Priority Over Selection)
        local bx, by, bw, bh = get_editor_metrics()
        if x > w - 20 and y > 40 and y < 40 + bh then 
            state.scrollbar_dragging = true 
            return 
        end
        
        -- Support Link Click
        local sx, sy, sw, sh = get_support_rect(h)
        if x >= sx and x <= sx + sw and y >= sy and y <= sy + sh then
            love.system.openURL("https://buymeacoffee.com/galore")
            return
        end
        
        if x >= bx and x <= bx + bw - 20 and y >= by and y <= by + bh then
            local l, c = get_mouse_text_pos(x, y)
            state.cursor = {line=l, col=c}
            state.selection = {start_pos = {line=l, col=c}, end_pos = {line=l, col=c}}
            state.mouse_selecting = true
            return
        end
        
        if x < 220 and y > 60 then
            local idx = math.floor((y - 70) / 40) + 1
            if state.project.files[idx] then
                update_file_content()
                state.selected_file = idx
                state.lines = split_lines(state.project.files[idx].content)
                state.scroll = 0
                state.selection = nil
                state.cursor = {line=1, col=0}
            end
        end
    end

    if state.screen == "MENU" then
        if ui.button_hit("LOAD EXAMPLE", w/2 - 160, h/2 + 50, 150, 50, x, y) then
            load_project_file("example.json")
        end
        
        if ui.button_hit("COPY FORMAT", w/2 + 10, h/2 + 50, 150, 50, x, y) then
            local content, _ = love.filesystem.read("example.json")
            if content then
                love.system.setClipboardText(content)
                state.copy_fmt_btn_timer = 3.0
                log("Example JSON copied to clipboard.")
            else
                log("Error: example.json not found.")
            end
        end
    end
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    love.graphics.clear(0.08, 0.09, 0.11) 

    ui.draw_panel(0, 0, w, 40, {0.15, 0.16, 0.20}) 
    ui.draw_icon(10, 8, 24, 24) 
    ui.print("JEMINI", 43, 1, 2.85)

    local btn_txt = state.console_open and "HIDE CONSOLE" or "SHOW CONSOLE"
    ui.draw_button(btn_txt, w - 160, 5, 150, 30) 
    if state.screen == "EDITOR" then ui.draw_button("EXPORT FILES", w - 320, 5, 150, 30) end

    if state.screen == "MENU" then draw_menu(w, h)
    elseif state.screen == "EDITOR" then draw_editor(w, h) end
    draw_console(w, h)
end

function draw_menu(w, h)
    local txt = "DROP JSON HERE"
    local txt_w = ui.width(txt, 5) 
    local center_x = (w / 2) - (txt_w / 2)
    ui.print(txt, center_x, h/2 - 50, 5)
    
    ui.draw_button("LOAD EXAMPLE", w/2 - 160, h/2 + 50, 150, 50)
    
    local fmt_txt = (state.copy_fmt_btn_timer > 0) and "COPIED" or "COPY FORMAT"
    ui.draw_button(fmt_txt, w/2 + 10, h/2 + 50, 150, 50)
end

function draw_editor(w, h)
    local sidebar_w = 220
    local bx, by, bw, bh, line_h = get_editor_metrics()

    ui.draw_panel(0, 40, sidebar_w, h-40, {0.12, 0.13, 0.16})
    
    love.graphics.setColor(1, 1, 1) 
    ui.print("EXPLORER", 10, 48, 2)
    
    -- Support Link Group
    local sx, sy, sw, sh, s_scale, h_size = get_support_rect(h)
    local mx, my = love.mouse.getPosition()
    local hovered = mx >= sx and mx <= sx + sw and my >= sy and my <= sy + sh
    
    if hovered then
        love.graphics.setColor(0.25, 0.25, 0.3) -- Button Hover Color
        love.graphics.rectangle("fill", sx, sy, sw, sh, 4, 4)
    end
    
    love.graphics.setColor(0.5, 0.5, 0.6)
    if hovered then love.graphics.setColor(0.95, 0.95, 0.95) end
    
    ui.print("Support me", sx + 6, sy + 3, s_scale)
    local txt_w = ui.width("Support me", s_scale)
    ui.draw_heart(sx + 6 + txt_w + 5, sy + 5.5, h_size, h_size) -- Moved to 5.5 (down 0.5 more from 5)
    
    -- File List
    for i, file in ipairs(state.project.files) do
        local fy = 70 + (i-1)*40
        if i == state.selected_file then
            love.graphics.setColor(0.2, 0.25, 0.35)
            love.graphics.rectangle("fill", 5, fy, sidebar_w-10, 35)
        end
        love.graphics.setColor(1, 1, 1)
        
        -- == MODIFIED SECTION: Truncate and Lowercase ==
        local f_name = file.filename:lower()
        local max_w = sidebar_w - 30
        
        -- If width * 3 (scale) > max width, truncate loop
        if ui.get_font():getWidth(f_name) * 3 > max_w then
            while ui.get_font():getWidth(f_name .. "...") * 3 > max_w and #f_name > 0 do
                f_name = f_name:sub(1, -2)
            end
            f_name = f_name .. "..."
        end
        -- ==============================================
        
        ui.print(f_name, 15, fy - 1, 3) 
    end

    love.graphics.setScissor(bx, by, bw, bh)
    love.graphics.push()
    love.graphics.translate(0, state.scroll)
    
    love.graphics.setColor(0.3, 0.3, 0.35)
    love.graphics.rectangle("fill", bx, by, bw, 40)
    
    love.graphics.setColor(1, 1, 1)
    
    -- Also truncate the filename in the header bar if it's too long
    local header_name = state.project.files[state.selected_file].filename
    local h_max_w = bw - 40
    if ui.get_font():getWidth(header_name) * 3 > h_max_w then
         while ui.get_font():getWidth(header_name .. "...") * 3 > h_max_w and #header_name > 0 do
            header_name = header_name:sub(1, -2)
        end
        header_name = header_name .. "..."
    end
    
    ui.print(header_name, bx + 20, by + 2, 3)
    
    local start_y = by + 50
    local font = ui.get_font()
    
    local s, e = get_selection_range()
    if s then
        love.graphics.setColor(0.2, 0.3, 0.5, 0.6)
        for i = s.line, e.line do
            local line_y = start_y + (i-1)*line_h
            local line_str = state.lines[i]
            local x1 = bx + 20
            local width = 0
            if i == s.line and i == e.line then
                x1 = x1 + font:getWidth(line_str:sub(1, s.col)) * 3
                width = font:getWidth(line_str:sub(s.col+1, e.col)) * 3
            elseif i == s.line then
                x1 = x1 + font:getWidth(line_str:sub(1, s.col)) * 3
                width = font:getWidth(line_str:sub(s.col+1)) * 3 + 10
            elseif i == e.line then
                width = font:getWidth(line_str:sub(1, e.col)) * 3
            else width = font:getWidth(line_str) * 3 + 10 end
            love.graphics.rectangle("fill", x1, line_y, width, line_h)
        end
    end
    
    for i, line in ipairs(state.lines) do
        local ly = start_y + (i-1)*line_h
        if ly + state.scroll > -50 and ly + state.scroll < h + 50 then
            love.graphics.setColor(1, 1, 1, 1) 
            local status, colored = pcall(syntax_highlight, line)
            if status then
                ui.print(colored, bx + 20, ly, 3)
            else
                ui.print(line, bx + 20, ly, 3)
            end
        end
    end
    
    if state.blink_timer % 1 < 0.5 then
        love.graphics.setColor(1, 1, 1)
        local c_line_y = start_y + (state.cursor.line-1)*line_h
        local c_line_str = state.lines[state.cursor.line] or ""
        local c_x_off = font:getWidth(c_line_str:sub(1, state.cursor.col)) * 3
        love.graphics.rectangle("fill", bx + 20 + c_x_off, c_line_y, 2, line_h)
    end
    
    love.graphics.pop()
    love.graphics.setScissor()
    
    local btn_label = (state.copy_btn_timer > 0) and "COPIED" or "COPY"
    ui.draw_button(btn_label, w - 150, 45, 130, 30, false)

    local total_h = #state.lines * line_h + 100
    if total_h > bh then
        local ratio = bh / total_h
        local bar_h = bh * ratio
        if bar_h < 30 then bar_h = 30 end 
        local max_scroll = total_h - bh
        local scroll_pct = -state.scroll / max_scroll
        local bar_y = by + (scroll_pct * (bh - bar_h))
        love.graphics.setColor(0.078, 0.09, 0.11)
        love.graphics.rectangle("fill", w - 12, by, 12, bh)
        love.graphics.setColor(0.298, 0.298, 0.349)
        love.graphics.rectangle("fill", w - 10, bar_y, 8, bar_h, 4, 4)
    end
end

function draw_console(w, h)
    if not state.console_open then return end
    local y = h - state.console_h
    ui.draw_panel(0, y, w, state.console_h, {0.05, 0.05, 0.05})
    love.graphics.setColor(0.298, 0.298, 0.349)
    love.graphics.rectangle("fill", 0, y, w, state.console_bar_h) 
    
    love.graphics.setColor(1, 1, 1)
    ui.print("TERMINAL", 10, y + 1, 2)
    
    local c_btn_label = (state.console_copy_btn_timer > 0) and "COPIED" or "COPY"
    ui.draw_button(c_btn_label, w - 104, y + 2, 95, 20, false)
    
    for i, msg in ipairs(state.logs) do
        local log_y = h - 25 - (#state.logs - i) * 20
        if log_y > y + state.console_bar_h + 5 then 
            local colored = colorize_log(msg)
            ui.print(colored, 10, log_y, 2) 
        end
    end
end