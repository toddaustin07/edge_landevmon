--[[
  Copyright 2021 Todd Austin

  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
  except in compliance with the License. You may obtain a copy of the License at:

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the
  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
  either express or implied. See the License for the specific language governing permissions
  and limitations under the License.


  DESCRIPTION
  
  This is an example SmartThings Edge Driver using the generalized UPnP device library.  It will 
  discover, subscribe to, send commands to, and monitor online/offline status of, UPnP devices found on the network

  ** This code borrows liberally from Samsung SmartThings sample LAN drivers; credit to Patrick Barrett **

--]]

-- Edge libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local cosock = require "cosock"                   -- cosock used only for sleep timer in this module
local socket = require "cosock.socket"
local log = require "log"

-- UPnP library
local upnp = require "UPnP"        

-- Custom capabilities
local capdefs = require "capabilitydefs"

local cap_upnpstate = capabilities.build_cap_from_json_string(capdefs.upnpstate_cap)
capabilities["partyvoice23922.upnpstate"] = cap_upnpstate

local cap_moncontrol = capabilities.build_cap_from_json_string(capdefs.moncontrol_cap)
capabilities["partyvoice23922.moncontrol"] = cap_moncontrol

local cap_upnpname = capabilities.build_cap_from_json_string(capdefs.upnpname_cap)
capabilities["partyvoice23922.upnpname"] = cap_upnpname

local cap_upnpmodel = capabilities.build_cap_from_json_string(capdefs.upnpmodel_cap)
capabilities["partyvoice23922.upnpmodel"] = cap_upnpmodel

local cap_upnpuuid = capabilities.build_cap_from_json_string(capdefs.upnpuuid_cap)
capabilities["partyvoice23922.upnpuuid"] = cap_upnpuuid

local cap_upnpaddr = capabilities.build_cap_from_json_string(capdefs.upnpaddr_cap)
capabilities["partyvoice23922.upnpaddr"] = cap_upnpaddr

local cap_createdev = capabilities.build_cap_from_json_string(capdefs.createdev_cap)
capabilities["partyvoice23922.createanother"] = cap_createdev



-- Module variables
local thisDriver = {}

local newly_added = {}
local rediscover_timer
local unfoundlist = {}

local initialize = false

local devcounter = 1


