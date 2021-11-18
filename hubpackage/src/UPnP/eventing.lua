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
  
  Library file to handle all UPnP eventing-related (subscription) routines.

  ** This code significantly based on Samsung SmartThings sample LAN drivers; credit to Patrick Barrett **

--]]

local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"
local ltn12 = require "ltn12"

local xmlparse = require "UPnP.xmlparse"
local util = require "UPnP.upnpcommon"

local log = require "log"

local initflag = false
local eventserver = {}
local subscriptions = {}
local orphanevents = {}

-- Figure out what our callback ip address is
local function find_myip(ip)
  
  local s = socket:udp()
  s:setpeername(ip, 9) -- port unimportant, use "discard" protocol port for lack of anything better
  local localip, _, _ = s:getsockname()
  s:close()

  return localip
end


local function send_response(sock, code)

	local resp
	
	if code == 400 then
		resp = "HTTP/1.1 400 Bad request\r\n\r\n"
	elseif code == 412 then
		resp = "HTTP/1.1 412 Precondition Failed\r\n\r\n"
	else
		resp = "HTTP/1.1 200 OK\r\n\r\n"
	end
	
	local _, senderr, _ = sock:send(resp)
	if senderr ~= nil then
		log.warn ('[upnp] Could not send event acknowledgment', senderr)
	end

end

-- Handle event connections from device
local function eventaccept_handler(_, eventsock)

  log.debug ('Handler: Event server')

  local client, accept_err = assert(eventsock:accept())

	if accept_err ~= nil then
		log.error ("[upnp] Connection accept error: " .. accept_err)
		--eventsock:close()
		return
	end
	
	if client == nil then
		log.error ('[upnp] Client connection for event is nil')
		return
	end
	
	--[[
	local ip, port, _ = assert(client:getpeername())
	log.debug ('[upnp] Event connection from: ' .. ip .. ":" .. port)
	--]]

	client:settimeout(1)
	
	--if ip ~= nil then
		do -- Read first line and verify it matches the expect request-line with NOTIFY method type
			local line, err = client:receive()
			if err == nil then
				if line ~= "NOTIFY / HTTP/1.1" then
					log.error ("[upnp] Received unexpected prefix: " .. line)
					send_response(client, 400)
					client:close()
					return
				end
			else
				log.error ("[upnp] Event socket receive failed: " .. err)
				client:close()
				return
			end
		end
		
		local content_length = 0
		local subscriptionid = ''
		local sequence = 0
		
		do -- Receive all headers until blank line is found, saving off content-length
			local line, err = client:receive()
			if err then
				log.error ("[upnp] Event socket receive failed: " .. err)
				client:close()
				return
			end

			while line ~= "" do
				local name, value = socket.skip(2, line:find("^(.-):%s*(.*)"))
				if not (name and value) then
					log.error ("[upnp] Event msg has malformed response headers")
					send_response(client, 400)
					client:close()
					return
				end

				if string.lower(name) == "content-length" then
					content_length = tonumber(value)
				end

				if string.lower(name) == "sid" then
					subscriptionid = value
				end
				
				if string.lower(name) == "seq" then
					sequence = tonumber(value)
				end

				line, err  = client:receive()
				if err ~= nil then
					log.error ("[upnp] Failed to receive event headers: " .. err)
					send_response(client, 400)
					client:close()
					return
				end
			end

			if content_length == nil or content_length <= 0 then
				log.error ("[upnp] Failed to parse content-length from event headers")
				send_response(client, 400)
				client:close()
				return
			end
		end

		do -- receive `content_length` bytes as body
			local body = ""
			while #body < content_length do
				local bytes_remaining = content_length - #body
				local recv, err = client:receive(bytes_remaining)
				if err == nil then
					body = body .. recv
				else
					log.error ("[upnp] Failed to receive event body: " .. err)
					break
				end
			end
			
			if body ~= nil then
				local propertylist = xmlparse.event_XML(body)

				if propertylist then
				
					-- Everything is good, so send HTTP OK response now
					send_response(client)	
					
					local sid_found = false
					
					if subscriptions ~= nil then
						if subscriptions[subscriptionid] ~= nil then
							local callback = subscriptions[subscriptionid]['callback']
							local stdevice = subscriptions[subscriptionid]['stdevice']
							sid_found = true
							callback(stdevice, subscriptionid, sequence, propertylist)
						end
					end
												
					if not sid_found then
						-- Instead of sending a 412 error, we'll store the event for retrieval in subscribe routine
						-- > This handles case where the first event is received prior to 'subscriptionid' being received,
						-- >  and 'subscriptions' set, by subscribe routine
						log.debug ('[upnp] Event received for unknown subscription ID: ' .. subscriptionid)
						orphanevents[subscriptionid] = {['sequence'] = sequence, ['propertylist'] = propertylist}
					end
					
				else
					log.warn ("[upnp] Empty property list in event msg")
					send_response(client, 400)
				end 
				
			else
				log.error ("[upnp] No body in received event msg")
				send_response(client, 400)
			end
		end
		
		client:close()
	--else
  --	log.error ("[upnp] Could not get IP from getpeername()")
	--end

end


local function init(driver)

	eventserver.listen_sock = socket.tcp()

	-- create server on IP_ANY and os-assigned port
	assert(eventserver.listen_sock:bind("*", 0))
	assert(eventserver.listen_sock:listen(5))
	local ip, port, _ = eventserver.listen_sock:getsockname()

	if ip ~= nil and port ~= nil then
		log.info ("[upnp] Event server started and listening on: " .. ip .. ":" .. port)
		eventserver.listen_port = port
					
		driver:register_channel_handler(eventserver.listen_sock, eventaccept_handler, 'eventing handler')
		
		initflag = true
		
		return true
		
	else
		log.error ("[upnp] Could not get IP/port from TCP getsockname(), not listening for events")
		eventserver.listen_sock:close()
		eventserver.listen_sock = nil
		return false
	end	
