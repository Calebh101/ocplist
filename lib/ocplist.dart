import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:plist_parser/plist_parser.dart';

late ArgResults args;
late bool outputToController;
StreamController controller = StreamController.broadcast();

void print(List<Log> input) {
  if (outputToController) {
    controller.sink.add(input);
  } else {
    stdout.writeln(input);
  }
}

StreamController ocplist({required String input, bool verbose = false, bool force = false}) {
  List<String> args = [input, if (verbose) "--verbose", if (force) "--force"];
  main(args);
  return controller;
}

Future<void> main(List<String> arguments, {bool useController = false}) async {
  outputToController = useController;
  ArgParser parser = ArgParser()
    ..addFlag("help", abbr: "h", negatable: false, help: "Show usage")
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose output')
    ..addFlag('force', abbr: 'f', negatable: false, help: 'Ignore unsupported configuration warnings');

  try {
    args = parser.parse(arguments);
  } catch (e) {
    error("$e", exitCode: 1);
  }

  List rest = args.rest;
  String usage = "ocplist (plist: file path, direct URL) [--help] [--verbose] [--force]";

  if (args["help"] == true || rest.isEmpty) {
    print([Log("Usage: $usage")]);
    return;
  }

  Plist plist = (await getPlist(rest[0]))!;
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
  }
}

class Log {
  final dynamic input;
  final List<int> effects;
  const Log(this.input, {this.effects = const []});

  @override
  String toString() {
    return "${effects.map((int item) => "\x1b[${item}m").join("")}$input${"\x1b[0m"}";
  }
}

void log(List<Log> logs) {
  print(logs);
}

void error(dynamic input, {int? exitCode}) {
  print([Log("Error: $input")]);
  if (exitCode != null) exit(exitCode);
}

void verbose(dynamic input) {
  if (args["verbose"] == true) {
    print([Log("Verbose: $input")]);
  }
}

void snippetdelim() {
  print([Log("")]);
}

void sectiondelim() {
  int width = stdout.terminalColumns;
  print([Log("\n${"-" * width}\n")]);
}

class Plist {
  final String raw;
  final Map json;
  const Plist({required this.raw, required this.json});
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
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.Olarila, reason: [[Log("Matches to ${regex.pattern}: ${matches.length}")]]));
    }
  } catch (e) {
    null;
  }

  return results;
}

class UnsupportedConfiguration {
  final UnsupportedConfigurationType type;
  final List<List<Log>> reason;
  const UnsupportedConfiguration({required this.type, this.reason = const []});

  String getTypeString() {
    String delim = " - ";
    switch (type) {
      case UnsupportedConfigurationType.OpcoreSimplify: return ["Prebuilt","Auto-Tool","OpCore Simplify"].join(delim);
      case UnsupportedConfigurationType.GeneralConfigurator: return ["Configurator"].join(delim);
      case UnsupportedConfigurationType.OCAT: return ["Configurator","OCAT"].join(delim);
      case UnsupportedConfigurationType.OCC: return ["Configurator","OpenCore Configurator"].join(delim);
      case UnsupportedConfigurationType.Olarila: return ["Prebuilt","Distro","Olarila"].join(delim);
      case UnsupportedConfigurationType.TopLevel: return ["Bootloader","Potentially not OpenCore"].join(delim);
      case UnsupportedConfigurationType.TopLevelClover: return ["Bootloader","Clover"].join(delim);
    }
  }

  @override
  String toString() {
    return "UnsupportedConfiguration(type: $type, reason: ${jsonEncode(reason)})";
  }
}

enum UnsupportedConfigurationType {
  OpcoreSimplify,
  Olarila,
  OCAT,
  OCC,
  GeneralConfigurator,
  TopLevel,
  TopLevelClover,
}

Future<Plist?> getPlist(String path) async {
  String? plistraw;

  try {
    File file = File(path);
    if (file.existsSync()) {
      verbose("Found plist: ${file.path}");
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
          verbose("Found plist: $uri");
          plistraw = utf8.decode(response.bodyBytes);
        } else {
          error("Got bad response: ${response.body} (status code: ${response.statusCode})", exitCode: 2);
        }
      }
    } catch (e) {
      null;
    }
  }

  if (plistraw == null) {
    error("Invalid plist path: $path", exitCode: -1);
  } else {
    try {
      Map result = PlistParser().parse(plistraw);
      verbose("Parsed plist (${plistraw.split("\n").length} lines)");
      return Plist(raw: plistraw, json: result);
    } catch (e) {
      error("Invalid plist format: $e", exitCode: -1);
    }
  }

  return null;
}