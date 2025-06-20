import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/logger.dart';
import 'package:ocplist/src/main.dart';
import 'package:plist_parser/plist_parser.dart';
import 'package:xml/xml.dart';

// Exit Codes
  // 0: OK
  // 1: User input error
  // 2: HTTP error
  // 3: Invalid plist path
  // 4: Invalid configuration

late ArgResults args;
late bool outputToController;
bool lock = false;
StreamController controller = StreamController.broadcast();

bool isLocked() {
  return lock;
}

Never quit([int code = 0]) {
  lock = false;
  exit(code);
}

StreamController gui({required String input, bool verbose = false, bool force = false}) {
  List<String> args = [input, if (verbose) "--verbose", if (force) "--force"];
  main(args, alt: true);
  return controller;
}

Future<void> cli(List<String> arguments) async {
  return await main(arguments);
}

String countword({required num count, required String singular, String? plural}) {
  plural ??= "${singular}s";
  return count == 1 ? singular : plural;
}

Future<void> main(List<String> arguments, {bool alt = false}) async {
  if (lock == true) {
    return print([Log("Error", effects: [31]), Log(": Process already started")], overrideOtuputToController: alt);
  }

  Plist plist;
  bool directPlist = false;
  lock = true;
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
    ..addFlag('force', abbr: 'f', negatable: false, help: 'Ignore unsupported configuration warnings');

  try {
    args = parser.parse(arguments);
  } catch (e) {
    error([Log("$e")], exitCode: 1);
  }

  List rest = args.rest;
  String usage = "ocplist (plist: file path, direct URL) [--help] [--verbose] [--force]";

  if (args["help"] == true || rest.isEmpty) {
    print([Log("Usage: $usage")]);
    return;
  }

  if (directPlist) {
    plist = parsePlist(rest[0]);
  } else {
    plist = await getPlist(rest[0]);
  }

  List unsupportedConfigurations = findUnsupportedConfigurations(plist.raw, plist.json);

  if (unsupportedConfigurations.isNotEmpty) {
    int errors = 0;
    int warnings = 0;
    sectiondelim();

    for (int i = 0; i < unsupportedConfigurations.length; i++) {
      UnsupportedConfiguration configuration = unsupportedConfigurations[i];
      int color = configuration.status == UnsupportedConfigurationStatus.warning ? 32 : 31;
      log([Log("Invalid Configuration", effects: [33]), Log(" ("), Log(configuration.status.toString().split(".")[1], effects: [color]), Log("): "), Log(configuration.getTypeString(), effects: [1, 31])]);

      switch (configuration.status) {
        case UnsupportedConfigurationStatus.warning: warnings++; break;
        case UnsupportedConfigurationStatus.error: errors++; break;
      }

      for (int i = 0; i < configuration.reason.length; i++) {
        String reason = configuration.reason[i].map((item) => item.toString()).join("");
        log([Log(reason)]);
      }

      if (i - 1 != unsupportedConfigurations.length) {
        snippetdelim();
      }
    }

    print([Log("Found "), Log("${unsupportedConfigurations.length} unsupported configurations", effects: [1]), Log(" with "), Log("$warnings warnings", effects: [1, 33]), Log(" and "), Log("$errors errors", effects: [1, 31]), Log("!")]);

    if (errors > 0 && args["force"] != true) {
      quit(4);
    }
  }

  verbose([Log("Generating report...")]);
  sectiondelim();

  try {
    List<Map> add = (plist.json["Kernel"]["Add"] as List).whereType<Map>().toList();
    int count = add.length;
    int enabled = add.where((item) => item["Enabled"] == true).length;
    log([Log("Kexts: ($count kexts, $enabled enabled)")]);

    for (int i = 0; i < add.length; i++) {
      Map item = add[i];
      bool enabled = item["Enabled"] ?? false;
      String name = item["BundlePath"];
      String? minkernel = item["MinKernel"];
      String? maxkernel = item["MaxKernel"];
      String kernel = "";

      bool valid<T>(dynamic input) {
        return input is T && input != "";
      } 

      if (valid<String>(minkernel)) {
        if (valid<String>(maxkernel)) {
          kernel = "$minkernel to $maxkernel";
        } else {
          kernel = "$minkernel and higher";
        }
      } else if (valid<String>(maxkernel)) {
        kernel = "$maxkernel and lower";
      } else {
        kernel = "any";
      }

      log([Log("${i + 1}. "), Log(name, effects: [1]), Log(" (enabled: "), Log("$enabled", effects: [1, enabled ? 32 : 31]), Log(") (kernel: "), Log(kernel, effects: [1]), Log(")")]);
    }

    sectiondelim();
  } catch (e) {
    null;
  }

  try {
    List<String> keys = ["Misc", "Security", "SecureBootModel"];
    String secureboot = plist.json * keys;
    misc(keys: keys, value: [Log(secureboot, effects: [1])]);
  } catch (e) {
    null;
  }

  try {
    List<String> keys = ["NVRAM", "Add", "7C436110-AB2A-4BBB-A880-FE41995C9F82", "prev-lang:kbd"];
    Uint8List bytes = plist.json * keys;
    String hex = getHex(bytes);
    String value = utf8.decode(bytes);
    misc(keys: keys, value: [Log(hex, effects: [1]), Log(" ("), Log(value, effects: [1]), Log(")")]);
  } catch (e) {
    rethrow;
  }

  verbose([Log("Parse complete!")]);
  lock = false;
  quit(0);
}

