# OCPlist

A tool for parsing and displaying properties of an OpenCore `config.plist`.

### OCPlist Features

- Detects config.plists from OpCore Simplify, Olarila, etcetera
- Detects config.plists used with configurators, Hackintool, etcetera
- Detects config.plists with older schemas
- Detects config.plists not made with OpenCore
- Shows kexts, SSDTs, ACPI patches, kernel patches, blocked kexts, tools, drivers
- Shows DeviceProperties, boot-args, platform info, emulation, etcetera
- Tells you if the config.plist still has sample entries
- Shows a small summary at the end of the report

## OCLog

A tool for parsing and displaying properties of an OpenCore debug log.

### OCLog Features

- Detects logs that aren't debug
- Shows tools and drivers
- Shows shown picker entries
- Shows OpenCore version and boot-args
- Shows how long the log *actually* was
- Shows how long the menu was shown, and if boot.efi successfully booted (if `EXITBS:START` was encountered)
- Shows last X lines (defaults to 15)


### OCLog Usage

`oclog