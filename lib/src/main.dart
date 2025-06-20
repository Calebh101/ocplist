import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ocplist/ocplist.dart';
import 'package:ocplist/src/logger.dart';

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