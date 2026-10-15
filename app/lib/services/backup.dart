import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps a directory out of the phone's cloud backups.
///
/// iOS: sets "excluded from backup" through AppDelegate.swift, so iCloud and
/// computer backups skip it. Android needs nothing at run time: backups are
/// off in the manifest (`allowBackup="false"`, data_extraction_rules.xml).
abstract final class BackupExclusion {
  static const channel = MethodChannel('org.roadto/files');

  /// Creates [dir] if needed and excludes it. Never throws: a failure only
  /// means the directory may be backed up.
  static Future<void> exclude(Directory dir, {bool? isIOS}) async {
    if (!(isIOS ?? Platform.isIOS)) return;
    try {
      await dir.create(recursive: true);
      await channel.invokeMethod<void>('excludeFromBackup', {'path': dir.path});
    } on Exception catch (e) {
      debugPrint('Could not exclude ${dir.path} from backups: $e');
    }
  }
}
