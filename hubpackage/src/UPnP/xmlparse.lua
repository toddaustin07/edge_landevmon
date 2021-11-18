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
  
  Library file to handle all UPnP (description and service) xml parsing-related routines.

  This module takes a UPnP device or service description or control
  response in XML form and creates a Lua table for ease of accessing
  the elements.  

  For device and service descriptions, those particular
  functions overcome an issue with the xml2lua module where single item
  arrays are not instantiated as an indexed element, which puts the  
  onus on the programmer to change parsing methods for single item 
  arrays vs. multiple element arrays.  The tables created by these 
  functions always create indexed arrays, making it more consistent for
  the programmer to parse the table.
--]]

local util = require "UPnP.upnpcommon"
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"
local log = require "log"

-- Parse the serviceList section of device description

local function upnp_description_getservicelist(t)

  if (t ~= nil) then
  
    local servicelist = {}
    
    if not util.is_array(t.service) then
      
      servicelist[1] = {}
      for key, value in pairs(t.service) do
        if type(value) == 'table' then value=nil end
        servicelist[1][key] = value
      end
    
    else
      
      for index, data in ipairs(t.service) do
        servicelist[index] = {}
        
        for key, value in pairs(data) do
          if type(value) == 'table' then value=nil end
          servicelist[index][key] = value
        end
      end
      
    end
    
    return servicelist
    
  else  
    log.warn ('[upnp] Service list missing in XML')
    return {}
  end

end


-- This function is called recursively for subdevices within subdevices
local function upnp_description_getsubdevicelist(t)

  if (t ~= nil) then
  
    local subdevices = {}
  
    local devicelist = t.device
    
    if devicelist ==  nil then
      return {}
    end
    
    if not util.is_array(devicelist) then
    
      subdevices[1] = {}
      for key, value in pairs(devicelist) do
        if key == 'serviceList' then
          subdevices[1].services = upnp_description_getservicelist(value)
        elseif key == 'deviceList' then
          subdevices[1].subdevices = upnp_description_getsubdevicelist(value)
        else
          subdevices[1][key] = value
        end
      end
    else
      for index, data in ipairs(devicelist) do
      
        subdevices[index] = {}
        
        for key, data2 in pairs(data) do
          if key == 'serviceList' then
            subdevices[index].services = upnp_description_getservicelist(data2)
          elseif key == 'deviceList' then
            subdevices[index].subdevices = upnp_description_getsubdevicelist(data2)
          else
            subdevices[index][key] = data2
          end
        end
      end
    end
    
    return subdevices
    
  else
    return {}
  end

end

-- Create consistently indexed LUA table of device description XML

local function parseDeviceXML(response)

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)

  xml_parser:parse(response)

  if not handler.root then
    log.error ("[upnp] Malformed Device Description XML")
    return nil
  end

  local parsed_xml = handler.root
  
  if not parsed_xml.root then
    log.error ("[upnp] Malformed Device Description XML")
    return nil
  end
  
  local devicetable = {}
  
  devicetable.device = {}
  
  devicetable.configId = parsed_xml.root._attr.configId
  
  if parsed_xml.root.specVersion ~= nil then
    devicetable.specVersion = util.tablefind(parsed_xml, "root.specVersion.major") .. '.' ..
                              util.tablefind(parsed_xml, "root.specVersion.minor")
  end
  
  -- URLBase is deprecated, but capture if it's there
  devicetable.URLBase = util.tablefind(parsed_xml, "root.URLBase")
  
  -- device metadata
  
  devicetable.device.deviceType = util.tablefind(parsed_xml, "root.device.deviceType")
  devicetable.device.friendlyName = util.tablefind(parsed_xml, "root.device.friendlyName")
  devicetable.device.manufacturer = util.tablefind(parsed_xml, "root.device.manufacturer")
  devicetable.device.modelDescription = util.tablefind(parsed_xml, "root.device.modelDescription")
  devicetable.device.modelName = util.tablefind(parsed_xml, "root.device.modelName")
  devicetable.device.modelNumber = util.tablefind(parsed_xml, "root.device.modelNumber")
  devicetable.device.serialNumber = util.tablefind(parsed_xml, "root.device.serialNumber")
  devicetable.device.UDN = util.tablefind(parsed_xml, "root.device.UDN")
  
  -- Services
  devicetable.device.services = upnp_description_getservicelist(parsed_xml.root.device.serviceList)
  
  -- Sub-devices
  devicetable.device.subdevices = upnp_description_getsubdevicelist(parsed_xml.root.device.deviceList)
  

  -- return the constructed table
  return devicetable
    
