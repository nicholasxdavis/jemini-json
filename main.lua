local json = require "json"
local ui = require "ui"
local utf8 = require "utf8"

-- Safe Icon Loading
local status, icon = pcall(love.image.newImageData, "assets/icon.png")
if status then love.window.setIcon(icon) end

local state = {
    screen = "MENU", 
    project = nil,
    selected_file = 1,
    scroll = 0,
    
    -- Layout State
    sidebar_w = 220,
    sidebar_scroll = 0,
    sidebar_dragging = false,
    sidebar_scrollbar_dragging = false,
    
    -- Text Editor State
    lines = {},          
    cursor = {line=1, col=0}, 
    selection = nil,     
    mouse_selecting = false,
    blink_timer = 0,
    current_lang = "text",
    
    -- Popup State
    popup = {
        open = false,
        title = "",
        type = "YESNO", -- or "OK"
        on_yes = nil,
        on_no = nil
    },
    
    -- Timers
    copy_btn_timer = 0,
    copy_fmt_btn_timer = 0,
    console_copy_btn_timer = 0,
    
    -- Console
    console_open = false,
    console_h = 150,
    console_bar_h = 25,
    console_dragging = false,
    logs = {"System initialized.", "Ready for JSON drop."},
    
    -- Scrollbar
    scrollbar_dragging = false,
    
    -- Cursors
    cursor_arrow = love.mouse.getSystemCursor("arrow"),
    cursor_size = love.mouse.getSystemCursor("sizens"),
    cursor_h_size = love.mouse.getSystemCursor("sizewe"),
    cursor_hand = love.mouse.getSystemCursor("hand"),
    cursor_ibeam = love.mouse.getSystemCursor("ibeam")
}

-- --- COLORS & HIGHLIGHTING THEMES ---
local colors = {
    keyword = {0.78, 0.47, 0.87}, -- Purple
    string  = {0.60, 0.76, 0.47}, -- Green
    comment = {0.36, 0.39, 0.44}, -- Gray
    number  = {0.82, 0.60, 0.40}, -- Orange
    default = {0.67, 0.70, 0.75}, -- White/Gray
    symbol  = {0.8, 0.8, 0.8},    -- Brackets etc
    tag     = {0.85, 0.35, 0.35}, -- HTML Tags (Redish)
    attr    = {0.82, 0.60, 0.40}, -- HTML Attributes
    
    -- Console Colors
    log_time = {0.8, 0.3, 0.3},
    log_text = {0.7, 0.7, 0.7}
}

-- --- LANGUAGE DEFINITIONS ---
local lang_defs = {
    lua = {
        keywords = {["local"]=true, ["function"]=true, ["return"]=true, ["end"]=true, ["if"]=true, ["then"]=true, ["else"]=true, ["elseif"]=true, ["for"]=true, ["while"]=true, ["do"]=true, ["break"]=true, ["nil"]=true, ["true"]=true, ["false"]=true, ["require"]=true}
    },
    js = { 
        keywords = {["const"]=true, ["let"]=true, ["var"]=true, ["function"]=true, ["return"]=true, ["if"]=true, ["else"]=true, ["for"]=true, ["while"]=true, ["import"]=true, ["export"]=true, ["from"]=true, ["class"]=true, ["extends"]=true, ["require"]=true, ["module"]=true, ["exports"]=true, ["true"]=true, ["false"]=true, ["null"]=true, ["undefined"]=true, ["new"]=true, ["this"]=true, ["async"]=true, ["await"]=true}
    },
    py = { 
        keywords = {["def"]=true, ["class"]=true, ["return"]=true, ["if"]=true, ["elif"]=true, ["else"]=true, ["for"]=true, ["while"]=true, ["break"]=true, ["continue"]=true, ["import"]=true, ["from"]=true, ["try"]=true, ["except"]=true, ["True"]=true, ["False"]=true, ["None"]=true, ["and"]=true, ["or"]=true, ["not"]=true, ["in"]=true, ["is"]=true, ["with"]=true, ["as"]=true}
    },
    rust = { 
        keywords = {["fn"]=true, ["let"]=true, ["mut"]=true, ["if"]=true, ["else"]=true, ["match"]=true, ["loop"]=true, ["while"]=true, ["for"]=true, ["return"]=true, ["pub"]=true, ["struct"]=true, ["enum"]=true, ["impl"]=true, ["use"]=true, ["mod"]=true, ["crate"]=true, ["true"]=true, ["false"]=true}
    },
    c = { 
        keywords = {["int"]=true, ["char"]=true, ["void"]=true, ["return"]=true, ["if"]=true, ["else"]=true, ["for"]=true, ["while"]=true, ["struct"]=true, ["class"]=true, ["public"]=true, ["private"]=true, ["include"]=true, ["define"]=true, ["true"]=true, ["false"]=true}
    },
    json = {
        keywords = {["true"]=true, ["false"]=true, ["null"]=true}
    },
    html = {
        keywords = {}
    }
}

