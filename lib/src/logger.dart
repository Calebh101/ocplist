import 'dart:io';

import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/plist.dart';

void print(List<Log> input, {bool? overrideOutputToController}) {
  if (overrideOutputToController ?? outputToController) {
    controller.sink.add(input);
  } else {
    stdout.writeln(input.map((item) => item.toString()).join(""));
  }
}

void title(List<Log> logs, {bool subtitle = false}) {
  int chars = logs.map((item) => item.input.toString()).join("").length + 2;
  int width = stdout.terminalColumns;
  int count = ((width - chars) / 2).ceil();
  int count2 = count;

  if (count < 0) count = 0;
  if (count * 2 + chars > width) count2 = count - 1;
  newline();

  print([Log("${"-" * count} "), ...logs.map((item) {
    if(subtitle == false) item.effects.add(1);
    return item;
  }), Log(" ${"-" * count2}")]);

  newline();
}

void log(List<Log> logs) {
  print(logs);
}

void error(List<Log> input, {int? exitCode}) {
  print([Log("Error: "), ...input]);
  if (exitCode != null) exit(exitCode);
}

void verboseerror(String location, List<Log> input) {
  if (args["verbose"] == true) {
    print([Log("Verbose ERROR (from: $location): "), ...input].map((item) {
    item.effects.addAll([2, 31]);
    return item;
  }).toList());
  }
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
  newline();
}

void newline() {
  print([Log("")]);
}

@Deprecated("Use title() to mark new sections instead.")
void sectiondelim() {
  int width = stdout.terminalColumns;
  print([Log("\n${"-" * width}\n")]);
}
