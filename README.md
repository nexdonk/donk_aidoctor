# donk_aidoctor v2.0

An AI-powered emergency medical service script for FiveM that supports both **QBCore** and **ESX** frameworks with optional **ox_lib** integration for enhanced UI/UX.

## Features

- **Multi-Framework Support**: Automatically detects and works with QBCore or ESX
- **ox_lib Integration**: Uses ox_lib for notifications and progress bars (with framework fallbacks)
- **Smart EMS Detection**: Only available when real EMS personnel are unavailable
- **Configurable Payment System**: Support for cash, bank, or both payment methods
- **Cooldown System**: Prevents spam and abuse with customizable cooldown timers
- **Society Integration**: Payments can be sent to ambulance society/job accounts
- **Multiple Revive Systems**: Supports wasabi_ambulance, QBCore hospital, ESX ambulancejob, and custom systems
- **Fully Customizable**: Extensive configuration options for every aspect
- **Clean Code**: Well-organized, documented, and optimized

## Requirements

### Mandatory
- FiveM Server (build 5848 or higher)
- OneSync enabled
- **One of the following frameworks**:
  - QBCore Framework
  - ESX Legacy (or older versions)

### Optional
- ox_lib (for better notifications and progress bars)
- wasabi_ambulance (for revive functionality)
- qb-management or qb-bossmenu (for QBCore society accounts)
- esx_society or esx_addonaccount (for ESX society accounts)

## Installation

1. Download or clone this repository
2. Place the `donk_aidoctor` folder in your server's `resources` directory
3. Add `ensure donk_aidoctor` to your `server.cfg`
4. Configure the script by editing `config.lua` (see Configuration section)
5. Restart your server or start the resource with `start donk_aidoctor`

## Configuration

Edit `config.lua` to customize the script. All options are documented with comments.

### Framework Settings
```lua
Config.Framework = 'auto' -- Options: 'auto', 'qbcore', 'esx'
```
- `auto`: Automatically detects your framework
- `qbcore`: Force QBCore mode
- `esx`: Force ESX mode

### Command Settings
```lua
Config.Command = 'aidoctor' -- Command to call AI doctor
```
Players will use `/aidoctor` to call the AI doctor when dead.

### EMS Availability
```lua
Config.MinEMS = 0 -- Minimum number of online EMS required
Config.EMSJob = 'ambulance' -- Job name for EMS personnel
```
- `0`: AI doctor always available
- `>0`: AI doctor only available when EMS count is at or below this number

### Payment Settings
```lua
Config.Price = 2000 -- Price for AI doctor service
Config.PaymentAccount = 'cash' -- Options: 'cash', 'bank', 'both'
Config.SendToSociety = true -- Send payment to society account
Config.SocietyAccount = 'ambulance' -- Society account name
```

### Doctor Behavior
```lua
Config.VehicleModel = 'ambulance' -- Vehicle to spawn
Config.DoctorPed = 's_m_m_doctor_01' -- NPC model
Config.DoctorSpeed = 20.0 -- Driving speed
Config.SpawnDistance = 40.0 -- Distance from player to spawn
```

### Revive System
```lua
Config.ReviveSystem = 'auto' -- Options: 'auto', 'wasabi', 'qbcore', 'esx', 'custom'
Config.CustomReviveEvent = nil -- For custom revive systems
```
- `auto`: Automatically detects available revive system
- `wasabi`: Uses wasabi_ambulance
- `qbcore`: Uses QBCore hospital system
- `esx`: Uses ESX ambulancejob
- `custom`: Uses custom event (set CustomReviveEvent)

### Locale/Messages
All messages can be customized in the `Config.Locale` table:
```lua
Config.Locale = {
    ['not_dead'] = 'You are not dead or injured!',
    ['ems_available'] = 'There are EMS personnel available! Call them first.',
    -- ... and more
}
```

## Usage

### For Players
1. When dead or in last stand, type `/aidoctor` (or your configured command)
2. The system checks:
   - Are you actually dead?
   - Are there too many EMS online?
   - Do you have enough money?
   - Are you on cooldown?
3. If all checks pass:
   - An ambulance spawns nearby
   - A doctor NPC drives to your location
   - The doctor approaches and performs CPR
   - You are revived and charged the configured price

### For Administrators

