import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/services/mpesa.dart';

/// This parser writes into a money ledger, so it is tested against real M-Pesa
/// message shapes rather than trusted. The rule under test throughout: nothing is
/// guessed. A shape the parser does not know returns null and gets reported,
/// because a wrong amount in the ledger is invisible and compounds, while a
/// message filed by hand costs a minute.
void main() {
  group('received', () {
    test('from a person, with a phone number', () {
      final e = parseMpesa(
          'TG83H5K2LM Confirmed. You have received Ksh1,000.00 from JOHN DOE 0712345678 '
          'on 3/8/26 at 10:15 AM New M-PESA balance is Ksh2,345.67.');
      expect(e, isNotNull);
      expect(e!.kind, MpesaKind.received);
      expect(e.amount, 1000.00);
      expect(e.code, 'TG83H5K2LM');
      expect(e.counterparty, 'JOHN DOE');
      expect(e.phone, '0712345678');
      expect(e.balance, 2345.67);
      expect(e.isInflow, isTrue);
      expect(e.isOutflow, isFalse);
      expect(e.at, DateTime(2026, 8, 3, 10, 15));
    });

    test('from a business, no phone number', () {
      final e = parseMpesa(
          'ABC1234567 Confirmed. You have received Ksh40,000.00 from WABBA GLOBAL '
          'on 5/8/26 at 9:00 AM New M-PESA balance is Ksh40,012.30.');
      expect(e!.kind, MpesaKind.received);
      expect(e.amount, 40000.00);
      expect(e.counterparty, 'WABBA GLOBAL');
      expect(e.phone, isNull);
    });
  });

  group('outflows', () {
    test('sent to a person', () {
      final e = parseMpesa(
          'TG83H5K2LN Confirmed. Ksh500.00 sent to JANE DOE 0723456789 on 3/8/26 '
          'at 11:00 AM. New M-PESA balance is Ksh1,845.67. Transaction cost, Ksh7.00.');
      expect(e!.kind, MpesaKind.sent);
      expect(e.amount, 500.00);
      expect(e.counterparty, 'JANE DOE');
      // Cost is kept separate: folding it into the amount misstates both.
      expect(e.cost, 7.00);
      expect(e.isOutflow, isTrue);
    });

    test('paid to a till', () {
      final e = parseMpesa(
          'TG83H5K2LP Confirmed. You have paid Ksh250.00 to NAIVAS LTD. on 3/8/26 '
          'at 12:00 PM. New M-PESA balance is Ksh1,595.67. Transaction cost, Ksh0.00.');
      expect(e!.kind, MpesaKind.paid);
      expect(e.amount, 250.00);
      // The trailing full stop on the merchant name is trimmed.
      expect(e.counterparty, 'NAIVAS LTD');
      expect(e.cost, 0.00);
    });

    test('paybill carries the account number', () {
      final e = parseMpesa(
          'TG83H5K2LQ Confirmed. Ksh1,000.00 paid to KPLC PREPAID. on 3/8/26 at 1:00 PM '
          'for account 12345678. New M-PESA balance is Ksh595.67.');
      expect(e!.kind, MpesaKind.paid);
      expect(e.amount, 1000.00);
      expect(e.account, '12345678');
      expect(e.counterparty, contains('KPLC'));
    });

    test('withdraw at an agent', () {
      final e = parseMpesa(
          'TG83H5K2LR Confirmed.on 3/8/26 at 1:30 PM Withdraw Ksh1,000.00 from '
          '123456 - MAMA MBOGA AGENT New M-PESA balance is Ksh595.67.');
      expect(e!.kind, MpesaKind.withdraw);
      expect(e.amount, 1000.00);
      expect(e.isOutflow, isTrue);
    });

    test('airtime is a utility', () {
      final e = parseMpesa(
          'TG83H5K2LS confirmed.You bought Ksh100.00 of airtime on 3/8/26 at 2:00 PM. '
          'New M-PESA balance is Ksh495.67.');
      expect(e!.kind, MpesaKind.airtime);
      expect(e.amount, 100.00);
      expect(e.suggestedTier, 'utilities');
    });
  });

  group('amounts and dates', () {
    test('thousands separators and decimals survive', () {
      final e = parseMpesa(
          'AAA1111111 Confirmed. You have received Ksh1,234,567.89 from X LTD on 1/1/27 at 8:00 AM '
          'New M-PESA balance is Ksh1,234,567.89.');
      expect(e!.amount, 1234567.89);
    });

    test('a whole-shilling amount with no decimals parses', () {
      final e = parseMpesa(
          'AAA1111112 Confirmed. Ksh50 sent to Z 0700000000 on 1/1/27 at 8:00 AM. '
          'New M-PESA balance is Ksh10.');
      expect(e!.amount, 50);
    });

    test('PM and AM map to the right hour, and noon and midnight do not invert', () {
      DateTime? at(String t) => parseMpesa(
            'AAA1111113 Confirmed. You have received Ksh10.00 from X on 3/8/26 at $t '
            'New M-PESA balance is Ksh10.00.',
          )?.at;
      expect(at('12:30 AM'), DateTime(2026, 8, 3, 0, 30));
      expect(at('12:30 PM'), DateTime(2026, 8, 3, 12, 30));
      expect(at('1:05 PM'), DateTime(2026, 8, 3, 13, 5));
    });

    test('a four-digit year works as well as two', () {
      final e = parseMpesa(
          'AAA1111114 Confirmed. You have received Ksh10.00 from X on 3/8/2026 at 9:00 AM '
          'New M-PESA balance is Ksh10.00.');
      expect(e!.at, DateTime(2026, 8, 3, 9, 0));
    });
  });

  group('nothing is guessed', () {
    test('an ordinary SMS is not an M-Pesa event', () {
      expect(parseMpesa('Hey, are we still on for 3pm?'), isNull);
      expect(parseMpesa(''), isNull);
    });

    test('an M-Pesa-ish message in an unknown shape returns null, not a guess', () {
      // Mentions M-PESA and Ksh but matches no known shape. It must NOT become a
      // ledger row with an invented direction.
      expect(
        parseMpesa('M-PESA: your statement for Ksh0.00 is ready. Dial *334#.'),
        isNull,
      );
    });

    test('a promotional message with a shilling figure is not a transaction', () {
      expect(
        parseMpesa('Get a loan of up to Ksh50,000 today! Dial *234# now.'),
        isNull,
      );
    });
  });

  group('sender is checked, not just the body', () {
    SmsMessage msg(String sender, String body) => SmsMessage(
        sender: sender, body: body, receivedAt: DateTime(2026, 8, 3));

    const real = 'TG83H5K2LM Confirmed. You have received Ksh1,000.00 from JOHN DOE '
        '0712345678 on 3/8/26 at 10:15 AM New M-PESA balance is Ksh2,345.67.';

    test('MPESA and M-PESA both count', () {
      expect(msg('MPESA', real).looksLikeMpesa, isTrue);
      expect(msg('M-PESA', real).looksLikeMpesa, isTrue);
    });

    // The body alone is forgeable. A scam SMS copying the format, or a friend
    // forwarding a message, must not reach the ledger.
    test('a forged sender is rejected even with a perfect body', () {
      expect(msg('+254700000000', real).looksLikeMpesa, isFalse);
      expect(msg('MPESA-OFFERS', real).looksLikeMpesa, isFalse);
      final h = harvest([msg('+254700000000', real)]);
      expect(h.events, isEmpty);
      expect(h.unparsed, isEmpty, reason: 'not from M-Pesa, so not even a miss');
      expect(h.ignored, 1);
    });
  });

  group('harvest', () {
    SmsMessage m(String body, {String sender = 'MPESA', int ms = 0}) => SmsMessage(
        sender: sender, body: body,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(ms));

    test('the transaction code makes a re-read idempotent', () {
      const body = 'TG83H5K2LM Confirmed. You have received Ksh1,000.00 from JOHN DOE '
          '0712345678 on 3/8/26 at 10:15 AM New M-PESA balance is Ksh2,345.67.';
      // A backfill overlapping the live receiver reads the same SMS twice.
      final h = harvest([m(body, ms: 1), m(body, ms: 2)]);
      expect(h.events.length, 1);
      expect(h.scanned, 2);
    });

    test('unparsed messages are carried, never dropped', () {
      final h = harvest([
        m('M-PESA: something entirely new we have never seen with Ksh5.00 in it'),
      ]);
      expect(h.events, isEmpty);
      expect(h.unparsed.length, 1,
          reason: 'a parser that silently drops misses can never be improved');
    });

    test('a mixed batch splits cleanly', () {
      final h = harvest([
        m('TG1 Confirmed. You have received Ksh10.00 from A on 3/8/26 at 9:00 AM '
            'New M-PESA balance is Ksh10.00.'),
        m('Hi, lunch?', sender: '+254711111111'),
        m('M-PESA unknown shape Ksh1.00'),
      ]);
      expect(h.events.length, 1);
      expect(h.unparsed.length, 1);
      expect(h.ignored, 1);
      expect(h.scanned, 3);
    });
  });

  group('json', () {
    test('direction and amount sign never disagree', () {
      final e = parseMpesa(
          'TG1 Confirmed. Ksh500.00 sent to JANE 0700000000 on 3/8/26 at 9:00 AM. '
          'New M-PESA balance is Ksh10.00.')!;
      final j = e.toJson();
      expect(j['direction'], 'out');
      // Amount is always positive; direction is the only place sign lives.
      expect(j['amount'], 500.00);
    });
  });
}
