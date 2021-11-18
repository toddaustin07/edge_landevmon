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
  
  Library file to handle all UPnP control-related routines.

  ** This code significantly based on Samsung SmartThings sample LAN drivers; credit to Patrick Barrett **

--]]

local xmlparse = require "UPnP.xmlparse"
local util = require 'UPnP.upnpcommon'

local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"
http.TIMEOUT = 10
local ltn12 = require "ltn12"

local log = require "log"

-- THIS FUNCTION TBD WHETHER IT WILL BE IMPLEMENTED OR NOT
-- Ensure command and arguments match with service description
local function validate_cmd(cmd_tbl, service_desc)

	local valid_action = false
	local valid_args = 0
	local action_index = 0
	
	
	for index, action in ipairs(service_desc.actions) do

		if cmd_tbl.action == action.name then
			valid_action = true
			action_index = index
		end

	end
	
	if valid_action then
		
		local argcounter = 0;
		for name, _ in pairs(cmd_tbl.arguments) do
			for _, servarg in ipairs(service_desc.actions[action_index].arguments) do
				if (servarg.direction == 'in') and (name == servarg.name) then
					valid_args = valid_args + 1
				end
		  end
		  argcounter = argcounter + 1
		end
		
		log.debug ('[upnp] action arg count / valid_args:', argcounter, valid_args)
		if argcounter == valid_args then
			
			return true
		
		else
		
			log.error ('[upnp] Invalid action argument provided')
			return false
		end
	
	else
		log.error ('[upnp] Invalid action command')
		return false
	
	end

end

-- Handle responses to action commands from devices

local function parse_action_response(statusline, body)

  if string.find(statusline, '200 OK', nil, 'plaintext') or 
     string.find(statusline, '500 Internal Server Error', nil, 'plaintext') then
  
		resp_table = xmlparse.action_XML(body)
			
		if resp_table then
			if string.find(statusline, '200 OK', nil, 'plaintext') then
				return 'OK', resp_table
			else
				return 'Error', resp_table
			end
		else
			log.error ('[upnp] Cannot parse action response XML')
			return nil
		end
				
  else
		log.error ('[upnp] Unknown HTTP action response: ', statusline)
		return nil
  
  end
  
end

-- Create XML for action commands

local function build_cmd_request(cmd, serviceType)

	local request_wrapper = [[<?xml version="1.0" encoding="utf-8"?>
			<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
			 s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
				<s:Body>
					%s
				</s:Body>
			</s:Envelope>]]

	local body_cmd = '<u:' .. cmd.action .. ' xmlns:u="' .. serviceType .. '">'
	local body_end = '</u:' .. cmd.action .. '>'
	
	local body_args = ''
	local argsbuild = ''

	if (cmd.arguments ~= nil) then
		for name, value in pairs(cmd.arguments) do
			
			argsbuild = '<' .. name .. '>' .. tostring(value) .. '</' .. name .. '>'
			body_args = body_args .. argsbuild
		
		end
	end
	
	body = body_cmd .. body_args .. body_end
	
	return string.format(request_wrapper, body)

end

-- Send action commands to UPnP devices

local function action (devobj, serviceid, cmd_tbl)

  local service = util.scan_for_service(devobj, serviceid)
	
	if not service then
		log.error ('[upnp] Invalid Service ID provided for action')
		return nil
	end
	
	-- Build XML message

	body = build_cmd_request(cmd_tbl, service.serviceType)
	
	ip = devobj.ip
	port = devobj.port
	
	if not (ip and port) then
		log.error ('[upnp] Action request: ip and port not found in UPnP device metadata')
		return nil
	end
		
	local responsechunks = {}

	local path = service.controlURL or '/'
	
	if string.match(path, '^/', 1) == nil then
		path = '/' .. path
	end

	log.debug ('[upnp] Sending action:', service.serviceType .. '#' .. cmd_tbl.action)

	local resp, code_or_err, _, status_line = http.request {
			url = "http://" .. ip .. ":" .. port .. path,
			method = "POST",
			sink = ltn12.sink.table(responsechunks),
			source = ltn12.source.string(body),
			headers = {
					["SOAPACTION"] = service.serviceType .. '#' .. cmd_tbl.action,
					["CONTENT-TYPE"] = "text/xml",
					["HOST"] =  ip .. ":" .. port,
					["CONTENT-LENGTH"] = #body
			}
	}
	
	if code_or_err == nil then
		log.error ("[upnp] HTTP response timeout for command: " .. cmd_tbl.action)
		return nil
	end
	
	local resp = table.concat(responsechunks)
	
	log.debug ("[upnp] Got action response", code_or_err, status_line)

	status, resptable = parse_action_response(status_line, resp)
	
  return status, resptable

end

return {
	action = action,
}
