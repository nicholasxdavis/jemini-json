local ui = {}
local font = nil
local icon = nil
local heart = nil
local images = {}

-- Shader to treat images as solid color masks 
local mask_shader = nil

function ui.load()
    local status, f = pcall(love.graphics.newFont, "assets/pixelFont.fnt")
    if status then
        font = f
        font:setFilter("nearest", "nearest")
    else
        font = love.graphics.newFont(12)
    end
    
    mask_shader = love.graphics.newShader[[
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec4 tex_color = Texel(texture, texture_coords);
            return vec4(color.rgb, tex_color.a * color.a);
        }
    ]]
    
    local function load_img(key, path)
        local s, img = pcall(love.graphics.newImage, path)
        if s then 
            images[key] = img 
        else
            print("Failed to load: " .. path)
        end
    end

    load_img("icon", "assets/gemini.png")
    load_img("heart", "assets/heart.png")
    load_img("github", "assets/github.png")   
    load_img("youtube", "assets/youtube.png") 
    
    icon = images["icon"]
    heart = images["heart"]
end

function ui.get_font() return font end
function ui.get_line_height(scale) return font:getHeight() * scale end
function ui.width(text, scale)
    scale = scale or 3
    if font then return font:getWidth(text) * scale else return 0 end
end

function ui.draw_icon(x, y, w, h)
    if icon then
        love.graphics.setColor(1, 1, 1)
        local sx = w / icon:getWidth()
        local sy = h / icon:getHeight()
        love.graphics.draw(icon, x, y, 0, sx, sy)
    end
end

function ui.draw_heart(x, y, w, h)
    if heart then
        love.graphics.setColor(1, 1, 1)
        local sx = w / heart:getWidth()
        local sy = h / heart:getHeight()
        love.graphics.draw(heart, x, y, 0, sx, sy)
    end
end

-- Updated to support 'raw_color' mode (disables shader)
function ui.draw_img(key, x, y, w, h, raw_color)
    if images[key] then
        local sx = w / images[key]:getWidth()
        local sy = h / images[key]:getHeight()
        
        if raw_color then
            -- Draw raw image (preserving original colors like Red/Black)
            -- We must ensure global color is white so it doesn't tint the image
            local r,g,b,a = love.graphics.getColor()
            love.graphics.setColor(1, 1, 1, a) 
            love.graphics.draw(images[key], x, y, 0, sx, sy)
            love.graphics.setColor(r,g,b,a) -- Restore previous color
        else
            -- Use Mask Shader (Solidify color)
            love.graphics.setShader(mask_shader)
            love.graphics.draw(images[key], x, y, 0, sx, sy)
            love.graphics.setShader()
        end
    else
        -- Fallback: Draw Magenta Box if image missing
        local r,g,b,a = love.graphics.getColor()
        love.graphics.setColor(1, 0, 1)
        love.graphics.rectangle("line", x, y, w, h)
        love.graphics.setColor(r,g,b,a)
    end
end

function ui.draw_panel(x, y, w, h, color)
    love.graphics.setColor(unpack(color))
    love.graphics.rectangle("fill", x, y, w, h)
end

function ui.print(text_or_table, x, y, scale, color_override)
    scale = scale or 3
    love.graphics.setFont(font)
    
    if color_override then
        love.graphics.setColor(unpack(color_override))
    end

    if type(text_or_table) == "table" then
        local status, err = pcall(function() 
            love.graphics.print(text_or_table, x, y, 0, scale, scale)
        end)
        if not status then
            love.graphics.setColor(1, 0, 0)
            love.graphics.print("Error rendering", x, y, 0, scale, scale)
        end
    else
        if not color_override then
            local r,g,b,a = love.graphics.getColor()
            if r==1 and g==1 and b==1 then
                love.graphics.setColor(0.9, 0.9, 0.9)
            end
        end
        love.graphics.print(tostring(text_or_table), x, y, 0, scale, scale)
    end
end

function ui.draw_button(text, x, y, w, h, active)
    local mx, my = love.mouse.getPosition()
    local hover = mx >= x and mx <= x+w and my >= y and my <= y+h
    if active ~= nil then hover = active end
    
    if hover then
        love.graphics.setColor(0.25, 0.25, 0.3)
    else
        love.graphics.setColor(0.18, 0.18, 0.22)
    end
    
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    local txt_w = font:getWidth(text) * 2
    local txt_h = font:getHeight() * 2
    
    love.graphics.setColor(0.95, 0.95, 0.95)
    love.graphics.print(text, x + (w-txt_w)/2, y + (h-txt_h)/2, 0, 2, 2)
end

function ui.button_hit(text, x, y, w, h, mx, my)
    return mx >= x and mx <= x+w and my >= y and my <= y+h
end

return ui