import 'dart:io';

import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/plist.dart';

void print(List<Log> input, {bool? overrideOtuputToController}) {
  if (overrideOtuputToController ?? outputToController) {
    controller.sink.add(input);
  } else {
    stdout.writeln(input.map((item) => item.toString()).join(""));
  }
}

void log(List<Log> logs) {
  print(logs);
}

void error(List<Log> input, {int? exitCode}) {
  print([Log("Error: "), ...input]);
  if (exitCode != null) exit(exitCode);
}

void verbose(List<Log> input) {
  if (args["verbose"] == true) {
    print([Log("Verbose: "), ...input].map((item) {
      item.effects.add(2);
      return item;
    }).toList());
  }
}

void snippetdelim() {
  print([Log("")]);
}

void sectiondelim() {
  int width = stdout.terminalColumns;
  print([Log("\n${"-" * width}\n")]);
}
