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

### OCPlist Usage

```
ocplist <url or file path> [--help] [--verbose] [--force] [--no-ocvalidate]
```

- The URL or file path can be a URL, relative file path, absolute file path, Google Drive link, or Pastebin link.
- `--help`: Show usage.
- `--verbose`: Shows extra messages for debugging. If you see `verbose error`, don't worry; the program logs *every single* try/catch, even if it's intentional (which a lot of them are).
- `--force`: Show properties of the entire `config.plist` even if unsupported configurations are detected.
- `no-ocvalidate`: Skip OCValidate.

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

```
oclog <url or file path> [--help] [--verbose] [--force] [--linecount=X]
```

Some arguments are the same as the OCPlist usage.

`--linecount=X`: Control how many of the last lines of the log are shown. Defaults to 15. Replace `X` with your chosen amount.