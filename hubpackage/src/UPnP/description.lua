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
  
  Library file to handle all UPnP description retrieval-related routines.
  
  ** This code significantly based on Samsung SmartThings sample LAN drivers; credit to Patrick Barrett **

--]]
local xmlparse = require 'UPnP.xmlparse'
local util = require 'UPnP.upnpcommon'

local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http" 
--local http = require "socket.http"
http.TIMEOUT = 3
local ltn12 = require "ltn12"

local log = require "log"


-- This function removes lines beginning with '#' which can be present in Sonos device description XML
local function scrubXML(data)

  local retdata = data

  local index1 = data:find('\n%s*#', 1)
  
  if index1 then
  
    local index2 = data:find('\n', index1 + 1, 'plaintext')
    if index2 then
    
      print (string.format('Rogue data removed: <<%s>>', string.sub(data, index1 + 1, index2 - 1)))
      local part1 = string.sub(data, 1, index1)
      local part2 = string.sub(data, index2 + 1)
      
      retdata = scrubXML(part1 .. part2)

    else
      print ('FATEL ERROR: could not find end of line')
    end
  end

  return retdata

end


local function getXML(targeturl)

  if targeturl == nil then
    log.error ('[upnp] No XML URL provided')
    return nil
  end
  
  -- HTTP GET the XML File

  log.debug ('[upnp] XML request URL= ', targeturl)

  local responsechunks = {}
  local body,status,headers = http.request{
    url = targeturl,
    sink = ltn12.sink.table(responsechunks)
   }

  local response = table.concat(responsechunks)

  if status == nil then
    log.warn("[upnp] HTTP request for XML seems to have timed out: ", targeturl)
    return nil
  end
  
  -- vvvvvvvvvvvvvvvv TODO: errors are coming back as literal string "[string "socket"]:1239: closed"
  -- instead of just "closed", so do a `find` for the error
  
  if string.find(status, "closed") then
  -- ^^^^^^^^^^^^^^^^
    log.warn ("[upnp] Socket closed unexpectedly, try parsing anyway")
    -- this workaround is required because device didn't send the required zero-length chunk
    -- at the end of its `Text-Encoding: Chunked` HTTP message, it just closes the socket,
    -- so ignore closed errors
  elseif status ~= 200 then
    log.warn (string.format("[upnp] HTTP XML request to %s failed with error code %s", targeturl, tostring(status)))
    return nil
  end

  if response ~= nil then
    
    return xmlparse.parseXML(scrubXML(response))
  
  else
    log.error ('[upnp] Nil response from description request to ' .. targeturl)
  end
  
end


local function getServiceDescription(devobj, serviceID)

  if serviceID then

    local serviceinfo = util.scan_for_service(devobj, serviceID)
    
    if serviceinfo then
    
      if string.match(serviceinfo.SCPDURL, '^/', 1) then
        targetURL = devobj.URLBase .. serviceinfo.SCPDURL
      else
        targetURL = devobj.URLBase .. '/' .. serviceinfo.SCPDURL
      end
      
      return getXML(targetURL)
    
    else
      log.error ('[upnp] Invalid Service ID provided for fetching service description')
    
    end
    
  else
    log.error ('[upnp] Missing Service ID parameter for fetching service description')
  end
  
  return nil

end

return {
  getXML = getXML,
  getServiceDescription = getServiceDescription,
}
