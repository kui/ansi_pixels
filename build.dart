import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import 'package:polymer/builder.dart';

main(args) {
  build(entryPoints: entryPoints, options: parseOptions(args));
}

String get projectDir => path.dirname(Platform.script.toFilePath());
String get pubspecFile => path.join(projectDir, 'pubspec.yaml');
YamlMap get pubspec {
  final f = pubspecFile;
  return loadYaml(new File(f).readAsStringSync(), sourceName: f);
}
List<String> get entryPoints {
  final YamlMap polymer = pubspec['transformers']
      .where((e) => e is YamlMap)
      .firstWhere((YamlMap m) => m.containsKey('polymer'))['polymer'];
  return polymer['entry_points'].toList(growable: false);
}
