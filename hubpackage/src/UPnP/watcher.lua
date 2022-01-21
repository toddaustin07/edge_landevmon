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
  
  Library file to handle all UPnP device online/offline monitoring-related routines.

--]]
local util = require "UPnP.upnpcommon"
local description = require "UPnP.description"

local cosock = require "cosock"
local socket = require "cosock.socket"

local ltn12 = require "ltn12"

local log = require "log"

local m     -- multicast socket
local u     -- unicast socket

-- socket ip defs
local multicast_ip = "239.255.255.250"
local multicast_port = 1900
local listen_ip = "0.0.0.0"
local listen_port = 0

local EXPIRATIONCHECKTIME = 10.2
local expiration_timer              -- *****

local watchtable = {}
local initflag = false


local function build_msearch_target(devicetable)

  local searchtarget = 'uuid:' .. devicetable.uuid
  
  log.debug ('[upnp] Monitor re-discovery search target: ', devicetable.description.device.friendlyName, searchtarget)
  return searchtarget

end  


-- Scan watch table for expired device states and send discovery messages if needed to see if alive
local function check_expirations()

  local t = math.floor(socket.gettime())
  log.debug ("[upnp] Running device expiration check")
  
  for usn, devicetable in pairs(watchtable) do
  
    if devicetable.online then
      
      if devicetable.expiration < t then
       
        log.info (string.format('[upnp] Polling %s; last exp: %s', devicetable.usn, os.date("%I:%M:%S",devicetable.expiration)))

        devicetable._retries = devicetable._retries + 1
        
        -- Retry unicast search message 2 times to try and get response
        
        if devicetable._retries <= 2 then
      
          local port = devicetable.msearchport or multicast_port
          log.debug (string.format('[upnp] Sending unicast discovery (attempt #%d) to %s:%s', devicetable._retries, devicetable.ip, port))
          assert(u:sendto(util.create_msearch_msg(build_msearch_target(devicetable), 1), devicetable.ip, port))  

        else
        
          -- Unicast didn't yield a response, so now try multicast 3 times
        
          if devicetable._retries <= 5 then
            log.debug (string.format('[upnp] Sending multicast discovery to %s (attempt #%d)', devicetable.st, devicetable._retries-2))
            assert(u:sendto(util.create_msearch_msg(devicetable.st, 2), multicast_ip, multicast_port))
          
          else
            devicetable.online = false
            log.info (string.format('[upnp] Device %s is OFFLINE', devicetable.usn))
            devicetable._changecallback(devicetable.stdevice)
          end
        end  
      end 
    else  
      -- Device is offline
      if devicetable._retries ~= -1 then                  -- _retries == -1 if device sent byebye message or retries already exhausted
        
        -- Try multicast 3 more times (device could have new ip if it rebooted)
        devicetable._retries = devicetable._retries + 1
        
        if (devicetable._retries <= 8) then
          log.debug (string.format('[upnp] Sending multicast discovery (retry #%d)', devicetable._retries))
          assert(u:sendto(util.create_msearch_msg(devicetable.st, 2), multicast_ip, multicast_port)) 
        else
          devicetable._retries = -1
        end
      end 
    end
  end
end


-- called when device was offline and has come back online
local function back_online(devicetable, headers)

  log.info (string.format('[upnp] Device %s is back ONLINE', devicetable.usn))
  
  -- Log warnings if device was rebooted or changed configuration
  
  if headers["bootid.upnp.org"] ~= nil then
    if devicetable.bootid then
      if headers["bootid.upnp.org"] ~= devicetable.bootid then
        log.warn ("[upnp] Device BootID has changed")
      end
    end
  end
  
  if headers["configid.upnp.org"] ~= nil then
    if devicetable.configid then
      if headers["configid.upnp.org"] ~= devicetable.configid then
        log.warn ("[upnp] Device ConfigID has changed")
      end
    end
  end
  
  -- Update devicetable attributes to capture any changes in ip address or boot/config id
  
  util.set_meta_attrs(devicetable, headers)
  
  -- Update device description
  
  local retries = 2
  local meta
  
  while retries > 0 do        -- device might need some time to finish startup
    meta = description.getXML(headers['location'])
    if meta then
      break
    end
    socket.sleep(2)
    retries = retries - 1
  end
  
  if meta then
    devicetable.description = nil         -- help ensure garbage collection(?)
    devicetable.description = meta
  else
    log.warn ('[upnp] Could not update device description')
  end
  
  log.info (string.format('[upnp] %s device metadata refreshed', devicetable.description.device.friendlyName))
  
  devicetable.online = true
  devicetable._changecallback(devicetable.stdevice)

end


