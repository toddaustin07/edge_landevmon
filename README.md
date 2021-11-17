# LAN Device Monitor for SmartThings Edge

This is a SmartThings Edge driver for creating virtual SmartThings devices that monitor the online/offline status of LAN devices that respond to SSDP requests.

## Instructions
Once the driver is installed to the hub, use the mobile app to do an Add device/Scan nearby.  A new device will be created in the 'No room assigned' room called **LAN Device Monitor**.

### What you will need to know
For the device you want to monitor, you'll need to know if it is a UPnP device, or if it at least responds to SSDP discovery requests.  If you don't know, you can simply try it and see if it works.  Alternatively you can use a UPnP explorer on your local LAN to discover all your monitorable devices.  One such explorer is available as SmartThings Edge driver.

- If it is a simple LAN device without multiple embedded logical devices/services, then all you need to know is the IP address of the device.  
- If it is a more complex device with multiple logical devices/services with their own unique UUID, then you'll need to know the UUID of the device/service you want to monitor.

You will configure the monitor to find your device either via IP address or UUID.  Note that if you use IP address, it's best that its a **static** IP address, otherwise it could change if your device goes off line or your router reboots.

### Configuration
Go to the device details screen in the mobile app and go to device settings by tapping the 3 vertical dot menu in the upper right corner, and then tap **Settings**.
Set either the IP Address or UUID fields for you device.  Note that if you configure both these fields with valid values, UUID will be used.

- A valid IP address must be in the form **nnn.nnn.nnn.nnn** where 'n' is a numeric digit and 'nnn' is less than 255; do *not* include port number
- A valid UUID must be in the form **xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx** where 'x' is a hexidecimal character (0-9, a-f or A-F)

#### Polling
You can configure how often, in seconds, the device is polled to ensure it is online.  The minimum interval is 10 seconds, and the default is 20 seconds.  The more frequent you poll, the more potential LAN traffic the driver will be generating - how much will depend on the device.  Better behaved devices that implement the full and proper SSDP protocol will be more responsive and require less LAN traffic.

### Usage
**Dashboard** - will reflect the on/off status of the device
**Automations** - switch capability will reflect the on/off status of the device which can be used in automation conditions

#### Device Details Screen
##### Device Info
This screen will show information about the device currently being monitored, including its online/offline status, name, model, UUID, and IP address.  Note that these fields will be grayed-out when monitoring is turned off.
##### Monitoring Switch
Following the device info fields is a switch to turn monitoring on and off.  There must be a valid IP address or UUID configured or any attempts to switch on monitoring will result in the switch immediately turning off again. Monitoring can be suspended for a known device by turning the switch off at any time.  This will result in the info fields getting grayed-out, and the dashboard state will show 'off'.  The switch capability used for automation conditions will also be set to **off**, so be sure to define automations accordingly.
##### Create another device
This button will create another virtual device that you can configure just like the original one.  Each subsequent device created will also have this button, so new devices can be created from any LAN monitoring device.



