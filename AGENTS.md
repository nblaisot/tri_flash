# Repository Instructions

## Android device installation

- Always install or update an APK with `adb install -r` (and the appropriate
  `-s <device-id>` selector when needed) so the existing application and its
  data are preserved.
- Never use `flutter install`, `adb uninstall`, or any installation workflow
  that uninstalls the existing app first.
- If `adb install -r` fails, stop and report the error. Do not uninstall the
  installed app or clear its data as a workaround unless the user explicitly
  authorizes that destructive action.
