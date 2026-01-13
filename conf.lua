-- conf.lua
function love.conf(t)
    t.window.title = "Jemini"
    t.window.width = 1100
    t.window.height = 700
    t.window.resizable = true
    
    -- DISABLE external console (we have our own in-app one now)
    t.console = false 
end