-- Map extensions
local ext_map = {
    ["lua"] = "lua",
    ["js"] = "js", ["jsx"] = "js", ["ts"] = "js", ["tsx"] = "js",
    ["py"] = "py", ["pyw"] = "py",
    ["rs"] = "rust",
    ["c"] = "c", ["cpp"] = "c", ["h"] = "c", ["hpp"] = "c", ["java"] = "c",
    ["json"] = "json",
    ["html"] = "html", ["htm"] = "html", ["xml"] = "html",
    ["css"] = "css",
    ["md"] = "text", ["txt"] = "text"
}

function get_language(filename)
    if not filename then return "text" end
    local ext = filename:match("^.+(%.[^%./]+)$")
    if ext then
        ext = ext:sub(2):lower() 
        return ext_map[ext] or "text"
    end
    if filename == "Makefile" then return "text" end
    return "text"
end

-- --- SYNTAX HIGHLIGHTING ---

function syntax_highlight(line, lang)
    lang = lang or "text"
    local t = {}
    local i = 1
    local len = #line
    local current_keywords = (lang_defs[lang] and lang_defs[lang].keywords) or {}
    
    while i <= len do
        local char = line:sub(i, i)
        if lang == "html" and char == "<" then
             local start = i
             i = i + 1
             while i <= len do
                 if line:sub(i,i) == ">" then break end
                 i = i + 1
             end
             table.insert(t, colors.tag)
             table.insert(t, line:sub(start, i))
             i = i + 1
        elseif char == '"' or char == "'" or (lang == "js" and char == "`") then
            local quote = char
            local start = i
            i = i + 1
            while i <= len do
                local c = line:sub(i,i)
                if c == quote and line:sub(i-1,i-1) ~= "\\" then break end
                i = i + 1
            end
            table.insert(t, colors.string)
            table.insert(t, line:sub(start, i))
            i = i + 1 
        elseif (lang == "lua" and char == "-" and line:sub(i,i+1) == "--") or
               ((lang == "js" or lang == "c" or lang == "rust" or lang == "java") and char == "/" and line:sub(i,i+1) == "//") or
               ((lang == "py") and char == "#") then
            table.insert(t, colors.comment)
            table.insert(t, line:sub(i))
            break
        elseif char:match("[%a_]") then
            local start = i
            while i <= len do
                local c = line:sub(i,i)
                if not c:match("[%w_]") then break end
                i = i + 1
            end
            local word = line:sub(start, i-1)
            if current_keywords[word] then 
                table.insert(t, colors.keyword)
            else 
                table.insert(t, colors.default) 
            end
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

function log(msg)
    table.insert(state.logs, "[" .. os.date("%H:%M:%S") .. "] " .. tostring(msg))
    if #state.logs > 50 then table.remove(state.logs, 1) end 
end

function love.load()
    ui.load()
    love.keyboard.setKeyRepeat(true)
end

function split_lines(str)
    if not str then return {""} end
    local t = {}
    local function helper(line) table.insert(t, line) return "" end
    helper((str:gsub("\r\n", "\n"):gsub("(.-)\n", helper)))
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
    if decoded.project_name then project.project_name = decoded.project_name end
    if decoded.files and type(decoded.files) == "table" then
        project.files = decoded.files
    else
        for k, v in pairs(decoded) do
            if k ~= "project_name" and type(k) == "string" and type(v) == "string" then
                table.insert(project.files, { filename = k, content = v })
            end
        end
    end
    for _, file in ipairs(project.files) do
        if not file.filename and file.name then file.filename = file.name end
        if file.filename then
            file.filename = file.filename:gsub("\\", "/"):gsub("%.%.", "")
            while file.filename:sub(1,1) == "/" do file.filename = file.filename:sub(2) end
        end
        if not file.content then file.content = "" end
        if type(file.content) ~= "string" then file.content = tostring(file.content) end
    end
    table.sort(project.files, function(a,b) return (a.filename or "") < (b.filename or "") end)
    return project
