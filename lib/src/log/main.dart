import 'package:args/args.dart';
import 'package:ocplist/src/main.dart';
import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/logger.dart';

// Exit Codes
  // 0: OK
  // 1: Not debug
  // 2: Already started

Future<void> OcLogGui({required String input, bool verbose = false, bool force = false, bool web = false, int? linecount, required double Function() terminalwidth}) async {
  List<String> args = [input, if (verbose) "--verbose", if (force) "--force", if (linecount != null && linecount >= 0) "--linecount=$linecount"];
  await main(args, alt: true, web: web, terminalwidth: terminalwidth);
  return;
}

Future<void> cli(List<String> arguments) async {
  await main(arguments);
  return;
}

Future<void> main(List<String> arguments, {bool alt = false, bool web = false, double Function()? terminalwidth}) async {
  if (lock.contains(LogMode.log)) {
    print([Log("Error", effects: [31]), Log(": Process already started")], overrideOutputToController: alt);
    quit(mode: LogMode.log, code: 2, gui: alt);
  }

  OCLog oclog;
  bool directLog = false;

  lock.add(LogMode.log);
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
    error([Log("$e")], exitCode: 1, mode: LogMode.log, gui: alt);
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
    oclog = await getLog(rest[0], gui: alt);
  }

  verbose([Log("Generating report...")]);
  log([Log.event(LogEvent.resultstart)]);
  logversion("oclog");

  List<String> tools = [];
  List<String> drivers = [];
  List<OCLogEntry> entries = [];
  List<OCLogKext> kexts = [];

  String? version = (() {
    try {
      String line = oclog.logs.firstWhere((String item) => RegExp(r"OpenCore DBG-[0-9-]+ is loading").hasMatch(item));
      String version = line.split("OpenCore")[1].split("is loading")[0].trim();
      return version;
    } catch (e) {
      verboseerror("version decider", [Log(e)]);
      return null;
    }
  })();

  if (version == null) {
    error([Log("This OpenCore log is not a debug log!", effects: [31, 1])], exitCode: 1, mode: LogMode.log, gui: alt);
  }

  for (String item in oclog.logs.where((String item) => RegExp(r"Prelinked injection .+\.kext v.+").hasMatch(item))) {
    String line = item.split("Prelinked injection")[1].trim();
    verbose([Log("found kext: $line")]);
    String name = line.split(" ")[0];
    String version = line.split("v").last;
    kexts.add(OCLogKext(name, version));
  }

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
  bool showedMenu = oclog.logs.any((String item) => item.contains("OCB: Showing menu... "));

  String? booted = (() {
    try {
      String bootedLine = oclog.logs.firstWhere((String item) => item.contains("Should boot from"));
      return RegExp(r'\b([A-Z][a-zA-Z]+)\s*\(').firstMatch(bootedLine)?.group(1);
    } catch (e) {
      verboseerror("booted", [Log(e)]);
      return null;
    }
  })();

  String? bootargs = (() {
    try {
      return oclog.logs.firstWhere((String item) => RegExp(r'\[EB\|MBA:OUT\] <".*?">').hasMatch(item)).split("<\"")[1].split("\">")[0].trim();
    } catch (e) {
      verboseerror("bootargs", [Log(e)]);
      return null;
    }
  })();

  double? showedMenuMs = (() {
    try {
      int i = oclog.logs.indexWhere((String item) => item.contains("OCB: Showing menu... "));
      List<String> startraw = oclog.logs[i].split(" ")[0].split(":");
      List<String> endraw = oclog.logs[i + 1].split(" ")[0].split(":");
      OCLogTimestamp start = OCLogTimestamp(int.parse(startraw[0]), int.parse(startraw[1]));
      OCLogTimestamp end = OCLogTimestamp(int.parse(endraw[0]), int.parse(endraw[1]));
      return (end - start).toDouble();
    } catch (e) {
      verboseerror("showedMenuMs", [Log(e)]);
      return null;
    }
  })();

  if (drivers.isNotEmpty) {
    title([Log("Drivers (${drivers.length} ${countword(count: drivers.length, singular: "driver")})")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < drivers.length; i++) {
      String driver = drivers[i];
      log([Log("${i + 1}. "), Log(driver, effects: [1])]);
    }
  }

  if (tools.isNotEmpty) {
    title([Log("Tools (${tools.length} ${countword(count: tools.length, singular: "tool")})")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < tools.length; i++) {
      String tool = tools[i];
      log([Log("${i + 1}. "), Log(tool, effects: [1])]);
    }
  }

  if (kexts.isNotEmpty) {
    title([Log("Kexts (${kexts.length} ${countword(count: kexts.length, singular: "kext")})")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < kexts.length; i++) {
      OCLogKext kext = kexts[i];
      log([Log("${i + 1}. "), Log(kext, effects: [1])]);
    }
  }

  if (entries.isNotEmpty) {
    title([Log("Picker Entries")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < entries.length; i++) {
      OCLogEntry entry = entries[i];
      log([Log("${i + 1}. "), Log(entry, effects: [1])]);
    }
  }

  title([Log("Misc")], overrideTerminalWidth: terminalwidth);
  log([Log("OpenCore version: "), Log(version, effects: [1])]);
  log([Log("Log line length: "), Log(oclog.logs.length, effects: [1]), Log(" lines")]);
  log([Log("Entry booted: "), Log(booted, effects: [1])]);
  log([Log("Menu shown: "), if (showedMenu == false) Log("No", effects: [1]), if (showedMenu == true && showedMenuMs != null) ...[Log("For "), Log("${showedMenuMs}s", effects: [1])], if (showedMenu == true && showedMenuMs == null) ...[Log("Yes")]]);
  log([Log("Successful boot.efi boot: "), Log(oclog.successful ? "Yes" : "No", effects: [1])]);
  log([Log("Boot arguments: "), Log(bootargs ?? "None", effects: [1])]);

  if (count > 0) {
    title([Log("Last $count ${countword(count: count, singular: "Line")}")], overrideTerminalWidth: terminalwidth);

    for (int i = 0; i < count; i++) {
      int index = oclog.logs.length - (count - i);
      String line = oclog.logs[index];
      log([Log("${index + 1}. "), Log(line)]);
    }
  }

  verbose([Log("Parse complete!")]);
  lock.remove(LogMode.log);
}

OCLog parseLog(String raw) {
  return OCLog(raw: raw, input: raw.split("\n"))..setSuccessful();
}

Future<OCLog> getLog(String path, {required bool gui}) async {
  String? raw = await getData(path, mode: LogMode.plist, gui: gui, fileRegex: RegExp(r"^opencore-\d{4}-\d{2}-\d{2}-\d{6}\.txt$"));
  
  if (raw == null) {
    error([Log("Invalid log file path: $path")], mode: LogMode.log, gui: gui);
    didExit();
  }

  try {
    return parseLog(raw);
  } catch (e) {
    error([Log("Invalid log file format: $e")], exitCode: 1, mode: LogMode.log, gui: gui);
    didExit();
  }
}