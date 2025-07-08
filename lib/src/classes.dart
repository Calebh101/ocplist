import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:ocplist/src/logger.dart';

enum LogType {
  standard,
  tab,
}

enum LogEvent {
  quit,
  resultstart,
  resultend,
}

class Log {
  dynamic input;
  List<int> effects;
  bool _tab;
  LogEvent? event;

  LogType get type => _tab ? LogType.tab : LogType.standard;
  Log(this.input, {List<int>? effects}) : effects = List.from(effects ?? []), _tab = false;
  Log.tab() : input = null, effects = [], _tab = true;
  Log.event(this.event) : input = null, effects = [], _tab = false;
  Log.yesNo(bool status, {String? yesText, String? noText, bool reverseColors = false}) : input = (status ? (yesText ?? "Yes") : (noText ?? "No")), effects = [1, (status && reverseColors ? 31 : (status ? 32 : 31))], _tab = false;

  @override
  String toString() {
    return _tab ? "\t" : "${effects.map((int item) => "\x1b[${item}m").join("")}$input${"\x1b[0m"}";
  }
}

class Plist {
  String raw;
  Map json;
  Plist({required this.raw, required this.json});

  Map operator [](String key) {
    return json[key];
  }
}

class UnsupportedConfiguration {
  UnsupportedConfigurationType type;
  List<List<Log>> reason;
  UnsupportedConfigurationStatus status;
  UnsupportedConfiguration({required this.type, this.reason = const [], this.status = UnsupportedConfigurationStatus.error});

  String getTypeString({String delim = " - "}) {
    switch (type) {
      case UnsupportedConfigurationType.OpcoreSimplify: return ["Prebuilt", "Auto-Tool", "OpCore Simplify"].join(delim);
      case UnsupportedConfigurationType.OCEfiMaker: return ["Prebuilt", "Auto-Tool", "OC-EFI-Maker"].join(delim);
      case UnsupportedConfigurationType.GeneralConfigurator: return ["Plist Tool", "Configurator"].join(delim);
      case UnsupportedConfigurationType.OCAT: return ["Plist Tool", "Configurator", "OCAT"].join(delim);
      case UnsupportedConfigurationType.OCC: return ["Plist Tool", "Configurator", "OpenCore Configurator"].join(delim);
      case UnsupportedConfigurationType.Olarila: return ["Prebuilt", "Distro", "Olarila"].join(delim);
      case UnsupportedConfigurationType.TopLevel: return ["Bootloader", "Potentially not OpenCore"].join(delim);
      case UnsupportedConfigurationType.TopLevelClover: return ["Bootloader", "Clover"].join(delim);
      case UnsupportedConfigurationType.Hackintool: return ["Plist Tool", "Hackintool"].join(delim);
      case UnsupportedConfigurationType.OldSchema: return ["Bootloader", "Old OpenCore Schema"].join(delim);
    }
  }

  @override
  String toString() {
    return "UnsupportedConfiguration(type: $type, reason: ${jsonEncode(reason)}, status: $status)";
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
  Hackintool,
  OldSchema,
  OCEfiMaker,
}

enum UnsupportedConfigurationStatus {
  warning,
  error,
}

extension MapAccessExtension on Map {
  dynamic operator *(List<String> keys) {
    dynamic value = this;

    for (String key in keys) {
      if (value is! Map) return null;
      value = value[key];
    }

    return value;
  }
}

class OpenCoreVersion {
  final bool _latest;
  bool get latest => _latest;

  final int main;
  final int sub;
  final int patch;

  OpenCoreVersion(this.main, this.sub, this.patch) : _latest = false;
  OpenCoreVersion.from(String version) : main = int.tryParse(version.split(".")[0]) ?? 0, sub = int.tryParse(version.split(".")[1]) ?? 0, patch = int.tryParse(version.split(".")[2]) ?? 0, _latest = false;
  OpenCoreVersion.latest() : _latest = true, main = 0, sub = 0, patch = 0;

  bool operator <(OpenCoreVersion other) {
    if (latest) {
      if (other.latest) {
        return true;
      } else {
        return false;
      }
    } else if (other.latest) {
      return true;
    } else if (main == other.main) {
      if (sub == other.sub) {
        if (patch == other.patch) {
          return false;
        } else {
          return patch < other.patch;
        }
      } else {
        return sub < other.sub;
      }
    } else {
      return main < other.main;
    }
  }

  @override
  String toString() {
    return _latest ? "Latest" : "V. ${[main, sub, patch].join(".")}";
  }
}

class DevicePropertiesDevice {
  static String igpu = "PciRoot(0x0)/Pci(0x2,0x0)";
}

class UnsupportedBootArgConfiguration {
  UnsupportedBootArgConfigurationInput input;
  List<String> reason;
  UnsupportedBootArgConfiguration({required this.input, required this.reason});
}

class UnsupportedBootArgConfigurationInput {
  final String? _arg;
  final int? _char;

  UnsupportedBootArgConfigurationInputType get type => _arg != null ? UnsupportedBootArgConfigurationInputType.arg : (_char != null ? UnsupportedBootArgConfigurationInputType.char : UnsupportedBootArgConfigurationInputType.none);
  dynamic get input => _arg ?? _char;

  const UnsupportedBootArgConfigurationInput.argument(String arg) : _arg = arg, _char = null;
  const UnsupportedBootArgConfigurationInput.character(int char) : _arg = null, _char = char;
  const UnsupportedBootArgConfigurationInput.none() : _arg = null, _char = null;
}

enum UnsupportedBootArgConfigurationInputType {
  arg,
  char,
  none,
}

class OCLog {
  String raw;
  List<String> logs;
  late bool successful;

  OCLog({required this.raw, required List<String> input}) : logs = input.where((line) => line.replaceAll('\x00', '').replaceAll("\\00", "").trim().isNotEmpty).toList();

  void setSuccessful() {
    successful = logs.any((String input) => input.contains("EB|LOG:EXITBS:START"));
  }
}

class OCLogEntry {
  String entry;
  String type;
  String path;

  OCLogEntry({required this.entry, required this.type, required this.path});

  @override
  String toString() {
    return "$entry ($type)";
  }

  @override
  bool operator ==(Object other) {
    bool status = identical(this, other) || (other is OCLogEntry && entry == other.entry && type == other.type && path == other.path);
    if (status) verbose([Log("OCLogEntry == found")]);
    return status;
  }

  @override
  int get hashCode => entry.hashCode ^ type.hashCode ^ path.hashCode;
}

class OCLogKext {
  String name;
  String version;

  OCLogKext(this.name, this.version);

  @override
  String toString() {
    return "$name v$version";
  }
}

class OCLogTimestamp {
  int seconds;
  int milliseconds;

  OCLogTimestamp(this.seconds, this.milliseconds);

  OCLogTimestamp operator -(OCLogTimestamp other) {
    return OCLogTimestamp(seconds - other.seconds, milliseconds - other.milliseconds);
  }

  double toDouble() {
    return double.parse("$seconds.$milliseconds");
  }
}

class CpuId {
  final String fromid;
  final String toid;
  final List<int> cpuid;
  final List<int> cpumask;

  CpuId({required String from, required String to, required List<int> id, List<int>? mask}) : fromid = from, toid = to, cpuid = id, cpumask = mask ?? [0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
}

class CpuIdDatabase {
  List<CpuId> ids;
  CpuIdDatabase(this.ids);

  CpuId findById(List<int> id) {
    return ids.firstWhere((CpuId item) {
      List<int> cpu = item.cpuid;
      bool status = ListEquality().equals(id, cpu);
      verbose([Log("Comparing CPU: $id vs $cpu: $status")]);
      return status;
    });
  }
}