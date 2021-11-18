# LAN Device Monitor for SmartThings Edge

This is a SmartThings Edge driver for creating virtual SmartThings devices that monitor the online/offline status of LAN devices that respond to SSDP requests.

### What you will need to know
For the device you want to monitor, you'll need to know if it is a UPnP device, or if it at least responds to SSDP discovery requests.  If you don't know, you can simply try it and see if it works.  Alternatively you can use a UPnP explorer on your local LAN to discover all your monitorable devices.  One such explorer is available as SmartThings Edge driver (Channel: https://api.smartthings.com/invitation-web/accept?id=4f17fc7e-7a44-4826-884d-31117037c08d).

- If your device is a simple, without multiple embedded logical devices/services, then all you need to know is the IP address of the device.  
- If it is a more complex device with multiple logical devices/services with their own unique UUID, then you'll need to know the UUID of the device/service you want to monitor.

You will configure the monitor to find your device either via IP address or UUID.  Note that if you use IP address, it's best that its a **static** IP address, otherwise it could change if your device goes off line or your router reboots.

## Instructions
Once the driver is installed to the hub, use the mobile app to do an Add device/Scan nearby.  A new device will be created in the 'No room assigned' room called **LAN Device Monitor**.

### Configuration
Go to the device details screen in the mobile app and go to device settings by tapping the 3 vertical dot menu in the upper right corner, and then tap **Settings**.
Set either the IP Address or UUID fields for you device.  Note that if you configure both these fields with valid values, UUID will be used.

- A valid IP address must be in the form **nnn.nnn.nnn.nnn** where 'n' is a numeric digit and 'nnn' is less than 255; do *not* include port number
- A valid UUID must be in the form **xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx** where 'x' is a hexidecimal character (0-9, a-f or A-F)

#### Polling
You can configure how often, in seconds, the device is polled to ensure it is online.  The minimum interval is 10 seconds, and the default is 20 seconds.  The more frequent you poll, the more potential LAN traffic the driver will be generating - how much will depend on the device.  Better behaved devices that implement the full and proper SSDP protocol will be more responsive and require less LAN traffic.

### Usage
#### Dashboard
The device card will reflect the on/off status of the device

#### Device Details Screen
The device details screen contains device information plus actions the user can take.
##### Device Info
Starting at the top, the device details screen will show information about the device currently being monitored, including its online/offline status, name & model as reported by the device, UUID, and IP address.  Note that these fields will be grayed-out when monitoring is turned off.
##### Monitoring Switch
Following the device info fields is a switch to turn monitoring on and off.  There must be a valid IP address or UUID configured or any attempts to switch on monitoring will result in the switch immediately turning off again. Monitoring can be suspended for a currently monitored device by turning the switch off at any time.  This will result in the info fields getting grayed-out, the device status field set to '-unknown-', and the dashboard state will show 'off'.  The switch capability used for automation conditions will also be set to **off**, so be aware of this when setting up automations.

Monitoring can be turned back on at any time as long as there is a valid IP address or UUID configured.

**Note on configuration changes:**
- Before any changes to configuration settings take effect (new IP address, UUID or different polling frequency), device monitoring must first be turned off, and then back on.
##### Create new device button
At the bottom of the device details screen, there is a button to create another virtual device, which you can then configure just as described above.  Each additional device created will also have this button, so new devices can be created from any LAN monitoring device.

#### Automations
A standard switch capability is provided that can be used in automation conditions to test the on/off status of the device.


#### Responsiveness
Generally, device online/offline status should get initialized within 10 seconds of initially turning on monitoring.  

If a device has implemented the full SSDP specification then response times and subsequent updating of device online/offline status will be quick, particularly when the device goes offline.  Well-implemented devices may also report their status more frequently than the polling interval you configure.  So for example, even if you define a polling interval of 15 minutes, the device may choose to report more frequently.  Networking equipment often have very frequent reporting intervals (e.g. every 30-45 seconds), for example.
