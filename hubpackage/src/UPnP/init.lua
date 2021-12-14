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
  
  Master UPnP library module; includes initialization, device discovery and reset routines

  ** discover function based on Samsung SmartThings sample LAN drivers; credit to Patrick Barrett **

--]]
local watcher = require 'UPnP.watcher'
local description = require 'UPnP.description'
local control = require 'UPnP.control'
local eventing = require 'UPnP.eventing'

local util = require "UPnP.upnpcommon"

local cosock = require "cosock"
local socket = require "cosock.socket"

local ltn12 = require "ltn12"
local log = require "log"

local ids_found = {}                -- used to filter duplicate usn's during discovery
local devdesc_fetched = {}

math.randomseed(socket.gettime())         -- ******

-- Called at device initialization to link UPnP metadata to SmartThings device, and ST device/driver data to UPnP metadata
local function link (upnpdev, driver, stdevice)

  upnpdev.stdriver = driver
  upnpdev.stdevice = stdevice
  stdevice:set_field("upnpdevice", upnpdev)

end


-- Method to remove UPnP device from known & monitored devices
local function forget(upnpdev)

  ids_found[upnpdev.usn] = nil
  watcher.unregister(upnpdev)
  log.debug ('[upnp] Device forgotten: ' .. upnpdev.usn)

end


-- Method to return specific metadata from device description based on uuid (for multi-tier devices)
--  if uuid not given, then default to upnpdev.uuid
local function devinfo(upnpdev, uuid)

  if upnpdev.description then

    if not uuid then
      uuid = upnpdev.uuid
    end

    local _uuid = 'uuid:' .. uuid

    if upnpdev.description.device.UDN == _uuid then
    
      return upnpdev.description.device
    
    else
    
      if #upnpdev.description.device.subdevices > 0 then
      
        for _, subdev in ipairs(upnpdev.description.device.subdevices) do
          if subdev.UDN == _uuid then
            return subdev
          end
            
          if subdev.subdevices then
          
            for _, subsubdev in ipairs(subdev.subdevices) do
              if subsubdev.UDN == _uuid then
                return subsubdev
              end
            end
            
          end
        end
      end
    end

    log.error ('[upnp] devinfo: Unable to find matching UDN')
  else
    log.warn('[upnp] devinfo: No description metadata available')
  end
  
  return nil
end

upnpDevice_prototype = {
    init = function (self, driver, device)
  link(self, driver, device)
    end,

    monitor = function (self, configchange_callback, poll, restart)
  return(watcher.register(self, configchange_callback, poll, restart))  --*****
    end,
    
    unregister = function (self)
  watcher.unregister(self)
    end,
    
    forget = function (self)
  forget(self)
    end,
    
    getservicedescription = function (self, serviceid)
  return(description.getServiceDescription(self, serviceid))
    end,
    
    command = function (self, serviceid, cmd_tbl)
  local status, response = control.action(self, serviceid, cmd_tbl)
  return status, response
    end,
    
    subscribe = function (self, serviceid, callback, subscribetime, statevars)
  local response = eventing.subscribe(self, serviceid, callback, subscribetime, statevars)
  return response
    end,
    
    unsubscribe = function (self, sid)
  return (eventing.unsubscribe(self, sid))
    end,
    
    cancel_resubscribe = function (self, sid)
  return (eventing.cancel_resubscribe(self, sid))
    end,

    devinfo = function (self, uuid)
  return (devinfo(self, uuid))
    end,
    
}

-- Make sure given discovery target is a valid MSEARCH option
-- Note that this will also strip off anything following a uuid (starting with '::'), which is not permitted
local function validate_target(target)

  if target == 'upnp:rootdevice' then
    return target
  elseif target == 'ssdp:all' then
    return target
  end
  
  local uuid = target:match("^(uuid:.+)::")
 
  if uuid then
    return uuid
  else
    uuid = target:match("^(uuid:.+)")
    if uuid then
      return target
    
    else
      local urn = target:match("^(urn:.+)") 
      if urn then
        return target
      else
        return nil
      end
    end
  end
end


-- Determine which discovery responses to consider legit
local function validate_response(headers, target, rip, nonstrict)

  local usn = headers["usn"]
  
  if not usn then                                                       -- *****
    log.error(string.format("[upnp] Discovery response from %s has no USN in headers:", rip))
    for key, value in pairs(headers) do
      log.debug (string.format('\t%s : %s', key, value))
    end
    return false
  end
  
  local loc = headers["location"]
  
  local ip = loc:match("http://([^,/:]+)")
  local port = loc:match(":([^/]+)") or ''
  
  if rip ~= ip then               -- not sure this would ever happen
    log.warn("[upnp] Received discovery response with reported & source IP mismatch, ignoring")
    log.warn ("[upnp] ", rip, "~=", ip)
    
  elseif not usn:match("^uuid") then
    log.warn(string.format('[upnp] Invalid USN returned from %s: "%s"', ip, usn))
  
  elseif ip and port and usn and not ids_found[usn] then
    ids_found[usn] = true

    -- Make sure that returned 'ST' header value is what was requested

    local st_val = headers["st"] or ''
    local is_correct_response = false
    
    if target == 'upnp:rootdevice' and st_val == 'upnp:rootdevice' then
      is_correct_response = true
    
    elseif target == "ssdp:all" then
      if st_val:match("^ssdp:all") or st_val:match("^upnp:rootdevice") or st_val:match("^uuid:") or st_val:match("^urn:") then 
        is_correct_response = true
      end
      
    elseif target:match("^uuid:") or target:match("^urn:") then
      if target == st_val then
        is_correct_response = true
      end
    else  
      if nonstrict == true then                                         -- *****
        if target == st_val then                                        -- *****
          is_correct_response = true                                    -- *****
        end                                                             -- *****
      end
    end
    
    if is_correct_response then
      return true
    else
      log.debug (string.format('[upnp] Incorrect search (ST header) response from %s: "%s" (for target=%s)', ip, st_val, target))
    end
  end
    
  return false
  
