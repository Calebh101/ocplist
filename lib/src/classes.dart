import 'dart:convert';

class Log {
  dynamic input;
  List<int> effects;
  Log(this.input, {List<int>? effects}) : effects = List.from(effects ?? []);

  @override
  String toString() {
    return "${effects.map((int item) => "\x1b[${item}m").join("")}$input${"\x1b[0m"}";
  }
}

class Plist {
  String raw;
  Map json;
  Plist({required this.raw, required this.json});
}

class UnsupportedConfiguration {
  UnsupportedConfigurationType type;
  List<List<Log>> reason;
  UnsupportedConfiguration({required this.type, this.reason = const []});

  String getTypeString() {
    String delim = " - ";
    switch (type) {
      case UnsupportedConfigurationType.OpcoreSimplify: return ["Prebuilt","Auto-Tool","OpCore Simplify"].join(delim);
      case UnsupportedConfigurationType.GeneralConfigurator: return ["Configurator"].join(delim);
      case UnsupportedConfigurationType.OCAT: return ["Configurator","OCAT"].join(delim);
      case UnsupportedConfigurationType.OCC: return ["Configurator","OpenCore Configurator"].join(delim);
      case UnsupportedConfigurationType.Olarila: return ["Prebuilt","Distro","Olarila"].join(delim);
      case UnsupportedConfigurationType.TopLevel: return ["Bootloader","Potentially not OpenCore"].join(delim);
      case UnsupportedConfigurationType.TopLevelClover: return ["Bootloader","Clover"].join(delim);
    }
  }

  @override
  String toString() {
    return "UnsupportedConfiguration(type: $type, reason: ${jsonEncode(reason)})";
  }
}

enum UnsupportedConfigurationType {
  OpcoreSimplify,
  Olarila,
  OCAT,
  OCC,
  GeneralConfigurator,
  TopLevel,
  TopLevelClover,
}