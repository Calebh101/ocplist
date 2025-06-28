import 'dart:io';

import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/main.dart';

void print(List<Log> input, {bool? overrideOutputToController}) {
  input = input.where((e) => e.input != null).toList();
  if (input.isEmpty) return;

  if (overrideOutputToController ?? outputToController) {
    controller.sink.add(input);
  } else {
    stdout.writeln(input.map((item) => item.toString()).join(""));
  }
}

void title(List<Log> logs, {bool subtitle = false, bool linebreak = true, required double Function()? overrideTerminalWidth}) {
  int width = (() {
    if (overrideTerminalWidth != null) {
      return overrideTerminalWidth().floor();
    } else {
      return stdout.terminalColumns;
    }
  })();

  int chars = logs.map((item) => item.input.toString()).join("").length + 2;
  int count = ((width - chars) / 2).ceil();
  int count2 = count;
  int spaces = 0;
  int spaces2 = 0;

  if (count < 0) count = 0;
  if (count * 2 + chars > width) count2 = count - 1;
  if (linebreak) newline();

  if (subtitle) {
    if (count > 10) {
      spaces = count - 10;
      spaces2 = count2 - 10;
      count = 10;
      count2 = 10;
    }
  }

  print([if (spaces > 0) Log("${" " * spaces} "), Log("${"-" * count} "), ...logs.map((item) {
    if(subtitle == false) item.effects.add(1);
    return item;
  }), Log(" ${"-" * count2}"), if (spaces > 0) Log("${" " * spaces2} ")]);

  if (linebreak) {
    newline();
  }
}

void log(List<Log> logs) {
  logs = logs.where((e) => e.input != null).toList();
  if (logs.isEmpty) return;
  print(logs);
}

void error(List<Log> input, {required LogMode mode, int? exitCode, required bool gui}) {
  print([Log("Error: "), ...input.map((Log item) => item..effects.addAll([1, 31]))]);
  if (exitCode != null) quit(code: exitCode, mode: LogMode.plist, gui: gui);
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