end


-- build the device info table for discovered device
local function build_device_object(headers)                             -- ***** removed ip/port parms (not used)

  local devloc = headers['location']
  local deviceobj = {}
  local meta = nil
  
  if not devloc then
    log.error ('[upnp] Device description location is missing')
  end
  
  if devdesc_fetched then
    if devdesc_fetched[devloc] == 'unavailable' then
      return nil
    end
  
    if devdesc_fetched[devloc] then
      meta = devdesc_fetched[devloc]
    end
  end
  
  if not meta then
    local retries = 2
    while retries > 0 do
      meta = description.getXML(devloc)
      if meta then; break; end
        
      retries = retries - 1
    end
    if meta then
      devdesc_fetched[devloc] = meta
    else
      devdesc_fetched[devloc] = 'unavailable'
    end
  end
    
  if meta then
    deviceobj.description = meta
  else                                                                  -- *****
    log.warn ('[upnp] No device description XML available from ' .. headers['location']) 
    deviceobj.description = nil
  end

  -- add additional important meta data to device table
 
  deviceobj.usn = headers['usn']
  local uuid = deviceobj.usn:match("uuid:([^,::]+)")
  
  deviceobj.uuid = uuid
  deviceobj.urn = deviceobj.usn:match("::urn:([^/]+)")
  deviceobj.st = headers['st']                                          -- ***** save returned search target

  util.set_meta_attrs(deviceobj, headers)
  
  deviceobj.online = true
  
  local seconds_to_expire = tonumber(string.match(headers["cache-control"], '%d+'))
  deviceobj.expiration = math.floor(socket.gettime()) + seconds_to_expire
  
  return deviceobj
    
end


-- Use multicast to search for and discover devices
local function discover (target, waitsecs, callback, nonstrict, reset)  -- *****

	if not target or not waitsecs or not callback then
		log.error ('[upnp] Missing discover function argument(s)')
		return false
	end
  
  if nonstrict == nil then; nonstrict = false; end
  if reset == nil then; reset = false; end
  
  log.debug (string.format('[upnp] Discovery parms: nonstrict=%s, reset=%s', nonstrict, reset))
  
  if nonstrict == false then                                            -- *****
    target = validate_target(target)                                    -- *****
  end
    
  if not target then
    log.error ('[upnp] Invalid search target:', target)
    return false
  end
  
  if reset then; ids_found = {}; end                                    -- *****

  local multicast_ip = "239.255.255.250"
  local multicast_port = 1900
  local listen_ip = "0.0.0.0"
  local listen_port = 0
  
  local s = assert(socket.udp(), "create discovery socket")
  
  assert(s:setsockname(listen_ip, listen_port), "discovery socket setsockname")

  local number_found = 0

  -- Send MSEARCH request to multicast ip:port

  assert(s:sendto(util.create_msearch_msg(target, waitsecs), multicast_ip, multicast_port))

  -- Wait for MSEARCH responses

  local timeouttime = socket.gettime() + waitsecs + .5 -- + 1/2 for network delay

  while true do
    local time_remaining = math.max(0, timeouttime-socket.gettime())
    
    s:settimeout(time_remaining)
    
    local data, rip, _ = s:receivefrom()
    
    if data then
      local headers = util.process_response(data, {'200 OK'})
      
      if headers then
      
        local valid = validate_response(headers, target, rip, nonstrict)
        
        if valid then 
          number_found = number_found + 1
          
          -- Build the upnp device object (including description)
          local upnpobj = build_device_object(headers)
            
          if upnpobj ~= nil then  
          
            setmetatable(upnpobj, {__index = upnpDevice_prototype})
            callback(upnpobj)
            
          end
        end
      else
        log.debug ('[upnp] Invalid headers from:', rip)
      end
    
    elseif rip == "timeout" then
      break
      
    else
      log.debug (string.format("[upnp] Error receiving discovery reply from: %s", rip))
    end
    
  end
  log.info (string.format("[upnp] Discovery response window ended for %s, %d new devices found", target, number_found))
  
  devdesc_fetched = {}
  s:close()
  return true
  
end


-- Called when all sockets need to be reset for new hub IP address
local function reset(driver)

  watcher.shutdown(driver)
  
  --eventing.shutdownsever(driver)        *****

end


return {
  discover = discover,
  link = link,
  reset = reset,
}
