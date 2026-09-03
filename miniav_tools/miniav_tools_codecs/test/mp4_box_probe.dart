/// Test-only ISO-BMFF box probe.
///
/// The muxer tests need to assert on the CONTAINER, not just on what the
/// demuxer makes of it: "there is no stss box" and "mvhd is version 1" are
/// claims about bytes, and a demuxer that happens to tolerate the wrong bytes
/// would hide exactly the bugs these tests exist to catch.
library;

import 'dart:typed_data';

class Mp4Box {
  Mp4Box(this.type, this.payloadStart, this.payloadEnd);
  final String type;
  final int payloadStart;
  final int payloadEnd;
}

/// Walk the boxes between [start] and [end].
List<Mp4Box> boxesIn(Uint8List b, int start, int end) {
  final d = ByteData.sublistView(b);
  final out = <Mp4Box>[];
  var pos = start;
  while (pos + 8 <= end) {
    var size = d.getUint32(pos, Endian.big);
    final type = String.fromCharCodes(b.sublist(pos + 4, pos + 8));
    var header = 8;
    if (size == 1) {
      if (pos + 16 > end) break;
      size = (d.getUint32(pos + 8, Endian.big) << 32) |
          d.getUint32(pos + 12, Endian.big);
      header = 16;
    } else if (size == 0) {
      size = end - pos;
    }
    if (size < header || pos + size > end) break;
    out.add(Mp4Box(type, pos + header, pos + size));
    pos += size;
  }
  return out;
}

/// Resolve a fourcc path (e.g. `['moov', 'trak', 'mdia', 'mdhd']`), returning
/// the [index]-th match at the final level, or null.
Mp4Box? findBox(Uint8List b, List<String> path, {int index = 0}) {
  var start = 0, end = b.length;
  for (var level = 0; level < path.length; level++) {
    final want = path[level];
    final matches = [for (final x in boxesIn(b, start, end)) if (x.type == want) x];
    final wanted = level == path.length - 1 ? index : 0;
    if (matches.length <= wanted) return null;
    final hit = matches[wanted];
    start = hit.payloadStart;
    end = hit.payloadEnd;
    if (level == path.length - 1) return hit;
  }
  return null;
}

/// All boxes with [type] anywhere in the tree (depth-first).
List<Mp4Box> findAll(Uint8List b, String type, {int? start, int? end}) {
  final out = <Mp4Box>[];
  void walk(int s, int e) {
    for (final box in boxesIn(b, s, e)) {
      if (box.type == type) out.add(box);
      // Only recurse into container boxes — descending into mdat or a sample
      // table would read media bytes as if they were box headers.
      if (const {
        'moov', 'trak', 'mdia', 'minf', 'stbl', 'edts', 'dinf', 'udta' //
      }.contains(box.type)) {
        walk(box.payloadStart, box.payloadEnd);
      }
    }
  }

  walk(start ?? 0, end ?? b.length);
  return out;
}

/// `version` byte of a FullBox payload.
int fullBoxVersion(Uint8List b, Mp4Box box) => b[box.payloadStart];
