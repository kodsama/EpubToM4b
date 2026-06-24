/// Small platform predicate shared by the entry point and the UI.
library;

import 'dart:io';

/// True on Android/iOS, where ffmpeg is bundled in-process and files live in
/// app-scoped storage (no native folder picker, share-sheet for output).
bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;