String getHex(Uint8List bytes) {
  return "0x${bytes.map((item) => item.toRadixString(16).toUpperCase()).join("")}";
}

void misc({required List<String> keys, required List<Log> value, String delim = " > "}) {
  log([Log("${keys.join(delim)}: "), ...value]);
}

List<UnsupportedConfiguration> findUnsupportedConfigurations(String raw, Map plist) {
  List<UnsupportedConfiguration> results = [];

  try {
    List<String> keys = ["ACPI", "Booter", "DeviceProperties", "Kernel", "Misc", "NVRAM", "PlatformInfo", "UEFI"];
    List<String> cloverKeys = ["ACPI", "Boot", "BootGraphics", "CPU", "Devices", "DisableDrivers?", "GUI", "Graphics", "KernelAndKextPatches", "Quirks", "RtVariables", "SMBIOS", "SMBIOS_capitan", "SMBIOS_ventura", "SystemParameters"];
    List<String> presentKeys = [];

    for (String key in keys) {
      if (plist.containsKey(key)) {
        presentKeys.add(key);
      }
    }

    double threshold = 0.9;
    double match = presentKeys.length / keys.length;

    if (match < threshold) {
      bool clover = false;
      List<String> cloverKeysPresent = [];

      for (String key in cloverKeys) {
        if (plist.containsKey(key)) {
          cloverKeysPresent.add(key);
        }
      }

      double matchClover = cloverKeysPresent.length / cloverKeys.length;
      if (matchClover > threshold) clover = true;

      results.add(UnsupportedConfiguration(status: clover ? UnsupportedConfigurationStatus.error : UnsupportedConfigurationStatus.warning, type: clover ? UnsupportedConfigurationType.TopLevelClover : UnsupportedConfigurationType.TopLevel, reason: [[Log("Present top level OpenCore keys: "), Log("${(match * 100).round()}% match", effects: [1]), Log(" (below threshold of ${(threshold * 100)}%): ${presentKeys.join(", ")}")], if (clover) [Log("Present top level Clover keys: "), Log("${(matchClover * 100).round()}% match", effects: [1]), Log(" (above threshold of ${(threshold * 100)}%): ${cloverKeysPresent.join(", ")}")]]));
    }
  } catch (e) {
    null;
  }

  try {
    int threshold = 3;
    int matches = 0;
    Map boot = plist["Misc"]["Boot"];
    bool pickerMode = boot["PickerMode"] == "External";
    bool timeout = boot["Timeout"] == 10;
    bool target = plist["Misc"]["Debug"]["Target"] == 0;
    bool language = plist["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"]["prev-lang:kbd"] == "en:252";

    for (bool item in [pickerMode, timeout, target, language]) {
      if (item == true) {
        matches++;
      }
    }

    if (matches >= threshold) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.OpcoreSimplify, reason: [[Log("Matches: $matches (above/equal to threshold of $threshold)")], [Log("PickerMode match: $pickerMode")], [Log("Timeout match: $timeout")], [Log("Target match: $target")], [Log("prev-lang:kbd match: $language")]]));
    }
  } catch (e) {
    null;
  }

  try {
    RegExp regex = RegExp(r'MaLd0n|olarila', multiLine: true, caseSensitive: false);
    Iterable matches = regex.allMatches(raw);

    if (matches.isNotEmpty) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.Olarila, reason: [[Log("Matches to ${regex.pattern}: "), Log("${matches.length}", effects: [1])]]));
    }
  } catch (e) {
    null;
  }

  try {
    RegExp regex = RegExp(r'^([Vv]\d+\.\d+(\.\d+)?(\s*\|\s*.+)?).*'); // Taken from CorpNewt's CorpBot.py $plist command
    int matches = 0;

    for (dynamic item in plist["Kernel"]["Add"]) {
      if (item is! Map) continue;
      dynamic comment = item["Comment"];
      print([Log("$comment")]);
      bool status = comment is String && regex.hasMatch(comment);

      if (status) {
        matches++;
      }
    }

    if (matches > 0) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.GeneralConfigurator, reason: [[Log("Matches to ${regex.pattern}: "), Log("$matches", effects: [1])]]));
    }
  } catch (e) {
    rethrow;
  }

  return results;
}

Future<Plist> getPlist(String path) async {
  String? raw = await getData(path);
  
  if (raw == null) {
    error([Log("Invalid plist path: $path")]);
    didExit();
  }

  try {
    return parsePlist(raw);
  } catch (e) {
    error([Log("Invalid plist format: $e")], exitCode: 1);
    didExit();
  }
}

Plist parsePlist(String raw) {
  Map result = PlistParser().parse(raw);
  verbose([Log("Parsed plist (${raw.split("\n").length} lines)")]);
  return Plist(raw: raw, json: result);
}