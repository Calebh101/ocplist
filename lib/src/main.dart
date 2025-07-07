import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/logger.dart';
import 'package:path/path.dart' as p;

late ArgResults args;
late bool outputToController;
List<LogMode> lock = [];
StreamController controller = StreamController.broadcast();
String version = "1.0.0A";
int? timeout;

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

Future<String?> getData(String path, {required LogMode mode, required bool gui, required RegExp fileRegex}) async {
  String? raw;
  String reason = "error";
  verbose([Log("Judging path $path (${path.runtimeType})")]);

  try {
    String filePath = p.absolute(path.replaceAll("~", getHome()!.path));
    verbose([Log("File path: $filePath")]);
    File file = File(filePath);

    if (file.existsSync()) {
      verbose([Log("Found file: $filePath")]);
      raw = file.readAsStringSync();
    } else {
      throw FileSystemException("File not found", filePath);
    }
  } catch (e) {
    verboseerror("getData file", [Log(e)]);
  }

  if (raw == null) {
    try {
      Uri? uri = Uri.tryParse(path);

      FutureOr<void> match(String name, RegExp regex, {required FutureOr<String> Function(List<String>) callback}) async {
        try {
          RegExpMatch firstMatch = regex.allMatches(path).first;
          List<String> match = firstMatch.groups(List.generate(firstMatch.groupCount, (i) => i + 1)).whereType<String>().toList();
          String result = await callback.call(match);
          Uri url = Uri.parse(result);
          uri = url;
          log([Log("Detected "), Log(name, effects: [1]), Log(" file: "), Log(match.join(" - "), effects: [1])]);
        } catch (e) {
          verboseerror("matchUrl[$name]", [Log(e)]);
        }
      }

      await match("Google Drive", RegExp(r"https?:\/\/drive\.google\.com\/file\/d\/([^\/]+).*"), callback: (List<String> id) => "https://drive.usercontent.google.com/u/0/uc?id=${id[0]}&export=download");
      await match("Pastebin", RegExp(r"https?:\/\/pastebin\.com\/([^\/]+).*"), callback: (List<String> id) => "https://drive.usercontent.google.com/u/0/uc?id=$id&export=download");
      await match("GitHub File", RegExp(r"^https:\/\/github\.com\/([^\/]+)\/([^\/]+)\/(blob|tree)\/([^\/]+)\/(.+)$"), callback: (List<String> id) => "https://raw.githubusercontent.com/${id[0]}/${id[1]}/refs/heads/${id[3]}/${id[4]}");

      await match("GitHub Repo", RegExp(r"^https:\/\/github\.com\/([^\/]+)\/([^\/]+)(?:\/(blob|tree)\/([^\/]+))?\/?$"), callback: (List<String> id) async {
        String owner = id[0];
        String repo = id[1];

        return "https://github.com/$owner/$repo/archive/refs/heads/${id.elementAtOrNull(3) ?? await (() async {
          log([Log("Finding default branch of "), Log("$owner/$repo", effects: [1]), Log("...")]);
          Uri url = Uri.parse('https://api.github.com/repos/$owner/$repo');
          http.Response response = await http.get(url);
          String branch;

          if (response.statusCode == 200) {
            Map data = jsonDecode(response.body);
            branch = data['default_branch'];
          } else {
            verboseerror("matchUrl[GitHub Repo].elementAtOrNull(3).branchChecker.postResponse", [Log("Status code was ${response.statusCode}")]);
            branch = "master";
          }

          return branch;
        })()}.zip";
      });

      if (uri != null) {
        uri = Uri.parse("https://corsproxy.io/?$uri"); // I know not the preferred solution, I'll change this later
        print([Log("Downloading file from "), Log(uri, effects: [1]), Log("...")]);
        http.Response response = timeout != null ? await http.get(uri!).timeout(Duration(seconds: timeout!)) : await http.get(uri!);

        if (response.statusCode == 200) {
          verbose([Log("Found file: $uri")]);
          try {
            raw = utf8.decode(response.bodyBytes);
          } catch (e) {
            try {
              verboseerror("getData uri utf8.decode", [Log(e)]);
              Archive archive = ZipDecoder().decodeBytes(response.bodyBytes);
              verbose([Log("Found archive: ${archive.files.length} files")]);
              List<ArchiveFile> found = [];
              ArchiveFile? selected;

              for (ArchiveFile file in archive.files) {
                Iterable<RegExpMatch> matches = RegExp(fileRegex.pattern, caseSensitive: false).allMatches(file.name);
                if (matches.isNotEmpty) found.add(file);
              }

              if (found.isEmpty) {
                found.add(archive.first);
              }

              log([Log("Found "), Log(found.length, effects: [1]), Log(" matching ${countword(count: found.length, singular: "file")} in archive")]);
              if (found.length > 1) {
                newline();
                log([Log("We found "), Log(found.length, effects: [1]), Log(" files. Please select a files to use.")]);
                newline();

                for (int i = 0; i < found.length; i++) {
                  ArchiveFile file = found[i];
                  log([Log("${i + 1}. "), Log(file.name, effects: [1]), Log(" (last modified "), Log(DateFormat("M/dd/yyyy h:mm a").format(file.lastModDateTime), effects: [1]), Log(")")]);
                }

                newline();
                int i = 0;

                if (gui) {} else {
                  while (selected == null) {
                    if (i == 0) {
                      stdout.write("Please type the file path or index of the chosen file. Type q to quit.\nInput   >> ");
                    } else {
                      stdout.write("Invalid >> ");
                    }

                    String? input = stdin.readLineSync();

                    if (input != null) {
                      input = input.toLowerCase();

                      if (input == "q" || input == "") {
                        quit(mode: mode, gui: gui);
                      } else {
                        i++;

                        if (int.tryParse(input) != null) {
                          int x = int.parse(input);
                          if (x <= found.length && x > 0) {
                            selected = found[x - 1];
                            stdout.writeln();
                          }
                        }
                      }
                    } else {
                      selected = found.first;
                    }
                  }
                }
              } else {
                selected = found.first;
              }

              verbose([Log("Parsing file ${selected!.name}...")]);
              raw = utf8.decode(selected.readBytes()!);
            } catch (e) {
              verboseerror("getData uri zip.decode", [Log(e)]);
            }
          }
        } else {
          error([Log("Got bad response: ${response.body} (status code: ${response.statusCode})")], exitCode: 2, mode: mode, gui: gui);
        }
      }
    } catch (e) {
      verboseerror("getData uri", [Log(e)]);
      if (e is TimeoutException) reason = "Timeout at ${e.duration?.inSeconds ?? 0}s";
    }
  }

  if (raw == null) {
    error([Log("Invalid file: $path ($reason)")], exitCode: 3, mode: mode, gui: gui);
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

Directory? getHome() {
  String? home = Platform.isWindows ? Platform.environment['USERPROFILE'] : Platform.environment['HOME'];
  if (home == null) return null;
  verbose([Log("Found home: $home")]);
  return Directory(home);
}

Directory getDataDirectory() {
  Directory home = getHome()!;
  String path = p.joinAll([home.path, ".ocplist"]);
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
