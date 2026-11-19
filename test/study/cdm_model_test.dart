import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isconl/study/cdm/cdm_model.dart';

/// BI26092620: the deck document model as the phone parses it.
CdmDoc fixture() => CdmDoc.fromJsonString(File('test/fixtures/cdm_v3_module.json').readAsStringSync());

void main() {
  test('the v3 fixture parses and every kind in it is one this build knows', () {
    final doc = fixture();
    expect(doc.headline, 'Reading a cash-flow table');
    expect(doc.subtitle, 'Money in, money out');
    expect(doc.meta['course'], 'finance-basics');
    final kinds = doc.allNodes.map((n) => n.type).toSet();
    expect(kinds, cdmKnownKinds, reason: 'the fixture must cover every block kind, and only those');
    expect(doc.allNodes.every((n) => n.known), isTrue);
  });

  test('all twelve v3 callout labels are in the fixture', () {
    final kinds = fixture().allNodes.where((n) => n.type == 'callout').map((n) => n.calloutKind).toSet();
    expect(kinds, cdmCalloutKinds);
    expect(cdmCalloutKinds, hasLength(12));
  });

  test('block ids are stable positions, unique, and nested under their section', () {
    final a = fixture().allNodes.map((n) => n.id).toList();
    final b = fixture().allNodes.map((n) => n.id).toList();
    expect(a, b);
    expect(a.toSet(), hasLength(a.length));
    final quiz = fixture().sections.firstWhere((n) => n.type == 'section');
    expect(quiz.children.first.id, startsWith('${quiz.id}.'));
  });

  test('an id or block_id on a node wins over its position', () {
    final doc = CdmDoc.fromJson({
      'sections': [
        {'type': 'paragraph', 'text': 'a', 'id': 'blk-7'},
        {'type': 'paragraph', 'text': 'b', 'block_id': 'blk-8'},
        {'type': 'paragraph', 'text': 'c'},
      ]
    });
    expect(doc.sections.map((n) => n.id), ['blk-7', 'blk-8', 'b2']);
  });

  test('the older cdm key is accepted for the version, as deck does', () {
    expect(CdmDoc.fromJson({'cdm': '1', 'headline': 'x', 'sections': []}).ddm, '1');
    expect(CdmDoc.fromJson({'headline': 'x', 'sections': []}).ddm, '1');
  });

  test('an unknown kind and malformed fields degrade, never throw', () {
    final doc = CdmDoc.fromJson({
      'headline': 'x',
      'sections': [
        {'type': 'hologram', 'text': 'future'},
        {'type': 'bullets', 'items': 'not a list'},
        {'type': 'callout', 'kind': 'from_the_future', 'text': 't'},
        'not a map',
        {'no_type': true},
      ]
    });
    expect(doc.sections, hasLength(4));
    expect(doc.sections[0].known, isFalse);
    expect(doc.sections[1].strList('items'), isEmpty);
    expect(doc.sections[2].calloutKind, isNull);
    expect(doc.sections[3].known, isFalse);
  });

  test('something that is not a document is refused', () {
    expect(() => CdmDoc.fromJsonString('nope'), throwsFormatException);
    expect(() => CdmDoc.fromJsonString('[1,2]'), throwsFormatException);
  });
}