end

-- Create proper LUA table of Service description XML

function parseServiceXML(response)
  
  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)

  xml_parser:parse(response)

  if not handler.root then
    log.error ("[upnp] Malformed Service Description XML")
    return nil
  end

  local parsed_xml = handler.root
  
  if not parsed_xml.scpd then
    log.error ("[upnp] Malformed Service Description XML")
    return nil
  end
  
  local servicetable = {}
  
  servicetable.configId = parsed_xml.scpd._attr.configId
  
  if parsed_xml.scpd.specVersion ~= nil then
    servicetable.specVersion = parsed_xml.scpd.specVersion.major .. '.' ..
                               parsed_xml.scpd.specVersion.minor
  end
  
  -- Parse the action list section
  
  servicetable.actions = {}
  
  if parsed_xml.scpd.actionList ~= nil then
  
    local actionlist = parsed_xml.scpd.actionList.action
    
    if util.is_array(actionlist) then
    
      for index, data in ipairs(actionlist) do
        
        servicetable.actions[index] = {}
        
        for key, value in pairs(data) do
        
          if key == 'argumentList' then
          
            servicetable.actions[index].arguments = {}
            argumentlist = actionlist[index].argumentList.argument
          
            if util.is_array(argumentlist) then
              for index2, data2 in ipairs(argumentlist) do
                
                servicetable.actions[index].arguments[index2] = {}
                
                for key2, value2 in pairs(data2) do
                  servicetable.actions[index].arguments[index2][key2] = value2
                  
                end
              end
            else
              servicetable.actions[index].arguments[1] = {}
              for key2, value2 in pairs(argumentlist) do
                servicetable.actions[index].arguments[1][key2] = value2
              end
            
            end
          
          else
            servicetable.actions[index][key] = value
          end
        end
      end
      
    else
      
      servicetable.actions[1] = {}
    
      for key, value in pairs(actionlist) do
              
        if key == 'argumentList' then
        
          servicetable.actions[1].arguments = {}
          argumentlist = actionlist.argumentList.argument
        
          if util.is_array(argumentlist) then
            for index2, data2 in ipairs(argumentlist) do
              
              servicetable.actions[1].arguments[index2] = {}
              
              for key2, value2 in pairs(data2) do
                servicetable.actions[1].arguments[index2][key2] = value2
                
              end
            end
          else
            servicetable.actions[1].arguments[1] = {}
            for key2, value2 in pairs(argumentlist) do
              servicetable.actions[1].arguments[1][key2] = value2
            end
          
          end
          
        else   
          servicetable.actions[1][key] = value
        end
      end
    end
  end
  -- Parse the serviceStateTable section
  
  servicetable.states = {}

  local statelist = parsed_xml.scpd.serviceStateTable.stateVariable
  
  if util.is_array(statelist) then
  
    for index, data in ipairs(statelist) do
    
      servicetable.states[index] = {}
      
      if data._attr ~= nil then
        servicetable.states[index]['sendEvents'] = data._attr.sendEvents
        servicetable.states[index]['multicast'] = data._attr.multicast  
      end
      
      for key, value in pairs(data) do
        
        if key ~= '_attr' then
          
          if key == 'allowedValueList' then
            
            servicetable.states[index].allowedValues = {}
            allowedvalues = statelist[index].allowedValueList.allowedValue
            
            if type(allowedvalues) == "table" then
            
              for index2, data2 in ipairs(allowedvalues) do
                servicetable.states[index].allowedValues[index2] = allowedvalues[index2]
              end
              
            else
              servicetable.states[index].allowedValues[1] = allowedvalues
              
            end
          
          elseif key == 'allowedValueRange' then
          
            servicetable.states[index].allowedValueRange = {}
            allowedrange = statelist[index].allowedValueRange
            
            for key, value in pairs(allowedrange) do
              servicetable.states[index].allowedValueRange[key] = value
            end
          
          else
            servicetable.states[index][key] = value
          end
        end
      end
    end
  else
    
    servicetable.states[1] = {}
    servicetable.states[1]['sendEvents'] = statelist._attr.sendEvents 
    
    for key, value in pairs(statelist) do
      if key ~= '_attr' then
        servicetable.states[1][key] = value
      end
    end
    
  end
  
  return servicetable
    
