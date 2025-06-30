import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localpkg/dialogue.dart';
import 'package:localpkg/functions.dart';
import 'package:ocplist/oclog.dart';
import 'package:ocplist/ocplist.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:localpkg/logger.dart';

double logFontSize = kIsWeb ? 13 : 11;
FontWeight logBoldedWeight = kIsWeb ? FontWeight.w600 : FontWeight.w700;
String fontFamily = "Hack";
List<String> fontFamilyFallbacks = ["monospace", "Courier New"];
Map<OCPlistMode, List<List<Log>>> allLogs = {};

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "OCPlist",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white, // Light background
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black, // Dark background
      ),
      themeMode: ThemeMode.system,
      home: Home(),
    );
  }
}

enum OCPlistMode {
  plist,
  log,
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  OCPlistMode mode = OCPlistMode.plist;
  OCPlistMode prevmode = OCPlistMode.plist;
  StreamSubscription? subscription;
  List<List<Log>> log = [];
  List<List<Log>> result = [];
  bool verbose = false;
  bool force = false;
  bool showOcPlistLogs = false;
  ScrollController scrollController = ScrollController();
  TextEditingController textController = TextEditingController();
  bool loggingresult = false;
  String text = "";

  void add(List<Log> input) {
    List<Log>? resultS = [];
    List<Log> logS = [];
    if (showOcPlistLogs) print("OCPlist: ${input.map((input) => input.toString()).join("")}");

    for (Log item in input) {
      if (item.event == LogEvent.resultstart) {
        loggingresult = true;
        result = [];
      } else if (item.event == LogEvent.resultend || item.event == LogEvent.quit) {
        loggingresult = false;
      } else if (item.event == null) {
        logS.add(item);
        if (loggingresult) resultS.add(item);
      }
    }

    if (loggingresult) result.add(resultS);
    if (logS.isNotEmpty) log.add(logS);

    if (scrollController.position.pixels > (scrollController.position.maxScrollExtent - 10)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(Duration(milliseconds: 50), () {
          if (scrollController.hasClients) {
            scrollController.jumpTo(scrollController.position.maxScrollExtent);
          }
        });
      });
    }

    refresh();
  }

  void clear() {
    log = [];
    refresh();
  }

  void refresh() async {
    if (prevmode == mode) {
      allLogs[mode] = log;
      setState(() {});
    } else {
      allLogs[prevmode] = log;
      log = allLogs[mode] ?? [];

      (() async {
        SharedPreferences prefs = await SharedPreferences.getInstance();

        switch (mode) {
          case OCPlistMode.plist:
            prefs.setInt("mode", 0);
            break;
          case OCPlistMode.log:
            prefs.setInt("mode", 1);
            break;
        }

        print("set preferred mode to ${prefs.getInt("mode")}");
      })();

      prevmode = mode;
      setState(() {});
      if (scrollController.hasClients) scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  @override
  void initState() {
    super.initState();
    subscription = getOcController().stream.listen((dynamic data) => add(data));

    (() async {
      int? value = (await SharedPreferences.getInstance()).getInt("mode");
      bool success = false;

      switch (value) {
        case 0:
          mode = OCPlistMode.plist;
          success = true;
          break;
        case 1:
          mode = OCPlistMode.log;
          success = true;
          break;
      }

      if (success) {
        prevmode = mode;
        refresh();
      }
    })();
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    RegExp pattern = RegExp(r"\n|\r");
    textController.text = text.replaceAll(pattern, "");
    bool multiline = text.contains(pattern);
    double padding = 8;
    int length = log.length * 2 - 1;
    if (length < 0) length = 0;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: DropdownButton<OCPlistMode>(items: [
          DropdownMenuItem(value: OCPlistMode.plist, child: Text("OCPlist")),
          DropdownMenuItem(value: OCPlistMode.log, child: Text("OCLog")),
        ], onChanged: (OCPlistMode? value) {
          if (value == null || isLocked()) return;
          mode = value;
          refresh();
        }, value: mode),
        actions: [
          PopupMenuButton<String>(
            tooltip: "Extra Options",
            itemBuilder: (BuildContext context) {
              void share<T>(T name, String option, dynamic input) {
                showDialogue(context: context, title: "OCPlist $option Log", copy: true, copyText: "$input", content: SingleChildScrollView(child: SelectableText("$input", style: TextStyle(fontSize: logFontSize, fontFamily: "monospace"))));
              }

              List<PopupMenuEntry<T>> generateExportEntries<T>({required List<ExportItemEntry<T>> entries}) {
                List<PopupMenuEntry<T>> wholeLog = [];
                List<PopupMenuEntry<T>> resultLog = [];

                for (ExportItemEntry entry in entries) {
                  if (log.isNotEmpty) {
                    wholeLog.add(
                      PopupMenuItem<T>(
                        onTap: () {
                          share(entry.name, entry.option, entry.value.call(log));
                        },
                        value: entry.name,
                        child: Row(
                          children: [
                            Icon(Icons.ios_share),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text("Export as ${entry.option}"),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (result.isNotEmpty) {
                    resultLog.add(
                      PopupMenuItem<T>(
                        onTap: () {
                          share(entry.name, entry.option, entry.value.call(result));
                        },
                        value: entry.name,
                        child: Row(
                          children: [
                            Icon(Icons.ios_share),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text("Export Result as ${entry.option}"),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                }

                return [...wholeLog, PopupMenuDivider(), ...resultLog];
              }

              return [
                PopupMenuItem(
                  onTap: () {
                    clear();
                  },
                  value: "clear",
                  child: Tooltip(
                    message: "Clear the console.",
                    child: Row(
                      children: [
                        Icon(Icons.clear),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text("Clear"),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuItem(
                  onTap: () {
                    verbose = !verbose;
                  },
                  value: "verbose",
                  child: Tooltip(
                    message: "Show extra debugging messages.",
                    child: Row(
                      children: [
                        Icon(verbose ? Icons.check_box_outlined : Icons.check_box_outline_blank),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text("Verbose"),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuItem(
                  onTap: () {
                    force = !force;
                  },
                  value: "force",
                  child: Tooltip(
                    message: "Force scan the config, even if it has invalid configurations.",
                    child: Row(
                      children: [
                        Icon(force ? Icons.check_box_outlined : Icons.check_box_outline_blank),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text("Force"),
                        ),
                      ],
                    ),
                  ),
                ),
                if (log.isNotEmpty && result.isNotEmpty)
                ...[
                  PopupMenuDivider(),
                  ...generateExportEntries<String>(entries: [
                    ExportItemEntry(name: "ascii", option: "ASCII", value: (List<List<Log>> value) => value.map((List<Log> item) => toraw(item)).join("\n").replaceAll("\n", "\\n")),
                    ExportItemEntry(name: "plaintext", option: "Plain Text", value: (List<List<Log>> value) => value.map((List<Log> item) => item.map((Log item) => item.input.toString()).join("")).join("\n")),
                  ]),
                ],
              ];
            },
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.upload),
                  onPressed: () async {
                    XTypeGroup typeGroup = XTypeGroup(
                      label: 'config.plist',
                      extensions: ['plist', 'xml', 'txt'],
                    );

                    try {
                      XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
                      if (file == null) return;
                      String content = await file.readAsString();
                      text = content;
                      refresh();
                    } catch (e) {
                      error("Upload config.plist: $e");
                      showSnackBar(context, "Unable to open file.");
                      if (verbose) log.add([Log("Unable to open file: $e", effects: [31])]);
                      refresh();
                    }
                  },
                ),
                Expanded(
                  child: multiline ? Row(
                    children: [
                      Expanded(
                        child: Text("Multiline file selected."),
                      ),
                      IconButton(
                        icon: Icon(Icons.backspace),
                        onPressed: () {
                          text = "";
                          refresh();
                        },
                      ),
                    ],
                  ) : TextField(
                    controller: textController,
                    decoration: InputDecoration(
                      hint: Text("URL, file path or full text..."),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () {
                    start(padding: padding);
                  },
                ),
              ],
            ),
            SizedBox(height: padding),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText.rich(
                      TextSpan(
                        children: List.generate(length, (int i) {
                          if (i.isEven) {
                            int index = i ~/ 2;
                            return generateLog(log[index], context: context);
                          } else {
                            return TextSpan(text: '\n');
                          }
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void start({required double padding}) {
    print("running script as $mode");
    if (log.isNotEmpty) log.addAll([[], [], []]);

    switch (mode) {
      case OCPlistMode.plist:
        OcPlistGui(input: text, verbose: verbose, terminalwidth: terminalwidth(context: context, padding: padding), web: kIsWeb, force: force);
        break;
      case OCPlistMode.log:
        OcLogGui(input: text, terminalwidth: terminalwidth(context: context, padding: padding), web: kIsWeb, force: force);
        break;
    }
  }
}

class ExportItemEntry<T> {
  final T name;
  final T option;
  final dynamic Function(List<List<Log>> value) value;
  const ExportItemEntry({required this.name, required this.option, required this.value});
}

enum LogEffect {
  bold,
  dim,
}

TextSpan generateLog(List<Log> input, {required BuildContext context}) {
  return TextSpan(
    children: List.generate(
      input.length,
      (int i) {
        Log item = input[i];
        List<Color> colors = [];
        List<LogEffect> effects = [];

        if (item.event != null) {
          return null;
        }

        for (int effect in item.effects) {
          switch (effect) {
            case 1:
              effects.add(LogEffect.bold);
              break;
            case 2:
              effects.add(LogEffect.dim);
              break;
            case 31:
              colors.add(Colors.red);
              break;
            case 32:
              colors.add(Colors.green);
              break;
            case 33:
              colors.add(Colors.yellow);
              break;
            default:
              throw Exception("Invalid effect: $effect");
          }
        }

        Color color = colors.lastOrNull ?? getColor(context: context, type: ColorType.theme);

        if (effects.contains(LogEffect.dim)) {
          color = color.withAlpha(200);
        }

        TextStyle style = TextStyle(color: color, fontWeight: effects.contains(LogEffect.bold) ? logBoldedWeight : null, fontSize: logFontSize, fontFamily: fontFamily, fontFamilyFallback: [...fontFamilyFallbacks, fontFamily]);
        return TextSpan(text: "${item.input}", style: style);
      },
    ).whereType<InlineSpan>().toList(),
  );
}

double Function() terminalwidth({required BuildContext context, String text = "-", required double padding}) {
  return (() {
    int count = ((MediaQuery.of(context).size.width - padding) / 9).floor();
    return count.toDouble();
  });
}

String toraw(List<Log> input) {
  List<int> bytes = input.map((Log log) => log.toString()).join("").codeUnits;

  return bytes.map((int b) {
    if (b >= 32 && b <= 126) {
      return String.fromCharCode(b);
    } else {
      return '\\x${b.toRadixString(16).padLeft(2, '0')}';
    }
  }).join("").replaceAll("\\x0a", "\n");
}