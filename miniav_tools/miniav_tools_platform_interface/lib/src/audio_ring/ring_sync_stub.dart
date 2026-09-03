/// Plain (non-atomic) cursor access, for platforms with no `Atomics`.
///
/// Correct wherever the ring is not actually shared between threads: the VM
/// tests, and any native host that uses the ring as a plain queue. A real
/// cross-thread ring on the VM would need its own primitives; this file exists
/// so the ring's LOGIC can be tested off-browser, not to make it thread-safe
/// here.
library;

import 'dart:typed_data';

/// Reads a cursor.
int loadCursor(Int32List control, int index) => control[index];

/// Publishes a cursor. On web this carries release ordering; see the web
/// implementation for why that matters.
void storeCursor(Int32List control, int index, int value) =>
    control[index] = value;

/// Whether cursor access is genuinely atomic here.
bool get hasAtomics => false;

/// Reads a `uint32` cursor.
///
/// Separate from [loadCursor] because the ring miniAV's capture MIRROR uses
/// declares its cursors `uint32` in C, and a `Uint32List` is what reads them
/// back without a sign fold at 2^31.
int loadCursorU32(Uint32List control, int index) => control[index];

/// Allocates the ring's backing store.
///
/// Off-web there is no `SharedArrayBuffer`, so this is an ordinary buffer.
ByteBuffer allocateRingBuffer(int lengthBytes) =>
    Uint8List(lengthBytes).buffer;

/// The backing store as something a worker can be handed.
///
/// Off-web that is the buffer itself: there is no separate shared-memory
/// object, and handing it back keeps [bufferFromShareable] symmetric so the
/// ring's own tests exercise the same round trip the browser does.
Object shareableBuffer(ByteBuffer buffer) => buffer;

/// Inverse of [shareableBuffer].
ByteBuffer bufferFromShareable(Object shareable) => shareable as ByteBuffer;

/// Whether [buffer] is memory two threads can genuinely share. Never, off-web.
bool isSharedBuffer(ByteBuffer buffer) => false;
