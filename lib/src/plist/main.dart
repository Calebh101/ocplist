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

bool isLocked() {
  return lock;
}

Never quit([int code = 0]) {
  lock = false;
  exit(code);
}

StreamController gui({required String input, bool verbose = false, bool force = false, bool web = false}) {
  List<String> args = [input, if (verbose) "--verbose", if (force) "--force"];
  main(args, alt: true, web: web);
  return controller;
}

Future<void> cli(List<String> arguments) async {
  return await main(arguments);
}

Future<void> main(List<String> arguments, {bool alt = false, bool web = false}) async {
  if (lock == true) {
    return print([Log("Error", effects: [31]), Log(": Process already started")], overrideOutputToController: alt);
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
    title([Log("Invalid Configurations")]);

    for (int i = 0; i < unsupportedConfigurations.length; i++) {
      UnsupportedConfiguration configuration = unsupportedConfigurations[i];
      int color = configuration.status == UnsupportedConfigurationStatus.warning ? 33 : 31;
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

    print([Log("Found "), Log("${unsupportedConfigurations.length} unsupported configurations", effects: [1]), Log(" with "), Log("$warnings ${countword(count: warnings, singular: "warning")}", effects: [1, 33]), Log(" and "), Log("$errors ${countword(count: errors, singular: "error")}", effects: [1, 31]), Log("!")]);

    if (errors > 0 && args["force"] != true) {
      quit(4);
    }
  }

  verbose([Log("Generating report...")]);

  if (web) {
    await ocvalidateweb(plist.raw);
  } else {
    await ocvalidate(plist.raw);
  }

  try {
    List<Map> add = (plist.json["Kernel"]["Add"] as List).whereType<Map>().toList();
    int count = add.length;
    int enabled = add.where((item) => item["Enabled"] == true).length;
    title([Log("Kexts ($count kexts, $enabled enabled)")]);

    for (int i = 0; i < add.length; i++) {
      Map item = add[i];
      bool enabled = item["Enabled"] ?? false;
      String name = item["BundlePath"];
      String? minkernel = item["MinKernel"];
      String? maxkernel = item["MaxKernel"];
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

      log([Log("${i + 1}. "), Log(name, effects: [1]), Log(" (enabled: "), Log("$enabled", effects: [1, enabled ? 32 : 31]), Log(") (kernel: "), Log(kernel, effects: [1]), Log(") (macOS: "), Log(macos, effects: [1]), Log(")")]);
    }

  } catch (e) {
    verboseerror("kexts", [Log(e)]);
  }

  try {
    String variable = plist["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"]["boot-args"];
    bool delete = plist["NVRAM"]["Delete"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"].contains("boot-args");
    Iterable<RegExpMatch> newline = RegExp("\n").allMatches(variable);

    List<UnsupportedBootArgConfiguration> errors = [];
    List<String> args = variable.split(RegExp(r"[ \n]"));

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

    title([Log("Boot Arguments")]);
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

  title([Log("Misc")]);

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
    try {
      Uint8List bytes = plist.json * keys;
      String hex = getHex(bytes);
      String value = utf8.decode(bytes);
      misc(keys: keys, value: [Log(hex, effects: [1]), Log(" ("), Log(value, effects: [1]), Log(")"), Log(" ("), Log(getType(bytes), effects: [1]), Log(")")]);
    } catch (e) {
      dynamic value = plist.json * keys;
      misc(keys: keys, value: [Log("$value", effects: [1]), Log(" ("), Log(getType(value), effects: [1]), Log(")")]);
    }
  } catch (e) {
    verboseerror("prev-lang:kbd", [Log(e)]);
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
      log([Log("Sample entries: 0 found")]);
    }
  } catch (e) {
    verboseerror("sample keys", [Log(e)]);
  }

  verbose([Log("Parse complete!")]);
  lock = false;
  quit(0);
}

String getHex(Uint8List bytes) {
  return "0x${bytes.map((item) => item.toRadixString(16).toUpperCase()).join("")}";
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

Future<void> ocvalidate(String plist) async {
  try {
    title([Log("OCValidate")]);
    File file = (await getOcValidateFile())!;
    Directory dir = Directory.systemTemp;
    String path = Path.join(dir.path, "config.plist");
    File config = File(path)..createSync();
    await config.writeAsBytes(Uint8List.fromList(utf8.encode(plist)));

    if (Platform.isLinux || Platform.isMacOS) {
      verbose([Log("changing perms of ${file.path}")]);
      ProcessResult result = await Process.run('chmod', ['+x', file.path]);

      if (result.exitCode != 0) {
        error([Log("Unable to change ocvalidate permissions: ${result.stderr}")]);
        return;
      }
    }

    log([Log("Generating OCValidate report...")]);
    ProcessResult result = await Process.run(file.path, [config.path]);
    log([Log(result.stdout)]);
  } catch (e) {
    error([Log(e)]);
  }
}

Future<void> ocvalidateweb(String raw) async {
  verbose([Log("OCValidate is not supported on Web!")]);
}