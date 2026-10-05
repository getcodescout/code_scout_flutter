/// The version of this package, as a value the code can read.
///
/// Dart gives a package no way to read its own pubspec at runtime, so this is a
/// constant that has to be bumped alongside `version:` in pubspec.yaml. A test
/// reads the pubspec and fails when the two drift, which is the only thing
/// standing between this and a number that quietly stops being true.
///
/// It is sent with every session so the dashboard can show which SDK an app is
/// running. That is the whole point: "is this app old enough to be missing the
/// fix?" is currently a question nobody can answer without asking the developer.
const String codeScoutSdkVersion = '1.6.0';