**Debug Mode**: Enable debug logging by setting `Config.Debug = true` in config.lua

**Cooldown Management**: Cooldowns are automatically cleared when players disconnect

## Framework Compatibility

### QBCore
- Full support for all QBCore features
- Integrates with qb-management/qb-bossmenu for society accounts
- Supports both cash and bank accounts
- Compatible with QBCore metadata system

### ESX
- Full support for ESX Legacy and older versions
- Integrates with esx_society/esx_addonaccount for society accounts
- Supports money and bank accounts
- Compatible with ESX job system

### ox_lib
- Uses ox_lib notifications when available
- Uses ox_lib progress bars when available
- Falls back to framework-specific UI if ox_lib not present

## File Structure

```
donk_aidoctor/
├── fxmanifest.lua          # Resource manifest
├── config.lua              # Configuration file
├── README.md               # This file
├── shared/
│   └── framework.lua       # Framework abstraction layer
├── client/
│   └── client.lua          # Client-side logic
└── server/
    └── server.lua          # Server-side logic
```

## API Reference

### Client-Side Events

**TriggerServerEvent**:
- `donk_aidoctor:charge` - Charges the player for the service
- `donk_aidoctor:revivePlayer` - Requests player revival

### Server-Side Callbacks

**Framework.RegisterCallback**:
- `donk_aidoctor:docOnline` - Checks if AI doctor is available
  - Returns: `canCall, hasEnoughMoney, reason, extraData`

### Custom Revive Integration

To use a custom revive system:
1. Set `Config.ReviveSystem = 'custom'`
2. Set `Config.CustomReviveEvent = 'your_custom_event'`
3. Your event will be triggered when revival is needed

Example:
```lua
Config.ReviveSystem = 'custom'
Config.CustomReviveEvent = 'myserver:revivePlayer'
```

## Troubleshooting

### AI Doctor won't spawn
- Check if you're actually dead
- Verify there aren't too many EMS online (check Config.MinEMS)
- Ensure you have enough money
- Check if you're on cooldown
- Enable debug mode (`Config.Debug = true`) to see detailed logs in F8 console

### Doctor spawns but doesn't approach/treat player
- Check F8 console with debug mode enabled to see distance calculations
- Verify the doctor is exiting the vehicle (look for "Doctor exiting vehicle" in console)
- Increase `Config.TreatmentDistance` if doctor never gets close enough (try 3.0)
- Ensure there are no obstacles blocking the doctor's path
- The doctor must be within `Config.ApproachDistance` to exit vehicle and approach

### Framework not detected
- Ensure your framework is started before this resource
- Check server console for error messages
- Try forcing framework mode in config (set to 'qbcore' or 'esx')

### ox_lib features not working
- Verify ox_lib is installed and started
- Check that `@ox_lib/init.lua` is in shared_scripts (fxmanifest.lua)
- The script will automatically fall back to framework UI if ox_lib isn't available

### Payment not going to society
- QBCore: Ensure qb-management or qb-bossmenu is running
- ESX: Ensure esx_society or esx_addonaccount is running
- Check society account name matches your configuration

## Changelog

### Version 2.0.1 (Current)
- **FIXED**: Removed problematic character loaded check that prevented dead players from calling doctor
- **FIXED**: Improved doctor exit vehicle and approach logic
- **FIXED**: Added proper state tracking for doctor exiting vehicle
- **IMPROVED**: Enhanced proximity detection and treatment distance checks
- **IMPROVED**: Better debug logging for distance tracking
- **CHANGED**: Increased default approach distance to 15.0 for more reliable detection
- **CHANGED**: Treatment distance now properly configurable (default: 1.0)

### Version 2.0.0
- Complete rewrite with multi-framework support
- Added ESX framework support
- Integrated ox_lib for better UI/UX
- Added framework abstraction layer
- Expanded configuration options
- Implemented proper cooldown system
- Improved code organization and documentation
- Added debug mode
- Better error handling and cleanup
- Changed default command from `/help` to `/aidoctor`

### Version 1.0.0 (Original)
- QBCore-only implementation
- Basic AI doctor functionality

## Credits

- **Original Author**: donk
- **Framework Abstraction & Improvements**: donk_aidoctor v2.0

## Support

For issues, suggestions, or questions, please open an issue on the GitHub repository.

## License

This project is open source and available under the MIT License.
