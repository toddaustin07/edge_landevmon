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
  
  Common UPnP library routines (used across modules)
  
  Several of these routines heavily borrowed from SmartThings example LAN drivers; much credit to Patrick Barrett

--]]

-- Generate discovery message to be sent
local function create_msearch_msg(searchtarget, waitsecs)

  return table.concat(
    {
      'M-SEARCH * HTTP/1.1',
      'HOST: 239.255.255.250:1900',
      'MAN: "ssdp:discover"', 
      'MX: ' .. waitsecs,
      'ST: ' .. searchtarget,
      'CPFN.UPNP.ORG: SmartThingsHub',
      '\r\n'
    },
    "\r\n"
  )
end

-- Create table of msg headers from SSDP response
local function process_response(resp, types)
  local info = {}
  
  local prefix = string.match(resp, "^([%g ]*)\r\n", 1)
  local match = false
  
  for _, resptype in ipairs(types) do
		if string.find(prefix, resptype, 1, "plaintext") ~= nil then        -- *****
			match = true
		end
  end

	if match then

    local resp2 = string.gsub(resp, "^([%g ]*)\r\n", "")
  
    for k, v in string.gmatch(resp2, "([%g]*):([%g ]*)\r\n") do
      v = string.gsub(v, "^ *", "", 1)  -- strip off any leading spaces
      info[string.lower(k)] = v
    end
    return info
    
  else
    return nil
  end
end


-- Update UPnP meta data attributes
local function set_meta_attrs(deviceobj, headers)
  
  local loc = headers["location"]
  
  local ip = loc:match("http://([^,/:]+)")
  local port = loc:match(":([^/]+)") or ''
  
  deviceobj.location = loc
  deviceobj.ip = ip
  deviceobj.port = port

  if deviceobj.description then                                         -- *****
    if not deviceobj.description.URLBase then
      deviceobj.URLBase = string.match(headers['location'], '^(http://[%d.:]*)')
    else
      deviceobj.URLBase = deviceobj.description.URLBase
    end
  else
    deviceobj.URLBase = string.match(headers['location'], '^(http://[%d.:]*)')
  end
  
  deviceobj.bootid = headers["bootid.upnp.org"]
  deviceobj.configid = headers["configid.upnp.org"]

end

-- Return service section of device description for a given serviceId
local function find_service(serviceid, section)

  if section then
  
    for _, data in ipairs(section) do
      for key, value in pairs(data) do
        if key == 'serviceId' then
          if value == serviceid then
            return data
          end
        end
      end
    end
  end
  return nil
end

local function scan_subdevices(serviceid, section)

  for _, data in ipairs(section) do
    
    for key, data in pairs(data) do
    
      if key == 'services' then 
      
        local result = find_service(serviceid, data)
        
        if result then return result end
        
      elseif key == 'subdevices' then
      
        local result = scan_subdevices(serviceid, data)
        if result then return result end
        
      end
    end
  end
  return nil
end

local function scan_for_service(devobj, serviceid)

  if devobj.description.device.services then

    local result = find_service(serviceid, devobj.description.device.services)
    
    if result then return result end
    
  end
  
  if devobj.description.device.subdevices then
  
    local result = scan_subdevices(serviceid, devobj.description.device.subdevices)
    
    if result then return result end
        
  end
  
  return nil

end

-- credit:  Samsung SmartThings/Patrick Barrett
local function tablefind(t, path)
  local pathelements = string.gmatch(path, "([^.]+)%.?")
  local item = t

  for element in pathelements do
    if type(item) ~= "table" then 
      item = nil; break end

    item = item[element]
  end

  return item
end

local function is_array(t)

  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil then return false end
  end
  return true
end


return {
	create_msearch_msg = create_msearch_msg,
	process_response = process_response,
  set_meta_attrs = set_meta_attrs,
  scan_for_service = scan_for_service,
  tablefind = tablefind,
  is_array = is_array,
}
