import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/app_scope.dart';
import 'package:isconl/theme.dart';
import 'package:isconl/ui/views/practice_leads.dart';

import 'support/test_services.dart';

/// BI26092652: Leads on the phone, against fixtures in the shape hub's /api/practice/leads returns.
Map<String, dynamic> lead(String kind, String id, String name, String practice, String at, {String status = 'new', String summary = '', String slotAt = '', String proposalUrl = ''}) =>
    {'key': '$kind:$id', 'id': id, 'kind': kind, 'practice': practice, 'name': name, 'at': at, 'status': status, 'summary': summary, 'slotAt': slotAt, 'proposalUrl': proposalUrl};

final fixture = {
  'ok': true,
  'practices': ['content', 'systems'],
  'leads': [
    lead('booking', 'B2', 'Eli', 'content', '2026-10-14T11:00:00.000Z', status: 'proposal', slotAt: '2026-10-14T11:00:00.000Z'),
    lead('enquiry', 'E2', 'Brian', 'content', '2026-10-08T12:00:00.000Z', summary: 'Course help'),
    lead('booking', 'B1', 'Dee', 'systems', '2026-10-07T10:00:00.000Z', status: 'won', proposalUrl: 'https://deck/p1', summary: 'A portal / March'),
  ],
  'funnel': {'total': {'enquiries': 1, 'bookings': 2, 'proposals': 2, 'won': 1, 'lost': 0}, 'practices': {}},
  'sources': {
    'enquiries': {'state': 'ok', 'pending': 'BS26092502'},
    'bookings': {'state': 'not-connected', 'pending': 'BS26092604'},
  },
};

void main() {
  test('the source note names what is missing and what it waits on, and is silent when all is connected', () {
    expect(leadsSourceNote({'enquiries': {'state': 'not-connected', 'pending': 'BS26092502'}, 'bookings': {'state': 'not-connected', 'pending': 'BS26092604'}}),
        'Enquiries: not connected yet (BS26092502) · Bookings: not connected yet (BS26092604). What is connected shows below.');
    expect(leadsSourceNote({'enquiries': {'state': 'ok'}, 'bookings': {'state': 'error', 'error': 'x'}}), 'Bookings: could not be read. What is connected shows below.');
    expect(leadsSourceNote({'enquiries': {'state': 'ok'}, 'bookings': {'state': 'ok'}}), isNull);
  });

  test('relative days', () {
    final now = DateTime.utc(2026, 10, 9, 12);
    expect(leadAgo('2026-10-09T01:00:00Z', now), 'today');
    expect(leadAgo('2026-10-08T01:00:00Z', now), 'yesterday');
    expect(leadAgo('2026-10-04T12:00:00Z', now), '5 days ago');
    expect(leadAgo('', now), '');
  });

  testWidgets('Leads shows the funnel, the merged list in order, the missing source, and wires the actions', (tester) async {
    final api = ScriptedApi({'/api/practice/leads': fixture});
    final services = (await tester.runAsync(() => buildTestServices(api)))!;
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: SingleChildScrollView(child: PracticeLeads()))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('leads-note')), findsOneWidget);
    expect(find.textContaining('Bookings: not connected yet (BS26092604)'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('funnel-bookings'))).data, '2');
    expect(tester.widget<Text>(find.byKey(const Key('funnel-won'))).data, '1');
    final ys = [for (final n in ['Eli', 'Brian', 'Dee']) tester.getTopLeft(find.text(n)).dy];
    expect(ys, [...ys]..sort(), reason: 'newest first');
    // A lead that already has a proposal has no Proposal button; a closed one has no Won/Lost.
    expect(find.byKey(const Key('convert-enquiry:E2')), findsOneWidget);
    expect(find.byKey(const Key('convert-booking:B1')), findsNothing);
    expect(find.byKey(const Key('won-booking:B1')), findsNothing);
    expect(find.byKey(const Key('won-enquiry:E2')), findsOneWidget);
    expect(find.text('Course help'), findsOneWidget);
    // Choosing a practice asks for just that practice.
    await tester.tap(find.text('systems'));
    await tester.pumpAndSettle();
    expect(api.asked.last, '/api/practice/leads?practice=systems');
  });
}