end

function show_popup(text, type, on_yes, on_no)
    state.popup.title = text
    state.popup.type = type or "OK"
    state.popup.on_yes = on_yes
    state.popup.on_no = on_no
    state.popup.open = true
end

-- ============================================================
-- TEXT EDITOR METRICS
-- ============================================================

function get_editor_metrics()
    local w, h = love.graphics.getDimensions()
    local console_h = state.console_open and state.console_h or 0
    local editor_h = h - 40 - console_h
    local line_h = ui.get_line_height(3) 
    return state.sidebar_w, 40, w - state.sidebar_w, editor_h, line_h
end

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

-- --- INPUT HANDLING ---

function love.textinput(t)
    if state.popup.open then return end
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
    if state.popup.open then return end
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
    elseif ctrl and key == "v" then
        local text = love.system.getClipboardText()
        if text then
            if state.selection then delete_selection() end
            local lines = split_lines(text)
            local line = state.lines[state.cursor.line]
            local pre = line:sub(1, state.cursor.col)
            local post = line:sub(state.cursor.col + 1)
            
            if #lines == 1 then
                state.lines[state.cursor.line] = pre .. lines[1] .. post
                state.cursor.col = state.cursor.col + #lines[1]
            else
                state.lines[state.cursor.line] = pre .. lines[1]
                for i=2, #lines-1 do
                    table.insert(state.lines, state.cursor.line + i - 1, lines[i])
                end
                table.insert(state.lines, state.cursor.line + #lines - 1, lines[#lines] .. post)
                state.cursor.line = state.cursor.line + #lines - 1
                state.cursor.col = #lines[#lines]
            end
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
    if state.console_open then y = y - state.console_h end
    return x, y, total_w, total_h, sup_scale, heart_size
end

function get_bottom_right_links(w, h)
    local scale = 1.6
    local icon_size = 14
    local margin = 15
    local gap = 20 -- Vertical gap between rows
    
    -- Tutorial Row (Bottom)
    local tut_txt = "Tutorial"
    local tut_txt_w = ui.width(tut_txt, scale)
    local tut_y = h - margin - icon_size
    local tut_icon_x = w - margin - icon_size
    local tut_txt_x = tut_icon_x - 5 - tut_txt_w
    
    -- Github Row (Above Tutorial)
    local git_txt = "Github"
    local git_txt_w = ui.width(git_txt, scale)
    local git_y = tut_y - gap
    local git_icon_x = w - margin - icon_size
    local git_txt_x = git_icon_x - 5 - git_txt_w
    
    -- Center icons vertically relative to text line height (approx 19px for scale 1.6)
    local text_h = ui.get_line_height(scale)
    local icon_offset_y = (text_h - icon_size) / 2
    
    return {
        tut = {x=tut_txt_x, y=tut_y, w=tut_txt_w + 5 + icon_size, h=icon_size, icon_x=tut_icon_x, icon_y = tut_y + icon_offset_y},
        git = {x=git_txt_x, y=git_y, w=git_txt_w + 5 + icon_size, h=icon_size, icon_x=git_icon_x, icon_y = git_y + icon_offset_y},
        scale = scale,
        icon_size = icon_size
    }
end

function love.update(dt)
    if state.popup.open then return end
    
    state.blink_timer = state.blink_timer + dt
    
    if state.copy_btn_timer > 0 then state.copy_btn_timer = state.copy_btn_timer - dt end
    if state.copy_fmt_btn_timer > 0 then state.copy_fmt_btn_timer = state.copy_fmt_btn_timer - dt end
    if state.console_copy_btn_timer > 0 then state.console_copy_btn_timer = state.console_copy_btn_timer - dt end
    
    local w, h = love.graphics.getDimensions()
    local mx, my = love.mouse.getPosition()
    local current_cursor = state.cursor_arrow
    
    if state.screen == "EDITOR" then
        local bx, by, bw, bh = get_editor_metrics()
        
        -- Resize Sidebar Handling
        if state.sidebar_dragging then
            state.sidebar_w = mx
            if state.sidebar_w < 150 then state.sidebar_w = 150 end
            if state.sidebar_w > w - 100 then state.sidebar_w = w - 100 end
            current_cursor = state.cursor_h_size
        elseif mx >= state.sidebar_w - 5 and mx <= state.sidebar_w + 5 then
            current_cursor = state.cursor_h_size
        else
            -- Text Selection Cursor
            if mx >= bx and mx <= bx + bw - 15 and my >= by and my <= by + bh then
                current_cursor = state.cursor_ibeam
            end
            
            -- Support Group Cursor
            local sx, sy, sw, sh = get_support_rect(h)
            if mx >= sx and mx <= sx + sw and my >= sy and my <= sy + sh then
                current_cursor = state.cursor_hand
            end

            -- Scrollbar dragging logic (Editor)
            if state.scrollbar_dragging then
                local total_h = #state.lines * ui.get_line_height(3) + 100
                if total_h > bh then
                    local rel_y = my - 40
                    local pct = rel_y / bh
                    if pct < 0 then pct = 0 end
                    if pct > 1 then pct = 1 end
                    state.scroll = -pct * (total_h - bh)
                end
            end
            
            -- Sidebar Scrollbar logic
            if state.sidebar_scrollbar_dragging then
                 local list_h = bh - 40 -- approx usable height
                 local total_h = #state.project.files * 40 + 20
                 if total_h > list_h then
                     local rel_y = my - 60
                     local pct = rel_y / list_h
                     if pct < 0 then pct = 0 end
                     if pct > 1 then pct = 1 end
                     state.sidebar_scroll = -pct * (total_h - list_h)
                 end
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

    -- Icon Hover for Main Menu
    check_btn(0, 0, 180, 40) -- Top left area

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
        
        -- Check hover for bottom right links
        local lnks = get_bottom_right_links(w, h)
        check_btn(lnks.git.x, lnks.git.y, lnks.git.w, lnks.git.h)
        check_btn(lnks.tut.x, lnks.tut.y, lnks.tut.w, lnks.tut.h)
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
        state.sidebar_scrollbar_dragging = false
        state.mouse_selecting = false
        state.sidebar_dragging = false
    end
end

-- --- FILE LOADING ---

function love.filedropped(file)
    if state.popup.open then return end
    file:open("r")
    local data = file:read()
    file:close()
    local decoded, err = json.decode(data)
    if decoded then
        state.project = normalize_project(decoded)
        if #state.project.files == 0 then 
            show_popup("Error: JSON has no files.", "OK")
            return 
        end
        state.screen = "EDITOR"
        state.selected_file = 1
        state.lines = split_lines(state.project.files[1].content)
        state.cursor = {line=1, col=0}
        state.current_lang = get_language(state.project.files[1].filename)
        state.selection = nil
        log("Project loaded.")
    else
        show_popup("Invalid JSON Format", "OK")
    end
end

function load_project_file(filename)
    local contents, _ = love.filesystem.read(filename)
    if contents then
        local decoded, err = json.decode(contents)
        if decoded then
            state.project = normalize_project(decoded)
            state.screen = "EDITOR"
            state.lines = split_lines(state.project.files[1].content)
            state.current_lang = get_language(state.project.files[1].filename)
        else
            show_popup("Failed to parse file", "OK")
        end
    end
end

-- --- EXPORTING ---

function export_project()
    if not state.project or #state.project.files == 0 then 
        show_popup("Nothing to export!", "OK")
        return 
    end
    update_file_content()
    local save_dir = love.filesystem.getSaveDirectory()
    local export_base = save_dir .. "/Exports"
    local folder_name = state.project.project_name:gsub("[^%w%-_]", "_")
    local full_path = export_base .. "/" .. folder_name
    
    local is_win = (love.system.getOS() == "Windows")
    
    -- Helper to collect dirs
    local dirs_needed = {}
    local function add_dirs(path)
        if not path or path == "" or path == "." then return end
        dirs_needed[path] = true
        local parent = path:match("^(.*)/[^/]+$")
        if parent then add_dirs(parent) end
    end
    
    for _, file in ipairs(state.project.files) do
        local dir = file.filename:match("^(.*)/[^/]+$")
        if dir then add_dirs(dir) end
    end
    
    local sorted_dirs = {}
    for dir, _ in pairs(dirs_needed) do table.insert(sorted_dirs, dir) end
    table.sort(sorted_dirs)
    
    local batch_content = ""
    if is_win then
        batch_content = "@echo off\n"
        batch_content = batch_content .. 'mkdir "' .. full_path:gsub("/", "\\") .. '" >nul 2>nul\n'
        for _, dir in ipairs(sorted_dirs) do
            local dir_path = full_path .. "/" .. dir
            batch_content = batch_content .. 'mkdir "' .. dir_path:gsub("/", "\\") .. '" >nul 2>nul\n'
        end
    else
        os.execute('mkdir -p "' .. full_path .. '"')
        for _, dir in ipairs(sorted_dirs) do
            os.execute('mkdir -p "' .. full_path .. '/' .. dir .. '"')
        end
    end
    
    for i, file in ipairs(state.project.files) do
        local temp_name = "temp_" .. i .. ".dat"
        love.filesystem.write(temp_name, file.content)
        local src = save_dir .. "/" .. temp_name
        local dst = full_path .. "/" .. file.filename
        
        if is_win then
            src = src:gsub("/", "\\")
            dst = dst:gsub("/", "\\")
            batch_content = batch_content .. 'copy /Y "' .. src .. '" "' .. dst .. '" >nul\n'
            batch_content = batch_content .. 'del "' .. src .. '" >nul\n' 
        else 
            os.execute('cp "' .. src .. '" "' .. dst .. '"')
            love.filesystem.remove(temp_name)
        end
    end
    
    if is_win then
        batch_content = batch_content .. 'start "" "' .. full_path:gsub("/", "\\") .. '"\n'
        love.filesystem.write("export_job.bat", batch_content)
        love.system.openURL("file://" .. save_dir .. "/export_job.bat")
    else
        love.system.openURL("file://" .. full_path)
    end
end

function love.wheelmoved(x, y)
    if state.popup.open then return end
    
    local mx, my = love.mouse.getPosition()
    -- Sidebar Scrolling Logic
    if state.screen == "EDITOR" and mx < state.sidebar_w then
        local bx, by, bw, bh = get_editor_metrics()
        local list_h = bh - 40 -- approx usable height
        local total_h = #state.project.files * 40 + 20
        
        if total_h > list_h then
            state.sidebar_scroll = state.sidebar_scroll + (y * 40)
            -- Clamp
            if state.sidebar_scroll > 0 then state.sidebar_scroll = 0 end
            if state.sidebar_scroll < -(total_h - list_h) then state.sidebar_scroll = -(total_h - list_h) end
        end
        return
    end

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

    -- POPUP HANDLING
    if state.popup.open then
        local pw, ph = 300, 140
        local px, py = (w - pw)/2, (h - ph)/2
        
        if state.popup.type == "YESNO" then
            -- Check YES
            if ui.button_hit("YES", px + 20, py + 80, 120, 40, x, y) then
                if state.popup.on_yes then state.popup.on_yes() end
                state.popup.open = false
            end
            -- Check NO
            if ui.button_hit("NO", px + 160, py + 80, 120, 40, x, y) then
                if state.popup.on_no then state.popup.on_no() end
                state.popup.open = false
            end
        else -- OK Type
            if ui.button_hit("OK", px + 90, py + 80, 120, 40, x, y) then
                state.popup.open = false
            end
        end
        return
    end
    
    -- CLICK MAIN MENU TRIGGER
    if x < 180 and y < 40 then
        show_popup("Proceed to main menu?", "YESNO", function()
             state.screen = "MENU"
             state.project = nil
        end)
        return
    end
    
    if state.console_open then
        local bar_y = h - state.console_h
        if x > w - 104 and x < w - 9 and y >= bar_y + 2 and y <= bar_y + 22 then
            love.system.setClipboardText(table.concat(state.logs, "\n"))
            state.console_copy_btn_timer = 3.0
            return
        end
        if y >= bar_y and y <= bar_y + state.console_bar_h then
            state.console_dragging = true return 
        end
    end

    if x > w - 160 and y < 40 then
        state.console_open = not state.console_open return
    end

    if state.screen == "EDITOR" then
        -- Resize Sidebar Start
        if x >= state.sidebar_w - 5 and x <= state.sidebar_w + 5 then
            state.sidebar_dragging = true
            return
        end

        if x > w - 300 and x < w - 170 and y < 40 then export_project() return end
        
        if x > w - 150 and x < w - 20 and y > 45 and y < 75 then
            local text_to_copy = get_selected_text()
            if text_to_copy == "" then text_to_copy = table.concat(state.lines, "\n") end
            love.system.setClipboardText(text_to_copy)
            state.copy_btn_timer = 3.0 
            return
        end
        
        local bx, by, bw, bh = get_editor_metrics()
        
        -- Editor Scroll Bar Check
        if x > w - 20 and y > 40 and y < 40 + bh then 
            state.scrollbar_dragging = true 
            return 
        end
        
        -- Sidebar Scroll Bar Check
        if x > state.sidebar_w - 12 and x < state.sidebar_w and y > 60 then
            state.sidebar_scrollbar_dragging = true
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
        
        if x < state.sidebar_w - 12 and y > 60 then
            -- Account for scroll
            local rel_y = y - 70 - state.sidebar_scroll
            local idx = math.floor(rel_y / 40) + 1
            if idx > 0 and state.project.files[idx] then
                update_file_content()
                state.selected_file = idx
                state.lines = split_lines(state.project.files[idx].content)
                state.current_lang = get_language(state.project.files[idx].filename)
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
            end
        end
        
        -- Check External Links
        local lnks = get_bottom_right_links(w, h)
        if ui.button_hit("", lnks.git.x, lnks.git.y, lnks.git.w, lnks.git.h, x, y) then
             love.system.openURL("https://github.com/nicholasxdavis/jemini-json")
        end
        if ui.button_hit("", lnks.tut.x, lnks.tut.y, lnks.tut.w, lnks.tut.h, x, y) then
             love.system.openURL("https://example.com")
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
    
    if state.popup.open then draw_popup(w, h) end
end

function draw_menu(w, h)
    local txt = "DROP JSON HERE"
    local txt_w = ui.width(txt, 5) 
    local center_x = (w / 2) - (txt_w / 2)
    ui.print(txt, center_x, h/2 - 50, 5)
    ui.draw_button("LOAD EXAMPLE", w/2 - 160, h/2 + 50, 150, 50)
    local fmt_txt = (state.copy_fmt_btn_timer > 0) and "COPIED" or "COPY FORMAT"
    ui.draw_button(fmt_txt, w/2 + 10, h/2 + 50, 150, 50)
    
    -- Draw Bottom Right Links
    local lnks = get_bottom_right_links(w, h)
    
    -- Hover effect Github
    local mx, my = love.mouse.getPosition()
    local git_hover = mx >= lnks.git.x and mx <= lnks.git.x + lnks.git.w and my >= lnks.git.y and my <= lnks.git.y + lnks.git.h
    if git_hover then love.graphics.setColor(1, 1, 1) else love.graphics.setColor(0.6, 0.6, 0.65) end
    ui.print("Github", lnks.git.x, lnks.git.y, lnks.scale)
    -- pass 'true' to disable shader and draw raw color
    ui.draw_img("github", lnks.git.icon_x, lnks.git.icon_y, lnks.icon_size, lnks.icon_size, true)
    
    -- Hover effect Tutorial
    local tut_hover = mx >= lnks.tut.x and mx <= lnks.tut.x + lnks.tut.w and my >= lnks.tut.y and my <= lnks.tut.y + lnks.tut.h
    if tut_hover then love.graphics.setColor(1, 1, 1) else love.graphics.setColor(0.6, 0.6, 0.65) end
    ui.print("Tutorial", lnks.tut.x, lnks.tut.y, lnks.scale)
    -- pass 'true' to disable shader and draw raw color
    ui.draw_img("youtube", lnks.tut.icon_x, lnks.tut.icon_y, lnks.icon_size, lnks.icon_size, true)
end

function draw_editor(w, h)
    local bx, by, bw, bh, line_h = get_editor_metrics()

    ui.draw_panel(0, 40, state.sidebar_w, h-40, {0.12, 0.13, 0.16})
    
    love.graphics.setColor(1, 1, 1) 
    ui.print("EXPLORER", 10, 48, 2)
    
    -- Support Link Group calculations
    local sx, sy, sw, sh, s_scale, h_size = get_support_rect(h)
    
    -- SCISSOR START FOR FILE LIST
    local list_h = h - 70 - 45 
    if state.console_open then list_h = list_h - state.console_h end
    love.graphics.setScissor(0, 70, state.sidebar_w, list_h)
    
    love.graphics.push()
    love.graphics.translate(0, state.sidebar_scroll)

    -- File List
    for i, file in ipairs(state.project.files) do
        local fy = 70 + (i-1)*40
        
        if fy + state.sidebar_scroll > 30 and fy + state.sidebar_scroll < h then
            if i == state.selected_file then
                love.graphics.setColor(0.2, 0.25, 0.35)
                love.graphics.rectangle("fill", 5, fy, state.sidebar_w - 15, 35)
            end
            love.graphics.setColor(1, 1, 1)
            
            local f_name = file.filename:lower()
            local max_w = state.sidebar_w - 35
            
            if ui.get_font():getWidth(f_name) * 3 > max_w then
                while ui.get_font():getWidth(f_name .. "...") * 3 > max_w and #f_name > 0 do
                    f_name = f_name:sub(1, -2)
                end
                f_name = f_name .. "..."
            end
            
            ui.print(f_name, 15, fy - 1, 3) 
        end
    end
    
    love.graphics.pop()
    love.graphics.setScissor() -- SCISSOR END
    
    -- SIDEBAR SCROLLBAR
    local total_files_h = #state.project.files * 40 + 20
    if total_files_h > list_h then
        local ratio = list_h / total_files_h
        local s_bar_h = list_h * ratio
        if s_bar_h < 30 then s_bar_h = 30 end
        local max_s_scroll = total_files_h - list_h
        local s_pct = -state.sidebar_scroll / max_s_scroll
        local s_bar_y = 70 + (s_pct * (list_h - s_bar_h))
        
        love.graphics.setColor(0.1, 0.1, 0.12)
        love.graphics.rectangle("fill", state.sidebar_w - 10, 70, 8, list_h)
        love.graphics.setColor(0.25, 0.25, 0.3)
        love.graphics.rectangle("fill", state.sidebar_w - 10, s_bar_y, 8, s_bar_h, 4, 4)
    end
    
    -- DRAW SUPPORT BUTTON (ON TOP)
    ui.draw_panel(0, sy - 8, state.sidebar_w, sh + 16, {0.117, 0.129, 0.156}) 
    
    local mx, my = love.mouse.getPosition()
    local hovered = mx >= sx and mx <= sx + sw and my >= sy and my <= sy + sh
    
    if hovered then
        love.graphics.setColor(0.25, 0.25, 0.3)
        love.graphics.rectangle("fill", sx, sy, sw, sh, 4, 4)
    end
    
    love.graphics.setColor(0.5, 0.5, 0.6)
    if hovered then love.graphics.setColor(0.95, 0.95, 0.95) end
    
    ui.print("Support me", sx + 6, sy + 3, s_scale)
    local txt_w = ui.width("Support me", s_scale)
    ui.draw_heart(sx + 6 + txt_w + 5, sy + 5.5, h_size, h_size) 

    -- EDITOR AREA
    love.graphics.setScissor(bx, by, bw, bh)
    love.graphics.push()
    love.graphics.translate(0, state.scroll)
    
    love.graphics.setColor(0.3, 0.3, 0.35)
    love.graphics.rectangle("fill", bx, by, bw, 40)
    
    love.graphics.setColor(1, 1, 1)
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
            local status, colored = pcall(syntax_highlight, line, state.current_lang)
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

function draw_popup(w, h)
    -- Dim Background
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, w, h)
    
    local pw, ph = 300, 140
    local px, py = (w - pw)/2, (h - ph)/2
    
    -- Popup Box with new color #4c4c59
    ui.draw_panel(px, py, pw, ph, {0.298, 0.298, 0.349}) 
    
    -- Outline
    love.graphics.setColor(0.5, 0.5, 0.55)
    love.graphics.rectangle("line", px, py, pw, ph)
    
    -- Text (Forced White)
    local txt = state.popup.title
    local tw = ui.width(txt, 2.3)
    ui.print(txt, px + (pw-tw)/2, py + 30, 2.3, {1, 1, 1})
    
    if state.popup.type == "YESNO" then
        ui.draw_button("YES", px + 20, py + 80, 120, 40)
        ui.draw_button("NO", px + 160, py + 80, 120, 40)
    else
        ui.draw_button("OK", px + 90, py + 80, 120, 40)
    end
end