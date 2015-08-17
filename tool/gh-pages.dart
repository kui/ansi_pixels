#!/usr/bin/env dart
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:ghpages_generator/ghpages_generator.dart' as gh;

main() {
  new gh.Generator(rootDir: projectDir)
    ..withWeb = true
    ..withIndexGeneration = true
    ..generate(doCustomTask: (workDir) {
      gh.moveWebAtRoot(workDir);
    });
}

String get projectDir =>
    path.absolute(path.dirname(path.dirname(Platform.script.toFilePath())));
