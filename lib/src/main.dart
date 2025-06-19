import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:ocplist/src/classes.dart';
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
StreamController controller = StreamController.broadcast();

Never quit([int code = 0]) {
  exit(code);
}

void print(List<Log> input) {
  if (outputToController) {
    controller.sink.add(input);
  } else {
    stdout.writeln(input.map((item) {
      item.effects.add(2);
      return item.toString();
    }).join(""));
  }
}

StreamController ocplist({required String input, bool verbose = false, bool force = false}) {
  List<String> args = [input, if (verbose) "--verbose", if (force) "--force"];
  main(args, alt: true);
  return controller;
}

Future<void> ocplistcli(List<String> arguments) async {
  return await main(arguments);
}

Future<void> main(List<String> arguments, {bool alt = false}) async {
  Plist plist;
  bool directPlist = false;
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
    plist = (await getPlist(rest[0]))!;
  }

  List unsupportedConfigurations = findUnsupportedConfigurations(plist.raw, plist.json);

  if (unsupportedConfigurations.isNotEmpty) {
    sectiondelim();

    for (int i = 0; i < unsupportedConfigurations.length; i++) {
      UnsupportedConfiguration configuration = unsupportedConfigurations[i];
      log([Log("Invalid Configuration", effects: [33]), Log(": "), Log(configuration.getTypeString(), effects: [1, 31])]);

      for (int i = 0; i < configuration.reason.length; i++) {
        String reason = configuration.reason[i].map((item) => item.toString()).join("");
        log([Log(reason)]);
      }

      if (i - 1 != unsupportedConfigurations.length) {
        snippetdelim();
      }
    }

    if (args["force"] != true) {
      quit(4);
    }
  }

  verbose([Log("Generating report...")]);
}

void log(List<Log> logs) {
  print(logs);
}

void error(List<Log> input, {int? exitCode}) {
  print([Log("Error: "), ...input]);
  if (exitCode != null) exit(exitCode);
}

void verbose(List<Log> input) {
  if (args["verbose"] == true) {
    print([Log("Verbose: "), ...input]);
  }
}

void snippetdelim() {
  print([Log("")]);
}

void sectiondelim() {
  int width = stdout.terminalColumns;
  print([Log("\n${"-" * width}\n")]);
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

      results.add(UnsupportedConfiguration(type: clover ? UnsupportedConfigurationType.TopLevelClover : UnsupportedConfigurationType.TopLevel, reason: [[Log("Present top level OpenCore keys: "), Log("${(match * 100).round()}% match", effects: [1]), Log(" (below threshold of ${(threshold * 100)}%): ${presentKeys.join(", ")}")], if (clover) [Log("Present top level Clover keys: "), Log("${(matchClover * 100).round()}% match", effects: [1]), Log(" (above threshold of ${(threshold * 100)}%): ${cloverKeysPresent.join(", ")}")]]));
    }
  } catch (e) {
    null;
  }

  try {
    Map boot = plist["Misc"]["Boot"];
    bool pickerMode = boot["PickerMode"] == "External";
    bool timeout = boot["Timeout"] == 10;
    bool target = plist["Misc"]["Debug"]["Target"] == 0;
    bool language = plist["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"]["prev-lang:kbd"] == "en:252";

    if ([pickerMode, timeout, target, language].every((item) => item == true)) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.OpcoreSimplify, reason: [[Log("PickerMode match: $pickerMode")], [Log("Timeout match: $timeout")], [Log("Target match: $target")], [Log("prev-lang:kbd match: $language")]]));
    }
  } catch (e) {
    null;
  }

  try {
    RegExp regex = RegExp(r'MaLd0n|olarila', multiLine: true);
    Iterable matches = regex.allMatches(raw);

    if (matches.isNotEmpty) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.Olarila, reason: [[Log("Matches to ${regex.pattern}: "), Log("${matches.length}", effects: [1])]]));
    }
  } catch (e) {
    null;
  }

  try {
    RegExp regex = RegExp(r'^([Vv]\d+\.\d+(\.\d+)?(\s*\|\s*.+)?).*'); // Taken from CorpNewt's CorpBot.py $plist command
    List<Map<String, dynamic>> add = plist["Kernel"]["Add"];
    int matches = 0;

    bool match = add.any((Map item) {
      dynamic comment = item["comment"];
      bool status = comment is String && regex.hasMatch(comment);
      if (status) matches++;
      return status;
    });

    if (match) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.GeneralConfigurator, reason: [[Log("Matches to ${regex.pattern}: "), Log("$matches", effects: [1])]]));
    }
  } catch (e) {
    null;
  }

  return results;
}

Future<Plist?> getPlist(String path) async {
  String? plistraw;

  try {
    File file = File(path);
    if (file.existsSync()) {
      verbose([Log("Found plist: ${file.path}")]);
      plistraw = file.readAsStringSync();
    }
  } catch (e) {
    null;
  }

  if (plistraw == null) {
    try {
      Uri? uri = Uri.tryParse(path);
      if (uri != null) {
        http.Response response = await http.get(uri).timeout(Duration(seconds: 10));

        if (response.statusCode == 200) {
          verbose([Log("Found plist: $uri")]);
          plistraw = utf8.decode(response.bodyBytes);
        } else {
          error([Log("Got bad response: ${response.body} (status code: ${response.statusCode})")], exitCode: 2);
        }
      }
    } catch (e) {
      null;
    }
  }

  if (plistraw == null) {
    error([Log("Invalid plist path: $path")], exitCode: 3);
  } else {
    try {
      return parsePlist(plistraw);
    } catch (e) {
      error([Log("Invalid plist format: $e")], exitCode: 1);
    }
  }

  return null;
}

Plist parsePlist(String raw) {
  Map result = PlistParser().parse(raw);
  verbose([Log("Parsed plist (${raw.split("\n").length} lines)")]);
  return Plist(raw: raw, json: result);
}