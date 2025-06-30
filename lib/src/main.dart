import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/logger.dart';
import 'package:path/path.dart' as Path;

late ArgResults args;
late bool outputToController;
List<LogMode> lock = [];
StreamController controller = StreamController.broadcast();
String version = "1.0.0A";

enum LogMode {
  plist,
  log,
}

void logversion(String mode) {
  log([Log("Starting ocplist:$mode version $version...")]);;
}

String getOcPlistVersion() {
  return version;
}

Future<String?> getData(String path, {required LogMode mode, required bool gui}) async {
  String? raw;
  verbose([Log("Judging path $path (${path.runtimeType})")]);

  try {
    File file = File(path);
    if (file.existsSync()) {
      verbose([Log("Found file: ${file.path}")]);
      raw = file.readAsStringSync();
    }
  } catch (e) {
    verboseerror("getData file", [Log(e)]);
  }

  if (raw == null) {
    try {
      Uri? uri = Uri.tryParse(path);

      for (RegExpMatch match in RegExp(r"https?:\/\/drive\.google\.com\/file\/d\/([^\/]+).*").allMatches(path)) {
        String? id = match.group(1);
        if (id == null) continue;
        log([Log("Detected Google Drive file: "), Log(id, effects: [1])]);
        uri = Uri.tryParse("https://drive.usercontent.google.com/u/0/uc?id=$id&export=download") ?? uri;
      }

      for (RegExpMatch match in RegExp(r"https?:\/\/pastebin\.com\/([^\/]+).*").allMatches(path)) {
        String? id = match.group(1);
        if (id == null) continue;
        log([Log("Detected Pastebin file: "), Log(id)]);
        uri = Uri.tryParse("https://pastebin.com/raw/$id") ?? uri;
      }

      if (uri != null) {
        print([Log("Downloading file...")]);
        uri = Uri.parse("https://corsproxy.io/?$uri"); // I know not the preferred solution, I'll change this later
        http.Response response = await http.get(uri).timeout(Duration(seconds: 10));

        if (response.statusCode == 200) {
          verbose([Log("Found file: $uri")]);
          raw = utf8.decode(response.bodyBytes);
        } else {
          error([Log("Got bad response: ${response.body} (status code: ${response.statusCode})")], exitCode: 2, mode: mode, gui: gui);
        }
      }
    } catch (e) {
      verboseerror("getData uri", [Log(e)]);
    }
  }

  if (raw == null) {
    error([Log("Invalid file path: $path")], exitCode: 3, mode: mode, gui: gui);
  } else {
    return raw;
  }

  return null;
}

Never quit({int code = 0, required LogMode mode, required bool gui}) {
  lock.remove(mode);
  if (gui) {
    log([Log.event(LogEvent.quit)]);
    didExit();
  } else {
    exit(code);
  }
}

Never didExit() {
  throw UnimplementedError();
}

String countword({required num count, required String singular, String? plural}) {
  plural ??= "${singular}s";
  return count == 1 || count == 1.0 ? singular : plural;
}

String getMacOSVersionForDarwinVersion(String darwin) {
  int base = int.parse(darwin.split(".")[0]);
  double result = 0;
  String name = "";

  if (base >= 5 && base < 20) {
    int version = base - 4;
    result = double.parse("10.$version");

    if (version >= 12) {
      name = "macOS";
    } else {
      name = "OS X";
    }
  } else if (base == 1) {
    int version = int.parse(darwin.split(".")[1]);
    name = "OS X";

    if (version == 3) {
      result = 10;
    } else if (version == 4) {
      result = 10.1;
    } else {
      throw Exception("Could not translate Darwin version to macOS version: $darwin - Could not relate to OS X 10.0 to 10.1");
    }
  } else if (base >= 20 && base <= 25) {
    result = base - 9;
    name = "macOS";
  } else {
    throw Exception("Could not translate Darwin version to macOS version: $darwin - Could not relate to macOS 10.0 to 16");
  }

  return "$name $result";
}

Directory getDataDirectory() {
  String home = (Platform.isWindows ? Platform.environment['USERPROFILE'] : Platform.environment['HOME'])!;
  String path = Path.joinAll([home, ".ocplist"]);
  return Directory(path);
}

bool isLocked() {
  return lock.isNotEmpty;
}

StreamController getOcController() {
  return controller;
}

List<Log> generateValueLogs(String input, {String delim = "||", bool start = false}) {
  List<String> items = input.split(delim);
  bool bold = start;
  List<Log> result = [];

  for (String item in items) {
    result.add(Log(item, effects: [if (bold) 1]));
    bold = !bold;
  }

  return result;
}