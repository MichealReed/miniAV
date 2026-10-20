import 'package:miniav_recorder/src/packet_pts_ledger.dart';
import 'package:test/test.dart';

void main() {
  group('PacketPtsLedger', () {
    test('a late packet gets its own frame\'s timestamp, not the latest', () {
      // An asynchronous encoder answering two calls late: the packet the
      // third call returns encodes the FIRST frame.
      final ledger = PacketPtsLedger()
        ..submitted(1000)
        ..submitted(34333)
        ..submitted(67666);
      expect(ledger.resolve(0, keyed: false), 1000);
      expect(ledger.resolve(1, keyed: false), 34333);
      expect(ledger.pending, 1);
    });

    test('keyed: frames the encoder never answered are skipped and counted',
        () {
      final ledger = PacketPtsLedger()
        ..submitted(1000)
        ..submitted(34333)
        ..submitted(67666);
      // The encoder refused 1000 under back-pressure; its next packet names
      // the frame it really encodes.
      expect(ledger.resolve(34333, keyed: true), 34333);
      expect(ledger.unanswered, 1);
      expect(ledger.resolve(67666, keyed: true), 67666);
      expect(ledger.pending, 0);
    });

    test('keyed: a packet naming nothing submitted falls back to order', () {
      final ledger = PacketPtsLedger()
        ..submitted(1000)
        ..submitted(34333);
      expect(ledger.resolve(999999, keyed: true), 1000);
      expect(ledger.unmatched, 1);
      expect(ledger.unanswered, 0);
    });

    test('nothing waiting resolves to null', () {
      expect(PacketPtsLedger().resolve(5, keyed: true), isNull);
      expect(PacketPtsLedger().resolve(5, keyed: false), isNull);
    });

    test('a failed submission is withdrawn, and only that one', () {
      final ledger = PacketPtsLedger()
        ..submitted(1000)
        ..submitted(34333);
      ledger.withdraw(1000); // not the last: some other frame's entry
      expect(ledger.pending, 2);
      ledger.withdraw(34333);
      expect(ledger.pending, 1);
      expect(ledger.resolve(0, keyed: false), 1000);
    });

    test('abandoning counts every frame still waiting', () {
      final ledger = PacketPtsLedger()
        ..submitted(1000)
        ..submitted(34333)
        ..submitted(67666);
      expect(ledger.resolve(1000, keyed: true), 1000);
      expect(ledger.abandon(), 2);
      expect(ledger.unanswered, 2);
      expect(ledger.pending, 0);
      expect(ledger.resolve(34333, keyed: true), isNull);
    });
  });
}
