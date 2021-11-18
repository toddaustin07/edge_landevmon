
local capabilities = require "st.capabilities"
local log = require "log"

local command_handlers = {}


-- Ignore it (reset switch back to what it was)
function command_handlers.handle_switch_on(_, device)
    log.info("switch changed to ON")
    device:emit_event(capabilities.switch.switch('off'))
    
end

-- Ignore it (reset switch back to what it was)
function command_handlers.handle_switch_off(_, device)
    log.info("switch changed to OFF")
    device:emit_event(capabilities.switch.switch('on'))
end



return command_handlers
