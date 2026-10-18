/// Pairs encoded packets with the frames they encode. Pure bookkeeping — no
/// I/O — so it is unit-testable.
library;

/// Remembers the timestamp of every frame submitted to a video encoder until
/// the packet for that frame comes back, so the packet is written with its
/// own frame's timestamp.
///
/// An encode call returns a packet IF one happened to be ready, and from an
/// asynchronous hardware encoder that packet belongs to a frame submitted two
/// to four calls earlier. Stamping it with the timestamp of the call that
/// returned it shifts the whole video track two to four frames late against
/// the audio, and wherever that lag changes — an idle duplicate, a stall, the
/// flush at the end — a picture lands under another picture's time.
///
/// Two ways to pair them:
///
/// - **Keyed**: the encoder's packets carry the timestamp their frame was
///   submitted with (Media Foundation does). A packet takes the entry it
///   names; entries older than it were frames the encoder never answered —
///   it refused them under back-pressure — and are dropped and counted.
/// - **Order**: the encoder's packets carry something else (FFmpeg's carry the
///   submission index times the nominal frame duration). One packet comes
///   back per frame, in submission order, so a packet takes the oldest entry.
///
/// A keyed packet whose timestamp matches no entry falls back to order.
class PacketPtsLedger {
  final List<int> _pending = [];

  /// Frames an encoder never produced a packet for.
  int unanswered = 0;

  /// Keyed packets whose timestamp matched nothing submitted.
  int unmatched = 0;

  /// Frames submitted and not yet paired with a packet.
  int get pending => _pending.length;

  /// A frame stamped [ptsUs] is about to be submitted. Timestamps must be
  /// submitted in increasing order.
  void submitted(int ptsUs) => _pending.add(ptsUs);

  /// The submission of [ptsUs] failed: the encoder did not take the frame.
  void withdraw(int ptsUs) {
    if (_pending.isNotEmpty && _pending.last == ptsUs) _pending.removeLast();
  }

  /// The timestamp of the frame a packet stamped [packetPtsUs] encodes, or
  /// null when no submitted frame is waiting for one.
  int? resolve(int packetPtsUs, {required bool keyed}) {
    if (_pending.isEmpty) return null;
    if (keyed) {
      final i = _pending.indexOf(packetPtsUs);
      if (i >= 0) {
        unanswered += i;
        _pending.removeRange(0, i);
        return _pending.removeAt(0);
      }
      unmatched++;
    }
    return _pending.removeAt(0);
  }

  /// Forgets every waiting frame — the encoder was replaced or flushed and
  /// none of them will be answered now. Returns how many there were.
  int abandon() {
    final n = _pending.length;
    unanswered += n;
    _pending.clear();
    return n;
  }
}
