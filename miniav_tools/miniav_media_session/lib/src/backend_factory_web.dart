import 'backend.dart';
import 'backend_web.dart';

/// Browsers. [appName] and [hostWindowHandle] are unused: the browser owns the
/// session identity (it is the tab) and there is no window handle to adopt.
MediaSessionBackend createMediaSessionBackend({
  required String appName,
  int? hostWindowHandle,
}) => WebMediaSessionBackend();
