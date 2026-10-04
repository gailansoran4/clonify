import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:clonify/commands/clonify_command_runner.dart';
import 'package:clonify/utils/command_process.dart';
import 'package:clonify/utils/file_tree_checkpoint.dart';

/// Classifies usage, operational failures, and cancellation after transactions
/// have had a chance to restore local files.
Future<void> main(List<String> arguments) async {
  final session = CommandSession();
  try {
    await session.run(() => ClonifyCommandRunner().run(arguments));
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  } on CommandCancelled catch (error) {
    stderr.writeln(error);
    exitCode = 130;
  } catch (error) {
    stderr.writeln(error);
    exitCode = session.cancelled || isCancellation(error) ? 130 : 1;
  }
}

bool isCancellation(Object error) =>
    error is CommandCancelled ||
    (error is ConfigureRolledBackException && isCancellation(error.cause));
