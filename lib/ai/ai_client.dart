export 'ai_client_stub.dart'
    if (dart.library.io) 'ai_client_io.dart'
    if (dart.library.html) 'ai_client_web.dart'
    if (dart.library.js_interop) 'ai_client_web.dart';
