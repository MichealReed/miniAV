/// Cursor access through `Atomics`, and a `SharedArrayBuffer` to put the ring
/// in.
///
/// The ring is written by one thread and read by another (an `AudioWorklet`,
/// which is a genuine realtime audio thread), so the cursors need more than a
/// 32-bit store: they need ORDERING. `Atomics.store` is a release and
/// `Atomics.load` an acquire, which is what makes "the samples I wrote before
/// publishing the cursor are visible to whoever sees that cursor" true. A plain
/// `Int32List` store happens to be a single aligned write on every real CPU,
/// but it promises nothing about the sample writes around it — and the failure
/// it buys is a reader consuming samples that have not landed, which is
/// audible.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('Atomics.load')
external int _atomicsLoad(JSAny array, int index);

@JS('Atomics.store')
external int _atomicsStore(JSAny array, int index, int value);

/// Reads a cursor with acquire ordering.
int loadCursor(Int32List control, int index) =>
    _atomicsLoad(control.toJS, index);

/// Publishes a cursor with release ordering: every sample written before this
/// call is visible to a reader that observes the new value.
void storeCursor(Int32List control, int index, int value) =>
    _atomicsStore(control.toJS, index, value);

/// Whether cursor access is genuinely atomic here.
bool get hasAtomics => true;

/// True when this page can actually allocate a `SharedArrayBuffer`.
///
/// Asked by CONSTRUCTING one rather than by reading `crossOriginIsolated`.
/// Cross-origin isolation is the usual reason the constructor works, but it is
/// a proxy for the real question and it is not the only answer: a browser can
/// expose shared memory under a flag or an enterprise policy with
/// `crossOriginIsolated` still false, and on such a page the proxy says no
/// while the thing plainly works. The constructor cannot be wrong about
/// itself.
bool get canShareMemory {
  if (!globalContext.has('SharedArrayBuffer')) return false;
  try {
    globalContext
        .getProperty<JSFunction>('SharedArrayBuffer'.toJS)
        .callAsConstructor<JSObject>(8.toJS);
    return true;
  } on Object {
    // Present but blocked — an unisolated page in a browser that keeps the
    // constructor visible and throws on use.
    return false;
  }
}

/// Allocates the ring's backing store as shared memory when the page allows it,
/// and an ordinary buffer when it does not.
///
/// Falling back rather than throwing keeps a non-isolated page playing audio;
/// it just plays it from the main thread, which is what it did before any of
/// this existed.
ByteBuffer allocateRingBuffer(int lengthBytes) {
  if (!canShareMemory) return Uint8List(lengthBytes).buffer;
  final shared = globalContext
      .getProperty<JSFunction>('SharedArrayBuffer'.toJS)
      .callAsConstructor<JSObject>(lengthBytes.toJS);
  // dart2js represents `Uint8List` AS the JS `Uint8Array`, so viewing the
  // shared buffer and handing it to Dart is the same memory, not a copy.
  final view = globalContext
      .getProperty<JSFunction>('Uint8Array'.toJS)
      .callAsConstructor<JSUint8Array>(shared);
  return view.toDart.buffer;
}

/// The underlying `SharedArrayBuffer`, to hand to a worker.
///
/// A `SharedArrayBuffer` is SHARED by structured clone, never transferred —
/// putting one in a transfer list is a `DataCloneError`. Both sides end up
/// pointing at the same memory, which is the entire point.
Object shareableBuffer(ByteBuffer buffer) =>
    Uint8List.view(buffer).toJS.getProperty<JSObject>('buffer'.toJS);

/// Inverse of [shareableBuffer]: rebuilds a Dart view over memory that arrived
/// from another thread.
///
/// Accepts a `ByteBuffer` too, so a non-isolated page — where the ring is
/// ordinary memory and never left this thread — takes the same path.
ByteBuffer bufferFromShareable(Object shareable) {
  if (shareable is ByteBuffer) return shareable;
  final view = globalContext
      .getProperty<JSFunction>('Uint8Array'.toJS)
      .callAsConstructor<JSUint8Array>(shareable as JSObject);
  return view.toDart.buffer;
}

/// Whether [buffer] is backed by a `SharedArrayBuffer` rather than an ordinary
/// one.
///
/// Worth asking rather than assuming: [allocateRingBuffer] falls back to
/// ordinary memory on a page that is not cross-origin isolated, and a ring in
/// ordinary memory works perfectly within one thread while silently delivering
/// nothing across two. A consumer on another thread must check this before
/// trusting the ring.
bool isSharedBuffer(ByteBuffer buffer) {
  final js = Uint8List.view(buffer).toJS.getProperty<JSObject?>('buffer'.toJS);
  final ctor = js?.getProperty<JSObject?>('constructor'.toJS);
  return ctor?.getProperty<JSString?>('name'.toJS)?.toDart ==
      'SharedArrayBuffer';
}
