local upnpstate_cap = [[
{
    "id": "partyvoice23922.upnpstate",
    "version": 1,
    "status": "proposed",
    "name": "upnpstate",
    "attributes": {
        "state": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string"
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "enumCommands": []
        }
    },
    "commands": {}
}
]]

local moncontrol_cap = [[
{
    "id": "partyvoice23922.moncontrol",
    "version": 1,
    "status": "proposed",
    "name": "moncontrol",
    "attributes": {
        "switch": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string"
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "setter": "setSwitch",
            "enumCommands": []
        }
    },
    "commands": {
        "setSwitch": {
            "name": "setSwitch",
            "arguments": [
                {
                    "name": "value",
                    "optional": false,
                    "schema": {
                        "type": "string"
                    }
                }
            ]
        }
    }
}
]]

local upnpname_cap = [[
{
    "id": "partyvoice23922.upnpname",
    "version": 1,
    "status": "proposed",
    "name": "upnpname",
    "attributes": {
        "name": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string"
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "enumCommands": []
        }
    },
    "commands": {}
}
]]

local upnpmodel_cap = [[
{
    "id": "partyvoice23922.upnpmodel",
    "version": 1,
    "status": "proposed",
    "name": "upnpmodel",
    "attributes": {
        "model": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string"
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "enumCommands": []
        }
    },
    "commands": {}
}
]]

local upnpuuid_cap = [[
{
    "id": "partyvoice23922.upnpuuid",
    "version": 1,
    "status": "proposed",
    "name": "upnpuuid",
    "attributes": {
        "uuid": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string",
                        "maxLength": 36
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "enumCommands": []
        }
    },
    "commands": {}
}
]]

local upnpaddr_cap = [[
{
    "id": "partyvoice23922.upnpaddr",
    "version": 1,
    "status": "proposed",
    "name": "upnpaddr",
    "attributes": {
        "addr": {
            "schema": {
                "type": "object",
                "properties": {
                    "value": {
                        "type": "string",
                        "maxLength": 20
                    }
                },
                "additionalProperties": false,
                "required": [
                    "value"
                ]
            },
            "enumCommands": []
        }
    },
    "commands": {}
}
]]

local createdev_cap = [[
{
    "id": "partyvoice23922.createanother",
    "version": 1,
    "status": "proposed",
    "name": "createanother",
    "attributes": {},
    "commands": {
        "push": {
            "name": "push",
            "arguments": []
        }
    }
}
]]

return {
	upnpstate_cap = upnpstate_cap,
	moncontrol_cap = moncontrol_cap,
	upnpname_cap = upnpname_cap,
	upnpmodel_cap = upnpmodel_cap,
	upnpuuid_cap = upnpuuid_cap,
	upnpaddr_cap = upnpaddr_cap,
	createdev_cap = createdev_cap,
}
	
