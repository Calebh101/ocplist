import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/logger.dart';
import 'package:ocplist/src/main.dart';
import 'package:path/path.dart' as Path;
import 'package:http/http.dart';

String getExec([String? version]) {
  String versionstring = "";

  if (version != null) {
    versionstring = "-$version";
  }

  if (Platform.isLinux) {
    return "ocvalidate$versionstring.linux";
  } else if (Platform.isMacOS) {
    return "ocvalidate$versionstring";
  } else if (Platform.isWindows) {
    return "ocvalidate$versionstring.exe";
  } else {
    throw Exception("Invalid platform");
  }
}

File getFile(String? version) {
  String path = Path.joinAll([getDataDirectory().path, "ocvalidate", getExec(version)]);
  return File(path);
}

Future<void> assureDirectory() async {
  Directory directory = Directory(Path.join(getDataDirectory().path, "ocvalidate"));

  if (!(await directory.exists())) {
    await directory.create(recursive: true);
  }
}

Future<File?> getOcValidateFile({bool skipVersionCheck = false}) async {
  try {
    String? version;
    Response? response;
    List? assets;
    Uri uri = Uri.parse("https://api.github.com/repos/Acidanthera/OpenCorePkg/releases");

    try {
      print([Log("Downloading OCValidate info...")]);
      response = await get(uri).timeout(Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception("Status code: ${response.statusCode}");
    } catch (e) {
      log([Log("OCValidate download error (stage 1): $e", effects: [31])]);
    }

    if (response != null && response.statusCode == 200) {
      List body = jsonDecode(response.body);
      Map release = body[0];

      assets = release["assets"];
      version = release["name"];
    }

    File file = getFile(version);
    if (await file.exists()) {
      return file;
    } else if (assets != null) {
      log([Log("Downloading OCValidate...")]);
      Map asset = assets.firstWhere((item) => item["name"] == "OpenCore-$version-RELEASE.zip");
      Uri assetUrl = Uri.parse(asset["browser_download_url"]);

      try {
        Response response = await get(assetUrl).timeout(Duration(seconds: 60));
        if (response.statusCode != 200) throw Exception("Status code: ${response.statusCode}");
        Archive archive = ZipDecoder().decodeBytes(response.bodyBytes);
        ArchiveFile? file = archive.findFile("Utilities/ocvalidate/${getExec()}");
        await assureDirectory();
        if (file == null) throw Exception("Could not find archive file.");
        File out = getFile(version)..createSync();
        await out.writeAsBytes(file.content);
        return out;
      } catch (e) {
        log([Log("OCValidate download error (stage 2): $e", effects: [31])]);
      }
    } else {
      throw Exception("assets was null.");
    }
  } catch (e) {
    verboseerror("get ocvalidate file", [Log(e)]);
  }

  return null;
}

Future<void> ocvalidateweb(String raw) async {
  verbose([Log("OCValidate is not supported on Web!")]);
}