end

-- Callable device or service description XML parser

local function parseXML(xml)

  if string.find(xml,'<?xml version=\"1.0\"') then  -- make sure there is something to parse

    -- Determine if device or service xml and parse accordingly

    if string.find(xml, "root xmlns") then
    
      return parseDeviceXML(xml)
    
    elseif string.find(xml, "scpd xmlns") then
    
      return parseServiceXML(xml)
      
    else
      log.warn ("[upnp] Unrecognized XML")
    end
  
  else
    log.warn ("[upnp] Invalid XML returned: ", xml)
  end
  
  return nil

end

-- Create Lua table from action responses (both successes and errors)
function action_XML(xml)

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)

  xml_parser:parse(xml)
  
  if not handler.root then
    log.error ("[upnp] Malformed Service Description XML")
    return nil
  end

  local parsed_xml = handler.root
  local arglist = {}
  
  for key, value in pairs(parsed_xml) do
    if string.find(key, 'Envelope', nil, 'plaintext') then
     
      for key2, value2 in pairs(value) do
        if string.find(key2, 'Body', nil, 'plaintext') then
          
          for key3, value3 in pairs(value2) do
         
            if string.find(key3, 'Response', nil, 'plaintext') then
             
              local actionname = string.match(key3, ':([%g]*)Response',1)
              
              if actionname then
                arglist[actionname] = {}
                
                for key4, value4 in pairs(value3) do
                  if key4 ~= '_attr' then
                    if type(value4) == 'table' then   -- if no value provided in the XML, for some reason xml2lua creates a table
                      value4 = ''                     --  so set it to an empty string
                    end
                    arglist[actionname][key4] = value4
                  end
                end
              end
              return arglist
              
            else
              if string.find(key3, 'Fault', nil, 'plaintext') then
                return { ['errorCode'] = value3.detail.UPnPError.errorCode, 
                        ['errorDescription'] = value3.detail.UPnPError.errorDescription }
              end
            end
          end
        end
      end
    end
  end

end


function event_XML(xml)

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)

  xml_parser:parse(xml)
  
  if not handler.root then
    log.error ("[upnp] Malformed event response XML")
    return nil
  end

  local parsed_xml = handler.root
  local propertylist = {}
  
  for key, data in pairs(parsed_xml) do
    if string.find(key, 'propertyset', nil, 'plaintext') then
    
      for subkey, data2 in pairs(data) do
        if string.find(subkey, 'property', nil, 'plaintext') then
          
          if util.is_array(data2) then
            for index, data3 in ipairs(data2) do
              for propname, propvalue in pairs(data3) do
                propertylist[propname] = propvalue
              end
              
            end
          else  
            for propname, propvalue in pairs(data2) do
              propertylist[propname] = propvalue
            end
          end
        end
      end
    end
  end

  return propertylist
    
end


return {
  parseXML = parseXML,
  action_XML = action_XML,
  event_XML = event_XML,
}
