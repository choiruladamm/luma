import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/grouping.dart';
import 'package:luma/domain/models/book.dart';

RawParagraph p(int chars) => (type: ParagraphType.paragraph, text: 'x' * chars);
const RawParagraph heading = (type: ParagraphType.heading, text: 'Chapter I');
const RawParagraph sceneBreak = (type: ParagraphType.sceneBreak, text: '***');

void main() {
  test('empty chapter', () => expect(assignGroups([]), isEmpty));

  test('short paragraphs merge until targetChars', () {
    // 200 + 200 = 400 stays open; + 100 = 500 ≥ 450 closes it.
    expect(assignGroups([p(200), p(200), p(100), p(10)]), [0, 0, 0, 1]);
  });

  test('short dialogue lines: maxParagraphs closes the group first', () {
    // 6 × 60 = 360, still under targetChars, but 6 lines is the cap.
    expect(assignGroups(List.filled(9, p(60))), [0, 0, 0, 0, 0, 0, 1, 1, 1]);
  });

  test('a long paragraph is a group on its own', () {
    expect(assignGroups([p(100), p(GroupRules.longThreshold), p(100)]), [
      0,
      1,
      2,
    ]);
  });

  test('targetChars closes a group, so it never nears maxChars', () {
    // 299 + 299 = 598 ≥ 450 closes; then 200 + 299 = 499 closes again.
    expect(assignGroups([p(299), p(299), p(200), p(299)]), [0, 0, 1, 1]);
    // An open group is < targetChars and a short paragraph is
    // < longThreshold, so a group tops out below maxChars. maxChars only
    // bites if the rules are retuned.
    expect(
      GroupRules.targetChars - 1 + GroupRules.longThreshold - 1,
      lessThan(GroupRules.maxChars),
    );
  });

  test('headings and scene breaks break groups and get no index', () {
    expect(assignGroups([heading, p(50), p(50), sceneBreak, p(50), heading]), [
      null,
      0,
      0,
      null,
      1,
      null,
    ]);
  });

  test('mixed chapter: indexes start at 0 and never skip', () {
    final groups = assignGroups([
      heading,
      p(40),
      p(40),
      p(500),
      p(40),
      sceneBreak,
      p(120),
      p(120),
      p(120),
      p(120),
    ]);
    expect(groups, [null, 0, 0, 1, 2, null, 3, 3, 3, 3]);
  });
}
