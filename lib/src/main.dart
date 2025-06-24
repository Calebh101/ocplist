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
bool lock = false;
StreamController controller = StreamController.broadcast();

Future<String?> getData(String path) async {
  String? raw;

  try {
    File file = File(path);
    if (file.existsSync()) {
      verbose([Log("Found plist: ${file.path}")]);
      raw = file.readAsStringSync();
    }
  } catch (e) {
    null;
  }

  if (raw == null) {
    try {
      Uri? uri = Uri.tryParse(path);
      if (uri != null) {
        print([Log("Downloading file...")]);
        http.Response response = await http.get(uri).timeout(Duration(seconds: 10));

        if (response.statusCode == 200) {
          verbose([Log("Found plist: $uri")]);
          raw = utf8.decode(response.bodyBytes);
        } else {
          error([Log("Got bad response: ${response.body} (status code: ${response.statusCode})")], exitCode: 2);
        }
      }
    } catch (e) {
      null;
    }
  }

  if (raw == null) {
    error([Log("Invalid plist path: $path")], exitCode: 3);
  } else {
    return raw;
  }

  return null;
}

Never didExit() {
  return exit(-1);
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
  return lock;
}

StreamController getController() {
  return controller;
}