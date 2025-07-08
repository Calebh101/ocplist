import 'dart:convert';

import 'package:ocplist/src/classes.dart';
import 'package:ocplist/src/logger.dart';
import 'package:ocplist/src/plist/main.dart';

List<UnsupportedConfiguration> findUnsupportedConfigurations(String raw, Map plist) {
  List<UnsupportedConfiguration> results = [];

  try {
    List<String> keys = ocKeys;
    List<String> cloverKeys = ["ACPI", "Boot", "BootGraphics", "CPU", "Devices", "DisableDrivers?", "GUI", "Graphics", "KernelAndKextPatches", "Quirks", "RtVariables", "SMBIOS", "SMBIOS_capitan", "SMBIOS_ventura", "SystemParameters"];
    List<String> presentKeys = [];

    for (String key in keys) {
      if (plist.containsKey(key)) {
        presentKeys.add(key);
      }
    }

    double threshold = 0.9;
    double match = presentKeys.length / keys.length;

    if (match < threshold) {
      bool clover = false;
      List<String> cloverKeysPresent = [];

      for (String key in cloverKeys) {
        if (plist.containsKey(key)) {
          cloverKeysPresent.add(key);
        }
      }

      double matchClover = cloverKeysPresent.length / cloverKeys.length;
      if (matchClover > threshold) clover = true;

      results.add(UnsupportedConfiguration(status: clover ? UnsupportedConfigurationStatus.error : UnsupportedConfigurationStatus.warning, type: clover ? UnsupportedConfigurationType.TopLevelClover : UnsupportedConfigurationType.TopLevel, reason: [[Log("Present top level OpenCore keys: "), Log("${(match * 100).round()}% match", effects: [1]), Log(" (below threshold of ${(threshold * 100)}%): ${presentKeys.join(", ")}")], if (clover) [Log("Present top level Clover keys: "), Log("${(matchClover * 100).round()}% match", effects: [1]), Log(" (above threshold of ${(threshold * 100)}%): ${cloverKeysPresent.join(", ")}")]]));
    }
  } catch (e) {
    verboseerror("unsupportedconfiguration.bootloader.toplevel", [Log(e)]);
  }

  try {
    int threshold = 3;
    int matches = 0;
    Map boot = plist["Misc"]["Boot"];
    dynamic prevlang = plist["NVRAM"]["Add"]["7C436110-AB2A-4BBB-A880-FE41995C9F82"]["prev-lang:kbd"];

    bool pickerMode = boot["PickerMode"] == "External";
    bool timeout = boot["Timeout"] == 10;
    bool target = plist["Misc"]["Debug"]["Target"] == 0;
    bool language = (prevlang is List<int> ? utf8.decode(prevlang) : prevlang) == "en:252";
    List<RegExpMatch> efiupdater = RegExp("<string>run-efi-updater</string>").allMatches(raw).toList();

    for (bool item in [pickerMode, timeout, target, language]) {
      if (item == true) {
        matches++;
      }
    }

    if (matches >= threshold || efiupdater.isNotEmpty) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.OpcoreSimplify, reason: [[Log("Matches: $matches (threshold: $threshold)")], [Log("PickerMode match: $pickerMode")], [Log("Timeout match: $timeout")], [Log("Target match: $target")], [Log("prev-lang:kbd match: $language")], [Log("run-efi-updater matches: ${efiupdater.length}")]]));
    }
  } catch (e) {
    verboseerror("unsupportedconfiguration.prebuilt.autotool", [Log(e)]);
  }

  try {
    RegExp regexA = RegExp(r'oc-efi-maker', multiLine: true, caseSensitive: false);
    Iterable matchesA = regexA.allMatches(raw);

    RegExp regexB = RegExp(r'^[ \t]*<data>\n[ \t]*(.+)\n[ \t]*<\/data>$', multiLine: true, caseSensitive: false);
    Iterable matchesB = regexB.allMatches(raw);
    int thresholdB = 6;

    if (matchesA.isNotEmpty || matchesB.length >= thresholdB) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.OCEfiMaker, reason: [[Log("Matches to "), Log(regexA.pattern, effects: [1]), Log(": "), Log("${matchesA.length}", effects: [1]), Log( " (threshold of "), Log(1, effects: [1]), Log(")")], [Log("Matches to "), Log(regexB.pattern, effects: [1]), Log(": "), Log("${matchesB.length}", effects: [1]), Log(" (threshold of "), Log(thresholdB, effects: [1]), Log(")")]]));
    }
  } catch (e) {
    verboseerror("unsupportedconfiguration.prebuilt.autotool", [Log(e)]);
  }

  try {
    RegExp regex = RegExp(r'MaLd0n|olarila', multiLine: true, caseSensitive: false);
    Iterable matches = regex.allMatches(raw);

    if (matches.isNotEmpty) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.Olarila, reason: [[Log("Matches to "), Log(regex.pattern, effects: [1]), Log(": "), Log("${matches.length}", effects: [1])]]));
    }
  } catch (e) {
    verboseerror("unsupportedconfiguration.prebuilt.olarila", [Log(e)]);
  }

  try {
    RegExp regex = RegExp(r'^([Vv]\d+\.\d+(\.\d+)?(\s*\|\s*.+)?).*'); // Taken from CorpNewt's CorpBot.py $plist command
    int matches = 0;

    for (dynamic item in plist["Kernel"]["Add"]) {
      if (item is! Map) continue;
      dynamic comment = item["Comment"];
      bool status = comment is String && regex.hasMatch(comment);

      if (status) {
        matches++;
      }
    }

    if (matches > 0) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.GeneralConfigurator, reason: [[Log("Matches to "), Log(regex.pattern, effects: [1]), Log(": "), Log("$matches", effects: [1])]]));
    }
  } catch (e) {
    verboseerror("unsupportedconfiguration.configurators", [Log(e)]);
  }

  try {
    double slotNameThreshold = 0.6;
    List properties = getDevProps(plist);

    int slotNameCount = properties.where((item) {
      return item["value"]["AAPL,slot-name"] != null;
    }).length;

    double chance = slotNameCount / properties.length;
    bool match = chance > slotNameThreshold;
    verbose([Log("Hackintool results: $slotNameCount / ${properties.length} ($match)")]);

    if (match) {
      results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.Hackintool, status: UnsupportedConfigurationStatus.warning, reason: [[Log("Hackintool properties found: "), Log("${(chance * 100).round()}%", effects: [1]), Log(" (above threshold of "), Log("${(slotNameThreshold * 100)}%", effects: [1]), Log(")")]]));
    }
  } catch (e) {
    verboseerror("unsupportedconfiguration.hackintool", [Log(e)]);
  }

  try {
    OpenCoreVersion threshold = OpenCoreVersion(1, 0, 2);
    OpenCoreVersion max = OpenCoreVersion.latest();

    void check(OpenCoreVersion version, List<String> keys) {
      if (plist * keys == null) {
        max = version;
      }
    }

    check(OpenCoreVersion(1, 0, 4), ["Booter", "Quirks", "ClearTaskSwitchBit"]);
    check(OpenCoreVersion(1, 0, 1), ["UEFI", "Unload"]);
    check(OpenCoreVersion(0, 9, 6), ["Booter", "Quirks", "FixupAppleEfiImages"]);
    check(OpenCoreVersion(0, 8, 9), ["UEFI", "Quirks", "ResizeUsePciRbIo"]);
    check(OpenCoreVersion(0, 7, 0), ["Kernel", "Quirks", "ProvideCurrentCpuInfo"]);
    check(OpenCoreVersion(0, 5, 4), ["Booter", "Quirks", "SignalAppleOS"]);

    verbose([Log("Maximum OpenCore version: $max")]);
    if (max < threshold) results.add(UnsupportedConfiguration(type: UnsupportedConfigurationType.OldSchema, reason: [[Log("Maximum OpenCore schema version: "), Log("$max", effects: [1])]], status: UnsupportedConfigurationStatus.warning));
  } catch (e) {
    verboseerror("unsupportedconfiguration.bootloader.schema", [Log(e)]);
  }

  return results;
}