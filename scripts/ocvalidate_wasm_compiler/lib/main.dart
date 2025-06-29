import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

Uri opencorepkg = Uri.parse("https://github.com/acidanthera/OpenCorePkg/archive/refs/heads/master.zip");

void main(List<String> arguments) async {
  try {
    print("Fetching OpenCorePkg from $opencorepkg...");
    http.Response response = await http.get(opencorepkg).timeout(Duration(seconds: 60));
    print("Found response: ${response.statusCode}");
    if (response.statusCode != 200) throw Exception("Status code: ${response.statusCode}");
    String target = "OpenCorePkg-master/Utilities/ocvalidate";
    Archive archive = ZipDecoder().decodeBytes(response.bodyBytes);
    List<ArchiveFile> files = archive.where((ArchiveFile file) => file.isFile && file.name.startsWith('$target/')).toList();
    Directory dir = await Directory.systemTemp.createTemp('ocvalidate_wasm_compiler_');
    print("Extracting ${files.length} files from $target...");

    for (ArchiveFile file in files) {
      String relative = file.name.substring(target.length + 1);
      String outdir = p.join(dir.path, relative);
      File out = File(outdir);

      await out.parent.create(recursive: true);
      await out.writeAsBytes(file.content as List<int>);
    }

    print("Compiling as WASM...");
    throw UnimplementedError("OCValidate is not supported on web.");
  } catch (e) {
    print("OCValidate download error (stage 2): $e");
  }
}