import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/chat_toc.dart';

void main() {
  ambiguity();
  test('chapter numbers from roman, arabic and prefixed labels', () {
    expect(chatChapterNumber('III: Of Providence'), 3);
    expect(chatChapterNumber('XXIX.'), 29);
    expect(chatChapterNumber('Chapter 7'), 7);
    expect(chatChapterNumber('BAB 12 Penutup'), 12);
    expect(chatChapterNumber('Book IV'), 4);
    expect(chatChapterNumber('THE FIRST BOOK'), isNull);
    expect(chatChapterNumber('Introduction'), isNull);
    expect(chatChapterNumber('In the garden'), isNull); // "In" is not roman
    expect(chatChapterNumber('IIII'), isNull);
  });

  test('toc data keeps original ids, sections and sizes', () {
    final data = chatTocData([
      (id: 5, title: 'Imprint', section: '', chars: 100),
      (
        id: 9,
        title: 'III: Of Providence',
        section: 'Discourses › Book I',
        chars: 1757,
      ),
    ]);
    expect(data, [
      {'id': 5, 'title': 'Imprint', 'chars': 100},
      {
        'id': 9,
        'section': 'Discourses › Book I',
        'title': 'III: Of Providence',
        'number': 3,
        'chars': 1757,
      },
    ]);
    expect(
      chatChapterLabel((
        id: 9,
        title: 'III: Of Providence',
        section: 'Discourses › Book I',
        chars: 1,
      )),
      'Book I › III: Of Providence',
    );
    expect(
      chatChapterLabel((id: 5, title: 'Imprint', section: null, chars: 1)),
      'Imprint',
    );
  });

  test('model chapter ids are validated against the toc', () {
    expect(chatChapterIds(null, [1, 2]), isEmpty);
    expect(chatChapterIds([2, 1], [1, 2]), [2, 1]);
    expect(chatChapterIds(['2', ' 1'], [1, 2]), [2, 1]); // numeric strings
    expect(() => chatChapterIds([3], [1, 2]), throwsFormatException);
    expect(() => chatChapterIds([1, 1], [1, 2]), throwsFormatException);
    expect(() => chatChapterIds(['one'], [1, 2]), throwsFormatException);
    expect(() => chatChapterIds([1, 2], [1, 2], max: 1), throwsFormatException);
  });
}

void ambiguity() {
  const toc = <ChatChapterInfo>[
    (id: 1, title: 'Introduction', section: '', chars: 10),
    (
      id: 2,
      title: 'III: Of Providence',
      section: 'Discourses › Book I',
      chars: 10,
    ),
    (
      id: 3,
      title: 'III: On Tranquillity',
      section: 'Discourses › Book II',
      chars: 10,
    ),
    (
      id: 4,
      title: 'IV: Of Progress',
      section: 'Discourses › Book I',
      chars: 10,
    ),
  ];
  test('bare chapter numbers shared across books need a clarification', () {
    expect(chatAmbiguousSections('bab III bahas apa?', [2], toc), [
      'Book I',
      'Book II',
    ]);
    expect(chatAmbiguousSections('chapter 3 intinya apa', [3], toc), [
      'Book I',
      'Book II',
    ]);
    expect(chatAmbiguousSections('bab 4 bahas apa', [4], toc), isEmpty);
    expect(
      chatAmbiguousSections('Book II bab III bahas apa', [3], toc),
      isEmpty,
    );
    expect(
      chatAmbiguousSections('bab III bahas apa', [2], toc, readingChapterId: 4),
      isEmpty,
    );
    expect(
      chatAmbiguousSections('bab III bahas apa', [3], toc, readingChapterId: 4),
      ['Book I', 'Book II'],
    );
    expect(chatAmbiguousSections('apa gagasan utamanya', [2], toc), isEmpty);
    expect(chatAmbiguousSections('bab III', [2, 3], toc), [
      'Book I',
      'Book II',
    ]);
    expect(chatAmbiguousSections('bab III', [], toc), isEmpty);
  });
}