end


local function subscribe(devobj, serviceid, callback, subscribetime, statevars)

	if initflag ~= true then
		if not init(devobj.stdriver) then
			return nil
		end
	end
	
	local service = util.scan_for_service(devobj, serviceid)
	
	if not service then
		log.error ('[upnp] Invalid Service ID provided')
		return nil
	end
	
	local ip = devobj.ip
	local port = devobj.port

	if not (ip and port) then
		return nil
	end

	local device_facing_ip = find_myip(ip)

	if device_facing_ip == nil or eventserver.listen_port == nil then
		log.error ("[upnp] Cannot subscribe, no event listen server address available")
		return nil
	end
	
	if not eventserver.listen_sock then
		log.error ('[upnp] No event server socket')
		return nil
	end

	local urltarget = 'http://' .. ip .. ':' .. port
	
	if service.eventSubURL == nil then
		log.error ('[upnp] No event URL for requested service:', serviceid)
		return nil
	end
	
	if string.match(service.eventSubURL, '^/', 1) == nil then
		urltarget = urltarget .. '/'
	end
	
	urltarget = urltarget .. service.eventSubURL

	log.info ("[upnp] Subscribing to ", urltarget)

	local response_body = {}
	local sendheaders = {
		["HOST"] =  ip .. ":" .. port or 80,
		["CALLBACK"] = "<http://" .. device_facing_ip .. ":" .. eventserver.listen_port .. "/>",
		["NT"] = "upnp:event",
		["TIMEOUT"] = "Second-" .. tostring(subscribetime),
	}

	local statevarlist = ''
	
	if statevars then
		for i, var in ipairs(statevars) do
			if i > 1 then
				statevarlist = statevarlist .. ','
			end
			statevarlist = statevarlist .. var
		end
		sendheaders["STATEVAR"] = statevarlist
	end

	local resp, code_or_err, headers, status_line = http.request {
		url = urltarget,
		method = "SUBSCRIBE",
		sink = ltn12.sink.table(response_body),
		headers = sendheaders,
	}

	if resp == nil then
		log.error ("[upnp] HTTP error sending subscribe request: " .. code_or_err)
		return nil
	end

	if code_or_err ~= 200 then
		log.error ("[upnp] Subscribe failed with error code " .. code_or_err .. " and status: " .. status_line)
		return nil
	end

	local sid = headers["sid"]
	
	if sid ~= nil then																										
		subscriptions[sid] = {["stdevice"] = devobj.stdevice, ["callback"] = callback}
	
		local timeout = headers["timeout"]
		local varlist = headers["accepted-statevar"]
		local vartable = {}
		local i = 1
	
		if varlist then
			for var in string.gmatch(varlist, '([%w-_:+<>!@#$*$]*)') do
				vartable[i] = var
				i = i + 1
			end
		end

		-- Event server channel handler may have already gotten our first event before subscription table was set for this sid
		-- So it will store unrecognized events in orphanevents table.  Check that table now and issue callback if needed

		if orphanevents then
			if orphanevents[sid] then
				log.debug ('[upnp] Found orphaned event for subscription ID ' .. sid)
				local sequence = orphanevents[sid].sequence
				local propertylist = orphanevents[sid].propertylist
				
				callback(devobj.stdevice, sid, sequence, propertylist)
				orphanevents[sid] = nil
			end
		end

	
		return {['sid'] = sid, ["timeout"] = timeout, ["statevars"] = vartable}
	
	else
		log.error ("[upnp] No SID found in subscribe response header")
	end

	return nil

end


local function unsubscribe(devobj, sid)

	local ip = devobj.ip
	local port = devobj.port
	if not (ip and port) then
	  log.error ('[upnp] Unsubscribe: ip/port not found in UPnP metadata')
	  return false
	end

	log.info ("[upnp] Unsubscribing sid " .. sid)

	if sid == nil then
		log.error ('[upnp] SID missing in unsubscribe request')
		return false
	end
	
	local response_body = {}

	local resp, code_or_err, _, status_line = http.request {
			url = "http://" .. ip .. ":" .. port .. "/upnp/event/basicevent1",
			method = "UNSUBSCRIBE",
			sink = ltn12.sink.table(response_body),
			headers = {
					["HOST"] =  ip .. ":" .. port,
					["SID"] = sid,
			}
	}

	if resp == nil then
		log.error ("[upnp] Error sending unsubscribe http request: " .. code_or_err)
		return false
	end

	if code_or_err ~= 200 then
		log.warn ("[upnp] Unsubscribe failed with error code " .. code_or_err .. " and status: " .. status_line)
		return false
	else
	  subscriptions[sid] = nil
	  return true
	end

end


local function cancel_resubscribe(devobj, sid)

	subscriptions[sid] = nil
	log.info ('Subscription renewal cancelled for: ' .. sid)

end

local function shutdownserver(driver)

	driver:unregister_channel_handler(eventserver.listen_sock)
	eventserver.listen_sock:close()
	initflag = false
	-- let unsubscribe calls clear out subscriptions table
	
	log.info ('[upnp] Eventing server shutdown')

end

return {

	subscribe = subscribe,
	unsubscribe = unsubscribe,
	cancel_resubscribe = cancel_resubscribe,
	shutdownserver = shutdownserver,
}
