import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/logger.dart';
import 'package:ocplist/src/main.dart';
import 'package:ocplist/src/plist/configurations.dart';
import 'package:ocplist/src/plist/ocvalidate.dart';
import 'package:path/path.dart' as Path;
import 'package:plist_parser/plist_parser.dart';
import 'package:xml/xml.dart';

// Exit Codes
  // 0: OK
  // 1: User input error
  // 2: HTTP error
  // 3: Invalid plist path
  // 4: Invalid configuration
  // 5: Already started

List<String> acpiText = ["SSDT", "SSDTs"];
List<String> ocKeys = ["ACPI", "Booter", "DeviceProperties", "Kernel", "Misc", "NVRAM", "PlatformInfo", "UEFI"];

Future<void> OcPlistGui({required String input, bool verbose = false, bool force = false, bool web = false, bool ocvalidate = true, required double Function() terminalwidth}) async {
  List<String> args = [input, if (verbose) "--verbose", if (force) "--force", if (ocvalidate == false) "--no-ocvalidate"];
  await main(args, alt: true, web: web, terminalwidth: terminalwidth);
  return;
}

Future<void> cli(List<String> arguments) async {
  await main(arguments);
  return;
}

Future<void> main(List<String> arguments, {bool alt = false, bool web = false, double Function()? terminalwidth}) async {
  if (lock.contains(LogMode.plist)) {
    print([Log("Error", effects: [31]), Log(": Process already started")], overrideOutputToController: alt);
    quit(mode: LogMode.plist, code: 5, gui: alt);
  }

  Plist plist;
  bool directPlist = false;
  bool useOcValidate = true;

  lock.add(LogMode.plist);
  outputToController = alt;

  try {
    if (alt == false) throw Exception();
    XmlDocument.parse(arguments[0]);
    directPlist = true;
  } catch (e) {
    directPlist = false;
  }

  ArgParser parser = ArgParser()
    ..addFlag("help", abbr: "h", negatable: false, help: "Show usage")
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose output')
    ..addFlag('force', abbr: 'f', negatable: false, help: 'Ignore unsupported configuration warnings')
    ..addFlag('no-ocvalidate', negatable: false, help: "Don't use OCValidate.");

  try {
    args = parser.parse(arguments);
  } catch (e) {
    error([Log("$e")], exitCode: 1, mode: LogMode.plist, gui: alt);
  }

  List rest = args.rest;
  String usage = "ocplist (plist: file path, direct URL) [--help] [--verbose] [--force]";

  if (args["help"] == true || rest.isEmpty) {
    print([Log("Usage: $usage")]);
    return;
  }

  if (args["no-ocvalidate"] == true) {
    useOcValidate = false;
  }

  verbose([Log("Generating report...")]);
  log([Log.event(LogEvent.resultstart)]);
  logversion("ocplist");

  if (directPlist) {
    plist = parsePlist(rest[0]);
  } else {
    plist = await getPlist(rest[0], alt: alt);
  }

  List unsupportedConfigurations = findUnsupportedConfigurations(plist.raw, plist.json);

  if (unsupportedConfigurations.isNotEmpty) {
    int errors = 0;
    int warnings = 0;
    title([Log("Invalid Configurations")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < unsupportedConfigurations.length; i++) {
      UnsupportedConfiguration configuration = unsupportedConfigurations[i];
      int color = configuration.status == UnsupportedConfigurationStatus.warning ? 33 : 31;
      log([Log("Invalid Configuration", effects: [33]), Log(" ("), Log(configuration.status.toString().split(".")[1], effects: [color]), Log("): "), Log(configuration.getTypeString(), effects: [1, 31])]);

      switch (configuration.status) {
        case UnsupportedConfigurationStatus.warning: warnings++; break;
        case UnsupportedConfigurationStatus.error: errors++; break;
      }

      for (int i = 0; i < configuration.reason.length; i++) {
        List<Log> reason = configuration.reason[i];
        log(reason);
      }

      if (i - 1 != unsupportedConfigurations.length) {
        snippetdelim();
      }
    }

    print([Log("Found "), Log("${unsupportedConfigurations.length} unsupported configurations", effects: [1]), Log(" with "), Log("$warnings ${countword(count: warnings, singular: "warning")}", effects: [1, 33]), Log(" and "), Log("$errors ${countword(count: errors, singular: "error")}", effects: [1, 31]), Log("!")]);

    if (errors > 0 && args["force"] != true) {
      quit(code: 4, mode: LogMode.plist, gui: alt);
    }
  }

  if (useOcValidate) {
    if (web) {
      await ocvalidateweb(plist.raw);
    } else {
      await ocvalidate(plist.raw, alt: alt, terminalwidth: terminalwidth);
    }
  }

  try {
    List<Map> add = (plist.json["Kernel"]["Add"] as List).whereType<Map>().toList();
    int count = add.length;
    int enabled = add.where((item) => item["Enabled"] == true).length;
    title([Log("Kexts ($count ${countword(count: add.length, singular: "kext")}, $enabled enabled)")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < add.length; i++) {
      Map item = add[i];
      bool enabled = item["Enabled"] ?? false;
      String name = item["BundlePath"];
      String? minkernel = item["MinKernel"];
      String? maxkernel = item["MaxKernel"];

      log([Log("${i + 1}. "), Log(name, effects: [1]), Log(" (enabled: "), Log("$enabled", effects: [1, enabled ? 32 : 31]), Log(") "), ...getKernelString(minkernel, maxkernel)]);
    }

  } catch (e) {
    verboseerror("kexts", [Log(e)]);
  }

  try {
    List<Map> patch = (plist.json["Kernel"]["Block"] as List).whereType<Map>().toList();
    int count = patch.length;
    int enabled = patch.where((item) => item["Enabled"] == true).length;
    title([Log("Kernel > Block ($count ${countword(count: count, singular: "entry", plural: "entries")}, $enabled enabled)")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < count; i++) {
      Map item = patch[i];
      String? arch = item["Arch"];
      bool enabled = item["Enabled"] ?? false;

      if (arch == "" || arch == null) arch = "Any";
      log([Log("${i + 1}. "), Log(item["Identifier"] ?? "null", effects: [1]), Log(" (enabled: "), Log(enabled, effects: [1, enabled ? 32 : 31]), Log(") (arch: "), Log(arch, effects: [1]), Log(")"), Log(" (comment: "), Log(item["Comment"] ?? "no comment", effects: [1]), Log(") "), ...getKernelString(item["MinKernel"], item["MaxKernel"]), Log(" (strategy: "), Log(item["Strategy"] ?? "none", effects: [1]), Log(")")]);
    }
  } catch (e) {
    verboseerror("kernel.block", [Log(e)]);
  }

  try {
    List<Map> patch = (plist.json["Kernel"]["Patch"] as List).whereType<Map>().toList();
    int count = patch.length;
    int enabled = patch.where((item) => item["Enabled"] == true).length;
    title([Log("Kernel > Patch ($count ${countword(count: count, singular: "entry", plural: "entries")}, $enabled enabled)")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < count; i++) {
      Map item = patch[i];
      String? arch = item["Arch"];
      bool enabled = item["Enabled"] ?? false;

      if (arch == "" || arch == null) arch = "Any";
      log([Log("${i + 1}. "), Log(item["Identifier"] ?? "null", effects: [1]), Log(" (enabled: "), Log(enabled, effects: [1, enabled ? 32 : 31]), Log(") (arch: "), Log(arch, effects: [1]), Log(")"), Log(" (comment: "), Log(item["Comment"] ?? "no comment", effects: [1]), Log(") "), ...getKernelString(item["MinKernel"], item["MaxKernel"])]);
    }
  } catch (e) {
    verboseerror("kernel.patch", [Log(e)]);
  }

  try {
    List<Map> add = (plist.json["ACPI"]["Add"] as List).whereType<Map>().toList();
    int count = add.length;
    int enabled = add.where((item) => item["Enabled"] == true).length;
    title([Log("ACPI > Add ($count ${countword(count: count, singular: acpiText[0], plural: acpiText[1])}, $enabled enabled)")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < count; i++) {
      Map item = add[i];
      bool enabled = item["Enabled"] ?? false;
      log([Log("${i + 1}. "), Log(item["Path"], effects: [1]), Log(" (enabled: "), Log(enabled, effects: [1, enabled ? 32 : 31]), Log(") ("), Log(item["Comment"] ?? "no comment", effects: [1]), Log(")")]);
    }
  } catch (e) {
    verboseerror("acpi.add", [Log(e)]);
  }

  try {
    List<Map> patch = (plist.json["ACPI"]["Patch"] as List).whereType<Map>().toList();
    int count = patch.length;
    int enabled = patch.where((item) => item["Enabled"] == true).length;
    title([Log("ACPI > Patch ($count ${countword(count: count, singular: "entry", plural: "entries")}, $enabled enabled)")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < count; i++) {
      Map item = patch[i];
      String? base = item["Base"];
      bool enabled = item["Enabled"] ?? false;

      if (base == "" || base == null) base = "none";
      log([Log("${i + 1}. "), Log(item["Comment"] ?? "null", effects: [1]), Log(" (enabled: "), Log(enabled, effects: [1, enabled ? 32 : 31]), Log(") (base: "), Log(base, effects: [1]), Log(")")]);
    }
  } catch (e) {
    verboseerror("acpi.patch", [Log(e)]);
  }

  try {
    List<Map> drivers = (plist.json["UEFI"]["Drivers"] as List).whereType<Map>().toList();
    int count = drivers.length;
    int enabled = drivers.where((item) => item["Enabled"] == true).length;
    title([Log("Drivers ($count ${countword(count: count, singular: "driver")}, $enabled enabled)")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < count; i++) {
      Map item = drivers[i];
      bool enabled = item["Enabled"] ?? false;
      bool early = item["LoadEarly"] ?? false;

      log([Log("${i + 1}. "), Log(item["Path"], effects: [1]), ...generateValueLogs(" (comment: ||${item["Comment"]}||)"), Log(" (enabled: "), Log(enabled, effects: [1, enabled ? 32 : 31]), Log(") (arguments: "), Log(item["Arguments"], effects: [1]), Log(")"), Log(" (load early: "), Log(early, effects: [1, early ? 32 : 31]), Log(")")]);
    }
  } catch (e) {
    verboseerror("acpi.patch", [Log(e)]);
  }

  try {
    List<Map> tools = (plist.json["Misc"]["Tools"] as List).whereType<Map>().toList();
    int count = tools.length;
    int enabled = tools.where((item) => item["Enabled"] == true).length;
    title([Log("Tools ($count ${countword(count: count, singular: "tool")}, $enabled enabled)")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < count; i++) {
      Map item = tools[i];
      bool enabled = item["Enabled"] ?? false;
      bool auxilary = item["Auxilary"] ?? false;

      log([Log("${i + 1}. "), Log("${item["Path"]} - ${item["Name"]}", effects: [1]), ...generateValueLogs(" (comment: ||${item["Comment"]}||)"), ...generateValueLogs(" (||${item["Flavour"]}||)"), Log(" (enabled: "), Log(enabled, effects: [1, enabled ? 32 : 31]), Log(") (arguments: "), Log(item["Arguments"], effects: [1]), Log(")"), Log(" (auxilary: "), Log(auxilary, effects: [1, auxilary ? 32 : 31]), Log(")")]);
    }
  } catch (e) {
    verboseerror("acpi.patch", [Log(e)]);
  }

  try {
    List<Map<String, dynamic>> properties = getDevProps(plist.json);
    Map<String, List<List<Log>>> logdata = {};
    title([Log("DeviceProperties (${properties.length} ${countword(count: properties.length, singular: "device")})")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < properties.length; i++) {
      String device = properties[i]["key"];
      Map value = properties[i]["value"];
      verbose([Log("Scanning DeviceProperties device: $device")]);

      void addlog(List<Log> logs) {
        logdata[device] ??= [];
        logdata[device]!.add(logs);
      }

      if (device == "PciRoot(0x0)/Pci(0x2,0x0)") {
          for (String key in value.keys) {
            dynamic input;
            bool isData = false;

            try {
              input = value[key] as Uint8List;
              isData = true;
            } catch (e) {
              verboseerror("deviceproperties 0x0,0x2,0x0", [Log(e)]);
              input = value[key];
              isData = false;
            }

            addlog([Log(key, effects: [1]), Log(": "), Log("${isData ? getHex(input) : input}", effects: [1]), if (isData) ...[Log(" ("), Log(getHex(Uint8List.fromList((input as Uint8List).reversed.toList())), effects: [1]), Log(")")], Log(" ("), Log(getType(input), effects: [1]), Log(")")]);
          }
      }

      if (value.containsKey("layout-id")) {
        bool isData = true;

        dynamic id = (() {
          try {
            return value["layout-id"] as TypedDataList;
          } catch (e) {
            verboseerror("deviceproperties audio", [Log(e)]);
            isData = false;
            return value["layout-id"];
          }
        })();

        addlog([Log("Layout ID: "), Log("${isData ? getHex(id) : id}", effects: [1]), if (isData) ...[Log(" ("), Log(ByteData.sublistView(id).getInt32(0, Endian.big), effects: [1]), Log(")")], Log(" ("), Log(getType(id), effects: [1]), Log(")")]);
      }
    }

    List<String> keys = logdata.keys.toList();
    List<String> notIncluded = properties.where((Map<String, dynamic> item) => !keys.contains(item["key"])).map((Map<String, dynamic> item) => item["key"]).whereType<String>().toList();
    verbose([Log("${keys.length} keys: $keys")]);

    for (int i = 0; i < keys.length; i++) {
      String key = keys[i];
      log([Log("${i + 1}. "), Log(key, effects: [1])]);

      for (List<Log> input in logdata[key]!) {
        log(input);
      }

      if (i + 1 != keys.length) {
        snippetdelim();
      }
    }

    if (notIncluded.isNotEmpty) {
      snippetdelim();
      log([Log("Other Devices", effects: [1])]);
    }

    for (int i = 0; i < properties.length; i++) {
      String key = notIncluded[i];
      log([Log("${i + 1}. "), Log(key, effects: [1])]);
    }
  } catch (e) {
    verboseerror("deviceproperties", [Log(e)]);
  }

  try {
    String variable = plist["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"]["boot-args"];
    bool delete = plist["NVRAM"]["Delete"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"].contains("boot-args");
    Iterable<RegExpMatch> newline = RegExp("\n").allMatches(variable);

    List<UnsupportedBootArgConfiguration> errors = [];
    List<String> args = variable.replaceAll(RegExp(r'\s+'), ' ').split(RegExp(r"[ \n]"));

    for (String arg in args) {
      List matches = RegExp("=").allMatches(arg).toList();

      if (matches.isNotEmpty) {
        if (matches.length > 1) {
          errors.add(UnsupportedBootArgConfiguration(input: UnsupportedBootArgConfigurationInput.argument(arg), reason: ["too many equal signs"]));
        } else {
          if (arg.startsWith("-")) {
            errors.add(UnsupportedBootArgConfiguration(input: UnsupportedBootArgConfigurationInput.argument(arg), reason: ["invalid starting dash"]));
          }
        }
      } else {
        if (!arg.startsWith("-")) {
          errors.add(UnsupportedBootArgConfiguration(input: UnsupportedBootArgConfigurationInput.argument(arg), reason: ["no starting dash"]));
        }
        if (arg.endsWith("-")) {
          errors.add(UnsupportedBootArgConfiguration(input: UnsupportedBootArgConfigurationInput.argument(arg), reason: ["invalid ending dash"]));
        }
        if (arg.allMatches("-").length > 1) {
          errors.add(UnsupportedBootArgConfiguration(input: UnsupportedBootArgConfigurationInput.argument(arg), reason: ["too many dashes"]));
        }
      }
    }

    for (RegExpMatch match in newline) {
      errors.add(UnsupportedBootArgConfiguration(input: UnsupportedBootArgConfigurationInput.character(match.start), reason: ["invalid newline"]));
    }

    for (RegExpMatch match in RegExp(r' {2,}').allMatches(variable)) {
      errors.add(UnsupportedBootArgConfiguration(input: UnsupportedBootArgConfigurationInput.character(match.start), reason: ["too many spaces"]));
    }

    try {
      Map<String, int> counts = {};
      for (String item in args) {
        verbose([Log("found argument: $item")]);
        counts[item] = (counts[item] ?? 0) + 1;
      }
      for (String key in counts.keys.where((String key) => (counts[key] ?? 0) >= 2)) {
        errors.add(UnsupportedBootArgConfiguration(input: UnsupportedBootArgConfigurationInput.argument(key), reason: ["duplicate argument"]));
      }
    } catch (e) {
      verboseerror("boot args duplicates", [Log(e)]);
    }

    title([Log("Boot Arguments (${args.length} ${countword(count: args.length, singular: "arg")})")], overrideTerminalWidth: terminalwidth);
    print([Log("boot-args: "), Log(variable.replaceAll("\n", "[\\n]"), effects: [1])]);
    print([Log("Present in NVRAM > Delete: "), Log(delete ? "Yes" : "No", effects: [1, delete ? 32 : 31])]);

    if (errors.isNotEmpty) {
      snippetdelim();
      log([Log("Errors:", effects: [1])]);

      for (var i = 0; i < errors.length; i++) {
        UnsupportedBootArgConfiguration error = errors[i];
        print([Log("${i + 1}. "), Log(error.reason.join(", "), effects: [1, 31]), if (error.input.type != UnsupportedBootArgConfigurationInputType.none) (error.input.type == UnsupportedBootArgConfigurationInputType.arg ? Log(" (boot-arg: ${error.input.input})") : (Log(" (character: ${error.input.input})")))]);
      }
    }
  } catch (e) {
    verboseerror("boot-args", [Log(e)]);
  }

  try {
    title([Log("Emulation")], overrideTerminalWidth: terminalwidth);
    try {
      CpuIdDatabase database = CpuIdDatabase([
        CpuId(from: "Haswell-E", to: "Haswell", id: [0xC3, 0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
        CpuId(from: "Broadwell-E", to: "Broadwell", id: [0xD4, 0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
        CpuId(from: "Comet Lake U62", to: "Comet Lake U42", id: [0xEC, 0x06, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
        CpuId(from: "Rocket Lake", to: "Comet Lake", id: [0x55, 0x06, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
        CpuId(from: "Alder Lake", to: "Comet Lake", id: [0x55, 0x06, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
      ]);

      Uint8List? mask = (() {
        try {
          return plist["Kernel"]["Emulate"]["Cpuid1Data"] as Uint8List;
        } catch (e) {
          verboseerror("emulate cpu mask", [Log(e)]);
          return null;
        }
      })();

      Uint8List data = plist["Kernel"]["Emulate"]["Cpuid1Data"];
      CpuId result = database.findById(data);

      log([Log("CPU: "), Log(result.fromid, effects: [1]), Log(" to "), Log(result.toid, effects: [1]), Log(" (mask: "), Log(mask != null ? getHex(mask) : "Invalid", effects: [1]), Log(")")]);
    } catch (e) {
      verboseerror("emulate cpu", [Log(e)]);
      log([Log("CPU: "), Log("None", effects: [1])]);
    }

    try {
      Map nvram = plist["NVRAM"];
      List drivers = plist["UEFI"]["Drivers"];
      List driverlist = ["OpenVariableRuntimeDxe.efi", "OpenRuntime.efi"];

      bool DisableVariableWrite = plist["Booter"]["Quirks"]["DisableVariableWrite"] == true;
      bool ExposeSensitiveData = plist["Misc"]["Security"]["ExposeSensitiveData"] >= 1;
      bool LegacyOverwrite = nvram["LegacyOverwrite"] == true;
      bool WriteFlash = nvram["WriteFlash"] == true;
      bool LegacySchema = nvram["LegacySchema"] != null;

      List<Map> driverdata = [
        ...List.generate(driverlist.length, (int i) {
          try {
            Map driver = drivers.firstWhere((item) => item["Path"].contains(driverlist[i]));
            return {
              "name": driverlist[i],
              "present": true,
              "LoadEarly": driver["LoadEarly"] ?? false,
            };
          } catch (e) {
            verboseerror("emulate nvram driverdata($i)", [Log(e)]);
            return {
              "name": driverlist[i],
              "present": false,
              "LoadEarly": null,
            };
          }
        }),
      ];

      bool driverdatastatus = (() {
        bool status = true;
        for (Map driver in driverdata) {
          if (driver["present"] == false || driver["LoadEarly"] != true) status = false;
        }
        return status;
      })();

      bool dxefirst = (() {
        try {
          if ((drivers.indexWhere((item) => item["path"] == driverlist[0])) >= (drivers.indexWhere((item) => item["path"] == driverlist[1]))) throw Exception("${driverlist[0]} was after ${driverlist[1]}");
          return true;
        } catch (e) {
          verboseerror("emulate nvram dxefirst", [Log(e)]);
          return false;
        }
      })();

      List<bool> statuses = [DisableVariableWrite, ExposeSensitiveData, LegacyOverwrite, WriteFlash, LegacySchema, driverdatastatus, dxefirst];
      bool status = statuses.every((bool item) => item);
      log([Log("NVRAM: "), Log(status ? "Yes" : "No", effects: [1, if (status) 32]), if (status == false) ...[Log(" ("), Log([if ([DisableVariableWrite, ExposeSensitiveData, LegacyOverwrite, WriteFlash, LegacySchema].every((bool item) => item == false)) "Schema", if (driverdatastatus == false) "Drivers", if (dxefirst == false) "Driver Order"].join(", "), effects: [1, 31]), Log(")")]]);
    } catch (e) {
      verboseerror("emulate nvram", [Log(e)]);
      log([Log("NVRAM: "), Log("None", effects: [1])]);
    }
  } catch (e) {
    verboseerror("emulate", [Log(e)]);
  }

  try {
    Map data = plist["PlatformInfo"]["Generic"];

    String show(String key) {
      dynamic value = data[key];
      String show = "";
      String type = getType(value);

      if (type == "Boolean") {
        show = value ? "Yes" : "No";
      } else if (type == "Data") {
        show = getHex(value);
      } else {
        show = "$value";
      }

      log([Log("$key: "), Log(show, effects: [1]), Log(" ("), Log(type, effects: [1]), Log(")")]);
      return key;
    }

    title([Log("PlatformInfo")], overrideTerminalWidth: terminalwidth);
    ["SystemProductName", "SystemSerialNumber", "ROM", "SystemUUID", "SpoofVendor"].map((dynamic item) => show(item)).toList();
  } catch (e) {
    verboseerror("platforminfo", [Log(e)]);
  }

  title([Log("Misc")], overrideTerminalWidth: terminalwidth);

  try {
    List<String> keys = ["Misc", "Security", "SecureBootModel"];
    String secureboot = plist.json * keys;
    misc(keys: keys, value: [Log(secureboot, effects: [1])]);
  } catch (e) {
    verboseerror("SecureBootModel", [Log(e)]);
  }

  try {
    List<String> keys = ["Misc", "Security", "Vault"];
    String vault = plist.json * keys;
    misc(keys: keys, value: [Log(vault, effects: [1])]);
  } catch (e) {
    verboseerror("Vault", [Log(e)]);
  }

  try {
    List<String> keys = ["NVRAM", "Add", "7C436110-AB2A-4BBB-A880-FE41995C9F82", "prev-lang:kbd"];
    List<Log> result = [];
    bool delete = false;

    try {
      if ((plist.json * ["NVRAM", "Delete", "7C436110-AB2A-4BBB-A880-FE41995C9F82"]).contains("prev-lang:kbd")) delete = true;
    } catch (e) {
      verboseerror("prev-lang:kbd delete", [Log(e)]);
    }

    try {
      Uint8List bytes = plist.json * keys;
      String hex = getHex(bytes);
      String value = utf8.decode(bytes);
      result = [Log(hex, effects: [1]), Log(" ("), Log(value, effects: [1]), Log(")"), Log(" ("), Log(getType(bytes), effects: [1]), Log(")")];
    } catch (e) {
      dynamic value = plist.json * keys;
      if (value == null) {
        result = [Log("None", effects: [1])];
      } else {
        result = [Log("$value", effects: [1]), Log(" ("), Log(getType(value), effects: [1]), Log(")")];
      }
    }

    misc(keys: keys, value: [...result, Log(" (present in NVRAM > Delete: "), Log(delete ? "Yes" : "No", effects: [1, delete ? 32 : 31]), Log(")")]);
  } catch (e) {
    verboseerror("prev-lang:kbd", [Log(e)]);
  }

  try {
    List<String> keys = ["NVRAM", "Add", "7C436110-AB2A-4BBB-A880-FE41995C9F82", "csr-active-config"];
    try {
      Uint8List bytes = plist.json * keys;
      String hex = getHex(bytes);
      misc(keys: keys, value: [Log(hex, effects: [1]), Log(" ("), Log(getType(bytes), effects: [1]), Log(")")]);
    } catch (e) {
      dynamic value = plist.json * keys;
      if (value == null) {
        misc(keys: keys, value: [Log("None", effects: [1])]);
      } else {
        misc(keys: keys, value: [Log("$value", effects: [1]), Log(" ("), Log(getType(value), effects: [1]), Log(")")]);
      }
    }
  } catch (e) {
    verboseerror("csr-active-config", [Log(e)]);
  }

  try {
    List<String> keys = List.generate(4, (int i) {
      return "#WARNING - ${i + 1}";
    });

    List<String> found = [];

    for (String key in keys) {
      if (plist.json.containsKey(key)) {
        found.add(key);
      }
    }

    if (found.isNotEmpty) {
      log([Log("Sample entries: "), Log(found.length, effects: [1]), Log(" found: "), Log(found.join(", "), effects: [1])]);
    } else {
      log([Log("Sample entries: None found")]);
    }
  } catch (e) {
    verboseerror("sample keys", [Log(e)]);
  }

  try {
    List<String> keys = plist.json.keys.whereType<String>().toList();
    List<String> found = keys.where((String key) => !ocKeys.contains(key)).toList();

    if (found.isNotEmpty) {
      log([Log("Extra keys: "), Log(found.length, effects: [1]), Log(" found: "), Log(found.join(", "), effects: [1])]);
    } else {
      log([Log("Extra keys: None found")]);
    }
  } catch (e) {
    verboseerror("extra kekys", [Log(e)]);
  }

  List<Log>? countEntries(List<String> keys, {required String singular, String? plural, bool useEnabled = true}) {
    try {
      List<Map> value = ((plist.json * keys) as List).whereType<Map>().toList();
      List<Map> enabled = value.where((Map item) => item["Enabled"] == true).toList();
      int count = useEnabled ? enabled.length : value.length;
      return [Log("$count", effects: [1]), Log(" ${countword(count: count, singular: singular, plural: plural)}")];
    } catch (e) {
      verboseerror("countEntries($keys)", [Log(e)]);
      return null;
    }
  }

  List<List<Log>> summaryraw = [countEntries(["Kernel", "Add"], singular: "kext"), countEntries(["ACPI", "Add"], singular: "ACPI", plural: acpiText[1]), countEntries(["UEFI", "Drivers"], singular: "driver"), countEntries(["Misc", "Tools"], singular: "tool"), [Log(unsupportedConfigurations.length, effects: [1]), Log(" ${countword(count: unsupportedConfigurations.length, singular: "issue")}")]].whereType<List<Log>>().toList();
  List<Log> summary = [];

  for (int i = 0; i < summaryraw.length; i++) {
    summary.addAll(summaryraw[i]);
    if (i < summaryraw.length - 1) summary.add(Log(" - "));
  }

  newline();
  log(summary);
  log([Log.event(LogEvent.resultend)]);
  verbose([Log("Parse complete!")]);
  lock.remove(LogMode.plist);
  quit(mode: LogMode.plist, gui: alt);
}

String getHex(Uint8List bytes, {bool prefix = true, int pad = 2}) {
  if (bytes.isEmpty) return "";
  return "${prefix ? "0x" : ""}${bytes.map((item) => item.toRadixString(16).toUpperCase().padLeft(pad, "0")).join("")}";
}

List<Log> getKernelString(String? minkernel, String? maxkernel, {int mode = 1}) {
  String kernel = "";
  String macos = "";

  bool valid<T>(dynamic input) {
    return input is T && input != "";
  } 

  if (valid<String>(minkernel)) {
    if (valid<String>(maxkernel)) {
      kernel = "$minkernel to $maxkernel";
      macos = "${getMacOSVersionForDarwinVersion(minkernel!)} to ${getMacOSVersionForDarwinVersion(maxkernel!)}";
    } else {
      kernel = "$minkernel and higher";
      macos = "${getMacOSVersionForDarwinVersion(minkernel!)} and higher";
    }
  } else if (valid<String>(maxkernel)) {
    kernel = "$maxkernel and lower";
    macos = "${getMacOSVersionForDarwinVersion(maxkernel!)} and lower";
  } else {
    kernel = "any";
    macos = "any";
  }

  return mode == 1 ? [Log("(kernel: "), Log(kernel, effects: [1]), Log(") (macOS: "), Log(macos, effects: [1]), Log(")")] : [Log(kernel, effects: [1]), Log(" (macOS: "), Log(macos, effects: [1]), Log(")")];
}

String getType(dynamic value) {
  if (value is Map) {
    if (value.containsKey("CF\$UID")) {
      return "UID";
    } else {
      return "Dictionary";
    }
  } else if (value is List && value is! TypedDataList) {
    return "Array";
  } else if (value is bool) {
    return "Boolean";
  } else if (value is DateTime) {
    return "Date";
  } else if (value is int) {
    return "Integer";
  } else if (value is String) {
    return "String";
  } else {
    return "Data";
  }
}

void misc({required List<String> keys, required List<Log> value, String delim = " > "}) {
  log([Log("${keys.join(delim)}: "), ...value]);
}

List<Map<String, dynamic>> getDevProps(Map plist) {
  Map add = plist["DeviceProperties"]["Add"];
  return add.keys.map((key) {
    dynamic value = add[key];
    if (value is! Map) return null;
    return {"key": key, "value": value};
  }).whereType<Map<String, dynamic>>().toList();
}

Future<Plist> getPlist(String path, {required bool alt}) async {
  String? raw = await getData(path, mode: LogMode.plist, gui: alt);
  
  if (raw == null) {
    error([Log("Invalid plist path: $path")], mode: LogMode.plist, gui: alt);
    didExit();
  }

  try {
    return parsePlist(raw);
  } catch (e) {
    error([Log("Invalid plist format: $e")], exitCode: 1, mode: LogMode.plist, gui: alt);
    didExit();
  }
}

Plist parsePlist(String raw) {
  Map result = PlistParser().parse(raw);
  verbose([Log("Parsed plist (${raw.split("\n").length} lines)")]);
  return Plist(raw: raw, json: result);
}

Future<void> ocvalidate(String plist, {required bool alt, double Function()? terminalwidth}) async {
  try {
    title([Log("OCValidate")], overrideTerminalWidth: terminalwidth);
    File file = (await getOcValidateFile())!;
    Directory dir = Directory.systemTemp;
    String path = Path.join(dir.path, "config.plist");
    File config = File(path)..createSync();
    await config.writeAsBytes(Uint8List.fromList(utf8.encode(plist)));

    if (Platform.isLinux || Platform.isMacOS) {
      verbose([Log("changing perms of ${file.path}")]);
      ProcessResult result = await Process.run('chmod', ['+x', file.path]);

      if (result.exitCode != 0) {
        error([Log("Unable to change ocvalidate permissions: ${result.stderr}")], mode: LogMode.plist, gui: alt);
        return;
      }
    }

    log([Log("Generating OCValidate report...")]);
    ProcessResult result = await Process.run(file.path, [config.path]);
    log([Log(result.stdout)]);
  } catch (e) {
    error([Log(e)], mode: LogMode.plist, gui: alt);
  }
}