-- Update device expiration and other health state attributes
local function update_state(headers, rip)
  
  local id = headers["usn"]
  
  if id ~= nil and
    (id:match("^upnp:rootdevice") or id:match("^uuid") or id:match("^urn:")) then
  
    -- Update expiration if we match
    
    for usn, devicetable in pairs(watchtable) do
     
      if string.find(id, devicetable.uuid, nil, 'plaintext') then     -- any usn containing the target device UUID is good enough
        
        -- Matching UUID, validate Notify or Msearch Response fields
        
        if (headers["nts"] == 'ssdp:alive') or headers["st"] then      -- don't care what's in ST
        
          if headers["cache-control"] ~= nil then
        
            local seconds_to_expire = tonumber(string.match(headers["cache-control"], '%d+'))
            local t = math.floor(socket.gettime())
            local priorexp = os.date("%I:%M:%S", devicetable.expiration)
            
            if devicetable._poll then                                   -- *****
              devicetable.expiration = t + devicetable._poll
            else
              devicetable.expiration = t + seconds_to_expire            -- *****
            end
            
            local newexp = os.date("%I:%M:%S", devicetable.expiration)
            
            if newexp ~= priorexp then
              log.debug (string.format('[upnp] Device %s expiration updated TO: %s', devicetable.usn, newexp))
            end
            
            if not devicetable.online or devicetable._monrestart then
              back_online(devicetable, headers)                         -- ***** removed ip, port parms (not used)
              devicetable._monrestart = nil
            end
            
            devicetable._retries = 0        -- retry counter needs to be reset here
              
          else
            log.warn ('[upnp] cache-control header missing: ignoring notification')
          end
          
        elseif headers["nts"] == 'ssdp:byebye' then
        
          if devicetable.online then
            
            log.info (string.format('[upnp] Device %s (%s) has declared itself offline', id, devicetable.description.device.friendlyName))
            -- >> TO BE ADDED: CHECK DEVICE DESCRIPTION FOR ALL SIBLING AND PARENT DEVICES AND SET THOSE OFFLINE TOO
            devicetable.online = false
            devicetable._retries = -1         -- don't attempt to re-contact (depend instead on future advertisements)
            devicetable._changecallback(devicetable.stdevice)
          end
        end
      end
    end
  end
end

  
-- Channel Hander:  Receive and process discovery response messages
local function watch_multicast(_, sock)
  local data, rip
  repeat

    data, rip, _ = sock:receivefrom()
    
    if data and (rip ~= 'timeout') then
    
      local headers = util.process_response(data, {'NOTIFY', '200 OK'})
      
      if headers ~= nil then
        update_state(headers, rip) 
      end
    end   
  until rip == 'timeout'
      
end


-- Initialize monitoring feature
local function init(upnpdev)

  log.info ("[upnp] Initializing monitor sockets and channel handlers")

  -- initialize multicast socket
  m = assert(socket.udp(), "create discovery socket")
  assert(m:setoption('reuseaddr', true))
  assert(m:setsockname(multicast_ip, multicast_port))
  assert(m:setoption("ip-add-membership", {multiaddr = multicast_ip, interface = "0.0.0.0"}), "join multicast group")
  m:settimeout(0)

  -- initialize unicast socket
  u = assert(socket.udp(), "create unicast socket")
  assert(u:setsockname(listen_ip, listen_port), "unicast socket setsockname")
  u:settimeout(0)
  
  upnpdev.stdriver:register_channel_handler(m, watch_multicast, 'multicast')
  upnpdev.stdriver:register_channel_handler(u, watch_multicast, 'unicast')
  
  expiration_timer = upnpdev.stdriver:call_on_schedule(EXPIRATIONCHECKTIME, check_expirations, "Expiration check timer")   -- *****
  log.info ('[upnp] Periodic expiration checker scheduled')

  watchtable = {}               -- *****
  initflag = true
  
end


-- Add a device to the watch table
local function register(upnpdev, configchange_callback, poll, restart)  -- *****

  log.info ('[upnp] Registering for monitoring: ' .. upnpdev.usn)

  upnpdev._retries = 0
  upnpdev._changecallback = configchange_callback
  
  if poll then
    upnpdev._poll = tonumber(poll)
    log.debug (string.format('[upnp] Polling option: %s seconds', poll))
    
    -- Force quick initial expiration check *****
    upnpdev.expiration = math.floor(socket.gettime() + math.floor(math.random() * 10 + .5))
  else
    upnpdev._poll = nil
  end
  
  if restart == true then
    upnpdev._monrestart = true              -- *****this will force a status change callback for monitoring restarts
    log.debug(string.format('[upnp] Restart option= %s', restart))
  else
    upnpdev._monrestart = nil
  end

  if not initflag then
    init(upnpdev)
  end

  watchtable[upnpdev.usn] = upnpdev

end


-- Remove a device from the watch table
local function unregister(upnpdev)

  watchtable[upnpdev.usn] = nil
  
  log.info ('[upnp] Unregistered for monitoring: ' .. upnpdev.usn)
  
end


local function shutdown(driver)

  driver:unregister_channel_handler(m)
  driver:unregister_channel_handler(u)
	m:close()
  u:close()
	initflag = false
  watchtable = {}
  driver:cancel_timer(expiration_timer)             -- *****
  
  log.info ('[upnp] Monitor function shutdown')

end

return {
  init = init,
  register = register,
  unregister = unregister,
  shutdown = shutdown,
}
