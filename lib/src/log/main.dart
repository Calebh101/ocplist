import 'package:args/args.dart';
import 'package:ocplist/src/main.dart';
import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/logger.dart';

Future<void> gui({required String input, bool verbose = false, bool force = false, bool web = false, int? linecount}) async {
  List<String> args = [input, if (verbose) "--verbose", if (force) "--force", if (linecount != null && linecount >= 0) "--linecount=$linecount"];
  await main(args, alt: true, web: web);
  return;
}

Future<void> cli(List<String> arguments) async {
  await main(arguments);
  return;
}

Future<void> main(List<String> arguments, {bool alt = false, bool web = false}) async {
  if (lock == true) {
    return print([Log("Error", effects: [31]), Log(": Process already started")], overrideOutputToController: alt);
  }

  OCLog oclog;
  bool directLog = false;

  lock = true;
  outputToController = alt;

  try {
    if (alt == false) throw Exception();
    if (!arguments[0].contains("00:000 00:000 OC: Starting OpenCore...")) throw Exception();
    directLog = true;
  } catch (e) {
    directLog = false;
  }

  ArgParser parser = ArgParser()
    ..addFlag("help", abbr: "h", negatable: false, help: "Show usage")
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose output')
    ..addFlag('force', abbr: 'f', negatable: false, help: 'Ignore unsupported configuration warnings')
    ..addOption('linecount', help: "How many lines of the end of the log to show.");

  try {
    args = parser.parse(arguments);
  } catch (e) {
    error([Log("$e")], exitCode: 1);
  }

  List rest = args.rest;
  String usage = "oclog (log file: file path, direct URL) [--help] [--verbose] [--force] [--linecount=x]";
  int defaultcount = 15;
  int count = defaultcount;

  if (args["linecount"] == null || int.tryParse(args["linecount"]) == null || int.parse(args["linecount"]) < 0) {
    verboseerror("line count", [Log("count was invalid: ${args["linecount"]}")]);
  } else {
    count = int.parse(args["linecount"]);
  }

  if (args["help"] == true || rest.isEmpty) {
    print([Log("Usage: $usage")]);
    return;
  }

  if (directLog) {
    oclog = parseLog(rest[0]);
  } else {
    oclog = await getLog(rest[0]);
  }

  List<String> tools = [];
  List<String> drivers = [];
  List<OCLogEntry> entries = [];

  for (String item in oclog.logs.where((String item) => RegExp(r"Adding custom entry .+\.efi \(tool\|B:0\)").hasMatch(item))) {
    String tool = item.split("Adding custom entry")[1].split("(tool|B:0)")[0].trim();
    verbose([Log("found tool: $tool")]);
    tools.add(tool);
  }

  for (String item in oclog.logs.where((String item) => RegExp(r"Driver .+\.efi at \d+ is successfully loaded!").hasMatch(item))) {
    String driver = item.split("Driver")[1].split(RegExp(r"at \d+ is successfully loaded!"))[0].trim();
    verbose([Log("found driver: $driver")]);
    drivers.add(driver);
  }

  for (String item in oclog.logs.where((String item) => RegExp(r"Registering entry .+ \[.+]").hasMatch(item))) {
    String name = item.split("Registering entry")[1].split("[")[0].trim();
    String type = item.split("[")[1].split("]")[0];
    String path = item.split("-")[1].trim();
    verbose([Log("found entry: $name ($type) ($path)")]);
    entries.add(OCLogEntry(entry: name, type: type, path: path));
  }

  entries = entries.toSet().toList();

  String bootedline = oclog.logs.firstWhere((String item) => item.contains("Should boot from"));
  String? booted = RegExp(r'\b([A-Z][a-zA-Z]+)\s*\(').firstMatch(bootedline)?.group(1);
  bool showedMenu = oclog.logs.any((String item) => item.contains("OCB: Showing menu... "));

  if (drivers.isNotEmpty) {
    title([Log("Drivers (${drivers.length})")]);

    for (int i = 0; i < drivers.length; i++) {
      String driver = drivers[i];
      log([Log("${i + 1}. "), Log(driver, effects: [1])]);
    }
  }

  if (entries.isNotEmpty) {
    title([Log("Picker Entries")]);

    for (int i = 0; i < entries.length; i++) {
      OCLogEntry entry = entries[i];
      log([Log("${i + 1}. "), Log(entry, effects: [1])]);
    }
  }

  title([Log("Misc")]);
  log([Log("Log line length: "), Log(oclog.logs.length, effects: [1]), Log(" lines")]);
  log([Log("Entry booted: "), Log(booted, effects: [1])]);
  log([Log("Menu showed: "), if (showedMenu == false) Log("No", effects: [1]), if (showedMenu == true) ...[Log("For "), Log("${0}ms", effects: [1])]]);
  log([Log("Successful macOS boot: "), Log(oclog.successful, effects: [1])]);

  if (count > 0) {
    title([Log("Last $count Lines")]);

    for (int i = 0; i < count; i++) {
      int index = oclog.logs.length - (count - i);
      String line = oclog.logs[index];
      log([Log("${index + 1}. "), Log(line)]);
    }
  }
}

OCLog parseLog(String raw) {
  return OCLog(raw: raw, input: raw.split("\n"))..setSuccessful();
}

Future<OCLog> getLog(String path) async {
  String? raw = await getData(path);
  
  if (raw == null) {
    error([Log("Invalid log file path: $path")]);
    didExit();
  }

  try {
    return parseLog(raw);
  } catch (e) {
    error([Log("Invalid log file format: $e")], exitCode: 1);
    didExit();
  }
}