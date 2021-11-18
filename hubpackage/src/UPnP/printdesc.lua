local function printdescription(devdesc)

  print ("\n====================================================================================")
  print ("                            DEVICE DESCRIPTION TABLE                                ")
  print ("====================================================================================\n")

  print ("Config number: ", devdesc.configId)
  print ("Spec version: ", devdesc.specVersion)
  if devdesc.URLBase ~= nil then
    print ("URL Base: ", devdesc.URLBase, "\x1b[91m<deprecated>\x1b[0m")
  end
  
  print ("Number of services: ", #devdesc.device.services)
  print ("Number of sub-devices: ", #devdesc.device.subdevices)
  
  print ("\n\x1b[93mDevice metadata:\x1b[0m")

  for key, value in pairs(devdesc.device) do
    if key ~= 'services' and key ~= 'subdevices' then
      print ('\x1b[97m' .. key .. ': \x1b[0m' .. value)
    end
  end    
  
  print ("\n\x1b[93mServices:\x1b[0m")
  if devdesc.device.services then
    for index, data in ipairs(devdesc.device.services) do
      print ('\x1b[96m   ' .. index .. '\x1b[0m')
      for key, value in pairs(data) do
        print ('\t\x1b[97m' .. key .. ': \x1b[0m' .. value)
      end
    end
  end
  
  print ("\n\x1b[93mSub-Devices:\x1b[0m")  
  if devdesc.device.subdevices then
    for sd_index, sd_data in ipairs(devdesc.device.subdevices) do
      print ('\x1b[96m   ' .. sd_index .. '\x1b[0m')
      for sd_key, sd_value in pairs(sd_data) do
        if (sd_key ~= 'services') and (sd_key ~= 'subdevices')then
          if type(sd_value) ~= 'table' then
            print ('\t\x1b[97m' .. sd_key .. ': \x1b[0m' .. sd_value)
          else
            print ('\t\x1b[97m' .. sd_key .. '\x1b[0m (table)')
          end
        end
      end
      
      if sd_data.services then
        print ("\n\t\x1b[93mSub-device Services:\x1b[0m")
        for index2, data2 in ipairs(sd_data.services) do
          print ('\t\x1b[96m   ' .. index2 .. '\x1b[0m')
          for key2, value2 in pairs(data2) do
            print ('\t\t\x1b[97m' .. key2 .. ': \x1b[0m' .. value2)
          end
        end
      end
      
      if sd_data.subdevices then
        print ("\n\t\x1b[93mSub-sub-Devices:\x1b[0m")  
        for ssd_index, ssd_data in ipairs(sd_data.subdevices) do
          print ('\t\x1b[96m   ' .. ssd_index .. '\x1b[0m')
          for ssd_key, ssd_value in pairs(ssd_data) do
            if ssd_key ~= 'services' then
              print ('\t\t\x1b[97m' .. ssd_key .. ': \x1b[0m' .. ssd_value)
            end
          end 
        
          if ssd_data.services then
            print ("\n\t\t\t\x1b[93mSub-sub-device Services:\x1b[0m")
            for ssds_index, ssds_data in ipairs(ssd_data.services) do
              print ('\t\t\t\x1b[96m   ' .. ssds_index .. '\x1b[0m')
              for ssds_key, ssds_value in pairs(ssds_data) do
                print ('\t\t\t\t\x1b[97m' .. ssds_key .. ': \x1b[0m' .. ssds_value)
              end
            end
          end
        end
      end
    end
  end
  print ('\n')
end

local function printservice(servdesc)

  print ("\n====================================================================================")
  print ("                            SERVICE DESCRIPTION TABLE                                ")
  print ("====================================================================================\n")

  print ("Config number: ", servdesc.configId)
  print ("Spec version: ", servdesc.specVersion)
  
  print ("Number of actions: ", #servdesc.actions)
  print ("Number of states: ", #servdesc.states)
  
  print ("\n\x1b[93mACTIONS:\x1b[0m")

  if servdesc.actions then
    for index, data in ipairs(servdesc.actions) do
      print ('\x1b[96m   ' .. index .. '\x1b[0m')
      print ('\t\x1b[97mname:\x1b[0m  ' .. data.name)
      
      if data.arguments then
        print ('\t\x1b[96m     Arguments:\x1b[0m')
        
        for index2, data2 in ipairs(data.arguments) do
          print ('\t\t\x1b[96m' .. index2 .. '\x1b[0m')
          for key2, value2 in pairs(data2) do 
            print ('\t\t\t\x1b[97m' .. key2 .. ': \x1b[0m' .. value2)
          end
        end
      end
    end
  end
  
  print ("\n\x1b[93mSTATES:\x1b[0m")
  
  if servdesc.states then
    for index, data in ipairs(servdesc.states) do
      print ('\x1b[96m   ' .. index .. '\x1b[0m')
      for key, value in pairs(data) do
        if key == 'allowedValues' then
          print ('\t\x1b[96mAllowed Values:\x1b[0m')
           
          for index2, data2 in ipairs(value) do
            print ('\t', data2)
          end
        
        elseif key == 'allowedValueRange' then 
          print ('\t\x1b[96mAllowed Range:\x1b[0m')
          for key2, value2 in pairs (value) do
            print ('\t\t\x1b[97m' .. key2 .. ': \x1b[0m' .. value2)
          end
        
        else
          print ('\t\x1b[97m' .. key .. ': \x1b[0m' .. value)
        
        end  
      end
    end
  end
  
  print ('\n')
end

return {
  printdescription = printdescription,
  printservice = printservice,
}