local function validate_ipaddress(ip)

  local valid = true
  
  if ip then
    local chunks = {ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")}
    if #chunks == 4 then
      for i, v in pairs(chunks) do
        if tonumber(v) > 255 then 
          valid = false
          break
        end
      end
    else
      valid = false
    end
  else
    valid = false
  end
  
  if valid then
    return ip
  else
    return nil
  end
      
end

local function validate_uuid(uuid)

  if uuid then
    local chunks = {uuid:match("^(%x+)%-(%x+)%-(%x+)%-(%x+)-(%x+)$")}
    
    if #chunks == 5 then
      if string.len(chunks[1]) ~= 8 then; return nil; end
      if string.len(chunks[2]) ~= 4 then; return nil; end
      if string.len(chunks[3]) ~= 4 then; return nil; end
      if string.len(chunks[4]) ~= 4 then; return nil; end
      if string.len(chunks[5]) ~= 12 then; return nil; end
      return uuid
    end
  end
  
  return nil
      
end


-- Refresh mobile app device capability attributes
local function update_ST_capattrs(device)
  
  local upnpdev = device:get_field("upnpdevice")
  
  device:emit_event(cap_upnpname.name(upnpdev:devinfo().friendlyName))
  device:emit_event(cap_upnpmodel.model(upnpdev:devinfo().modelName))
  device:emit_event(cap_upnpuuid.uuid(upnpdev.uuid))
  device:emit_event(cap_upnpaddr.addr(upnpdev.ip .. ':' .. tostring(upnpdev.port)))
  
end

-- Callback to handle UPnP device status & config changes; invoked by the UPnP library device monitor 
local function status_changed_callback(device)
  
  log.debug ("Device change callback invoked")

  -- 1.Examine upnp device metadata for important changes (online/offline status, bootid, configid, etc)
  
  local upnpdev = device:get_field("upnpdevice")
  
  if upnpdev.online then
  
    log.info ("Device is back online")
    device:emit_event(cap_upnpstate.state('LAN Device is On'))
    device:emit_event(capabilities.switch.switch('on'))
    
    -- 2.Refresh SmartThings capability attributes
    update_ST_capattrs(device)

    -- 3.Refresh any important values from device and service descriptions
    
    -- 4.Send any necessary commands to device
    
    -- 5.Restart subscription for the device
    
  else
    log.info ("Device has gone offline")
    device:emit_event(cap_upnpstate.state('LAN Device is Off'))
    device:emit_event(capabilities.switch.switch('off'))
  end
end


-- Device has been discovered; perform device startup tasks
local function startup_device(device, upnpdev)

  device:emit_event(cap_upnpstate.state('LAN Device is On'))
  device:emit_event(capabilities.switch.switch('on'))
  upnpdev:init(thisDriver, device)
  update_ST_capattrs(device)

  if device:get_field('upnpmon') == true then
    log.info ('Initializing device monitoring')
    upnpdev:monitor(status_changed_callback, device.preferences.poll) 
  end
  
  device:set_field('upnpuuid', upnpdev.uuid, { ['persist'] = true })
 
end


-- Perform SSDP discovery to find target device on the LAN
local function discover(device, searchtarget, reset)
  log.debug("Starting UPnP discovery")
  
  local known_devices = {}
  local found_devices = {}

  local device_list = thisDriver:get_devices()
  for _, device in ipairs(device_list) do
    local id = device.device_network_id
    known_devices[id] = true
  end

  local repeat_count = 3
  local waittime = 3                          -- allow LAN devices 3 seconds to respond to discovery requests
  local reset_found = reset
  local discoverytarget = 'upnp:rootdevice'

  -- We'll limit our discovery to repeat_count to minimize unnecessary LAN traffic

  while repeat_count > 0 do
    log.debug("Making discovery request #" .. ((repeat_count*-1)+4) .. '; for target: ' .. searchtarget)
    if repeat_count < 3 then; reset_found = false; end
    
    --****************************************************************************
    upnp.discover(discoverytarget, waittime,   
                  function (upnpdev)
    
                    local id = upnpdev.uuid
                    local ip = upnpdev.ip
                    local name = upnpdev:devinfo().friendlyName
                    
                    if not known_devices[id] and not found_devices[id] then
                      found_devices[id] = true

                      if (id == searchtarget) or (ip == searchtarget) then

                        log.info(string.format("FOUND TARGET DEVICE: %s <%s> at %s", name, id, ip))
                        
                        if device:get_field('upnpinit') == false then
                          device:set_field('upnpinit', true)
                        
                          startup_device(device, upnpdev)
                        end
                        
                        repeat_count = 0

                      else
                        log.debug(string.format("Discovered device not target: %s <%s> at %s", name, id, ip))
                      end
                    end
                  end,
                  true,         -- non-strict validation
                  reset_found   -- reset found devices
                  
    )
    --***************************************************************************
    
    repeat_count = repeat_count - 1
    if repeat_count > 0 then
      socket.sleep(2)                          -- avoid creating network storms
    end
  end
  log.info("Driver is exiting discovery")
end


-- Scheduled re-discover retry routine for uninitialized UPnP connection (stored in unfoundlist table)
local function proc_rediscover()

  if next(unfoundlist) ~= nil then
  
    local targetuuid
  
    log.debug ('Running periodic re-discovery process for uninitialized UPnP connections:')
    for uuid, table in pairs(unfoundlist) do
      log.debug (string.format('\t<%s> (%s)', uuid, table.device.label))
    end
  
  
    upnp.discover('upnp:rootdevice', 3,    
                    function (upnpdev)
      
                      for uuid, table in pairs(unfoundlist) do
                        
                        if uuid == upnpdev.uuid then
                        
                          local device = table.device
                          local callback = table.callback
                          
                          log.info (string.format('UPnP device <%s> (%s) re-discovered at %s', uuid, device.label, upnpdev.ip))
                          
                          unfoundlist[uuid] = nil
                          device:set_field('upnpinit', true)
                          
                          callback(device, upnpdev)
                        end
                      end
                    end,
                    true,          -- non-strict validation
                    false          -- reset found devices
    )
  
     -- give discovery some time to finish
    socket.sleep(5)
    -- Reschedule this routine again if still unfound devices
    if next(unfoundlist) ~= nil then
      rediscover_timer = thisDriver:call_with_delay(20, proc_rediscover, 're-discover routine')
    end
  end
end


local function create_another_device(driver, counter)

  log.info("Creating additional LAN monitor device")
  
  local MFG_NAME = 'SmartThings Community'
  local VEND_LABEL = string.format('LAN Device Monitor #%d', counter)
  local MODEL = 'landevmon_v1'
  local ID = 'landevmon' .. '_' .. socket.gettime()
  local PROFILE = 'landevmon.v1'
  
  log.debug (string.format('Creating additional device: label=<%s>, id=<%s>', VEND_LABEL, ID))

  -- Create device

  local create_device_msg = {
                              type = "LAN",
                              device_network_id = ID,
                              label = VEND_LABEL,
                              profile = PROFILE,
                              manufacturer = MFG_NAME,
                              model = MODEL,
                              vendor_provided_label = VEND_LABEL,
                            }
                      
  assert (driver:try_create_device(create_device_msg), "failed to create additional landevmon device")

end

------------------------------------------------------------------------
--                         COMMAND HANDLERS
------------------------------------------------------------------------

local function handle_monitor_control(driver, device, command)

  log.info(string.format("Monitor control switched to [%s | %s]", command.command, command.args.value))
  
  device:emit_event(cap_moncontrol.switch(command.args.value))
  
  local upnpdev = device:get_field("upnpdevice")
  
  if command.args.value == 'Monitoring On' then
  
    local target
        
    if validate_uuid(device.preferences.uuid) then
      target = device.preferences.uuid
    elseif validate_ipaddress(device.preferences.ipaddr) then
      target = device.preferences.ipaddr
    else
      log.error('No valid IP address or UUID configured in Settings')
      device:emit_event(cap_moncontrol.switch('Monitoring Off'))
      return
    end

    local restart_flag = false
    
    -- Check if target has changed
    if device:get_field('upnpinit') == true then
      if upnpdev then
        if upnpdev.uuid ~= target and upnpdev.ip ~= target then
          device:set_field('upnpinit', false)
          upnpdev:unregister()
        end
      end
    end
  
    if device:get_field('upnpinit') == false then
      log.info ('Initilizing UPnP connection; target=', target)
      device:set_field('upnpmon', true, { ['persist'] = true })
      discover(device, target, true)
    else
      if upnpdev then
        log.info ('Restarting monitoring')
        upnpdev:monitor(status_changed_callback, device.preferences.poll, true)
        device:set_field('upnpmon', true, { ['persist'] = true })
      else
        log.error ('UPnP initialized but metadata is missing')
      end
    end
    
  else    -- switch turned off
    if device:get_field('upnpinit') == true then
      log.info ('Turning off monitoring')
      device:emit_event(cap_upnpstate.state('-unknown-'))
      device:emit_event(capabilities.switch.switch('off'))
      device:set_field('upnpmon', false, { ['persist'] = true })
      if upnpdev then
        upnpdev:unregister()
      end
    end
  end
end


local function handle_createdev(driver, device, command)

  log.debug ('Createdev handler- command received:', command.command)
  
  devcounter = devcounter + 1
  
  create_another_device(driver, devcounter)

end


------------------------------------------------------------------------
--                REQUIRED EDGE DRIVER HANDLERS
------------------------------------------------------------------------

-- Lifecycle handler to initialize existing devices AND newly discovered devices
local function device_init(driver, device)
  
  log.debug(string.format('INIT handler for %s', device.label))

  if device:get_field('upnpmon') == true then
    device:emit_event(cap_moncontrol.switch('Monitoring On'))
  else
    device:emit_event(cap_moncontrol.switch('Monitoring Off'))
  end
  
  -- Re-establish connection with UPnP device (re-discovery)
                                            
  local uuid = device:get_field('upnpuuid')
  
  if uuid then
    -- Store device in unfoundlist table and schedule re-discovery routine
    if next(unfoundlist) == nil then
      unfoundlist[uuid] = { ['device'] = device, ['callback'] = startup_device }
      log.warn ('\tScheduling re-discover routine')
      rediscover_timer = thisDriver:call_with_delay(3, proc_rediscover, 're-discover routine')
    else
      unfoundlist[uuid] = { ['device'] = device, ['callback'] = startup_device }
    end
  end
end


-- Called when device is initially discovered and created in SmartThings
local function device_added (driver, device)

  local id = device.device_network_id

  log.info(string.format('ADDED handler: <%s (%s)> successfully added; device_network_id = %s', device.id, device.label, id))
  
  device:set_field('upnpinit', false)
  device:set_field('upnpmon', false, { ['persist'] = true })
  
  device:emit_event(cap_upnpstate.state('-unknown-'))
  device:emit_event(capabilities.switch.switch('off'))
  device:emit_event(cap_moncontrol.switch('Monitoring Off'))
  
  log.debug ('ADDED handler exiting for ' .. device.label)

end

-- Called when SmartThings thinks the device needs provisioning
local function device_doconfigure (_, device)

  -- Nothing to do here!

end


-- Called when device was deleted via mobile app
local function device_removed(driver, device)
  
  log.info("<" .. device.id .. "> removed")
  
  local upnpdev = device:get_field("upnpdevice")
  
  if upnpdev ~= nil then

    upnpdev:unregister()
    
  else
    log.warn ('No UPnP data found for deleted device')                 -- this should never happen!
  end
    
end

-- WARNING:  Known issue is that this lifecycle handler may be invoked prior to updating the driver
local function handler_infochanged(driver, device, event, args)

  log.debug ('INFOCHANGED handler; event=', event)
  
  if args.old_st_store.preferences then
  
    if args.old_st_store.preferences.ipaddr ~= device.preferences.ipaddr then
      return
    elseif args.old_st_store.preferences.uuid ~= device.preferences.uuid then
      return
    elseif args.old_st_store.preferences.poll ~= device.preferences.poll then
      return
    elseif args.old_st_store.preferences.devicon ~= device.preferences.devicon then
      return
    else
      -- Assume driver is restarting - shutdown everything
      log.debug ('****** DRIVER RESTART ASSUMED - POSSIBLE CRASH IMMINENT! ******')
      --upnp.reset(driver)
      
    end
  end
  
  
end


-- If the hub's IP address changes, this handler is called
local function lan_info_changed_handler(driver, hub_ipv4)
  if driver.listen_ip == nil or hub_ipv4 ~= driver.listen_ip then
    log.info("Hub IP address has changed, restarting eventing server and resubscribing")
    
    upnp.reset(driver)                                                  -- reset device monitor and subscription event server
  end
end


local function discovery_handler(driver, _, should_continue)

  if not initialized then
  
    log.info("Creating device")
    
    local MFG_NAME = 'SmartThings Community'
    local VEND_LABEL = 'LAN Device Monitor'
    local MODEL = 'landevmon_v1'
    local ID = 'landevmon' .. '_' .. socket.gettime()
    local PROFILE = 'landevmon.v1'

    -- Create virtual SmartThings device
	
		local create_device_msg = {
																type = "LAN",
																device_network_id = ID,
																label = VEND_LABEL,
																profile = PROFILE,
																manufacturer = MFG_NAME,
																model = MODEL,
																vendor_provided_label = VEND_LABEL,
															}
												
		assert (driver:try_create_device(create_device_msg), "failed to create device")
    
    log.debug("Exiting device creation")
    
  else
    log.info ('Device already created')
  end

end

-----------------------------------------------------------------------
--        DRIVER MAINLINE: Build driver context table
-----------------------------------------------------------------------
thisDriver = Driver("landevmonDriver", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    infoChanged = handler_infochanged,
    doConfigure = device_doconfigure,
    deleted = device_removed,
    removed = device_removed,
  },
  lan_info_changed_handler = lan_info_changed_handler,
  capability_handlers = {
  
    [cap_moncontrol.ID] = {
      [cap_moncontrol.commands.setSwitch.NAME] = handle_monitor_control,
    },
    [cap_createdev.ID] = {
      [cap_createdev.commands.push.NAME] = handle_createdev,
    }
  }
})

log.debug("**** Driver Script Start ****")

log.info("LAN Device Monitor Driver v1 started")

thisDriver:run()
