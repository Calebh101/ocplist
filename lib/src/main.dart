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

      void match(String name, RegExp regex, {required Uri? Function(List<String>) callback, int groups = 1}) {
        try {
          List<String> match = regex.allMatches(path).first.groups(List.generate(groups, (i) => i + 1)).whereType<String>().toList();
          if (match.length == groups) {
            log([Log("Detected "), Log(name, effects: [1]), Log(" file: "), Log(match.join(" - "), effects: [1])]);
            Uri? result = callback.call(match);
            if (result != null) uri = result;
          }
        } catch (e) {
          verboseerror("matchUrl[$name]", [Log(e)]);
        }
      }

      match("Google Drive", RegExp(r"https?:\/\/drive\.google\.com\/file\/d\/([^\/]+).*"), callback: (List<String> id) => Uri.tryParse("https://drive.usercontent.google.com/u/0/uc?id=${id[0]}&export=download"));
      match("Pastebin", RegExp(r"https?:\/\/pastebin\.com\/([^\/]+).*"), callback: (List<String> id) => Uri.tryParse("https://drive.usercontent.google.com/u/0/uc?id=$id&export=download"));
      match("GitHub", RegExp(r"^https:\/\/github\.com\/([^\/]+)\/([^\/]+)\/blob\/([^\/]+)\/(.+)$"), callback: (List<String> id) => Uri.tryParse("https://raw.githubusercontent.com/${id[0]}/${id[1]}/refs/heads/${id[2]}/${id[3]}"));

      if (uri != null) {
        uri = Uri.parse("https://corsproxy.io/?$uri"); // I know not the preferred solution, I'll change this later
        print([Log("Downloading file from "), Log(uri, effects: [1]), Log("...")]);
        http.Response response = await http.get(uri!).timeout(Duration(seconds: 10));

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