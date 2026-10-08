import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/sentences.dart';

void main() {
  test('splits on . ! ? followed by a capital', () {
    expect(splitSentences('Satu. Dua! Tiga? Empat'), [
      'Satu.',
      'Dua!',
      'Tiga?',
      'Empat',
    ]);
  });

  test('a closing quote stays with its sentence; dialog tags do not split', () {
    expect(
      splitSentences(
        '“Tapi teman-temanku tidak akan terbantu.” Apa maksudmu dengan '
        '“tidak terbantu”? “Apa?” tanyanya. Lalu diam.',
      ),
      [
        '“Tapi teman-temanku tidak akan terbantu.”',
        'Apa maksudmu dengan “tidak terbantu”?',
        '“Apa?” tanyanya.',
        'Lalu diam.',
      ],
    );
  });

  test('an opening quote starts a new sentence', () {
    expect(splitSentences('Dia berkata. “Pergi!” Lalu pergi.'), [
      'Dia berkata.',
      '“Pergi!”',
      'Lalu pergi.',
    ]);
  });

  test('abbreviations, initials and decimals do not split', () {
    expect(
      splitSentences(
        '“Sayangku Mr. Bennet,” kata Mrs. Long. Dr. Watson dan St. Paul '
        'datang, dll. Harganya 3.5 dinar. J. R. Tolkien menulis.',
      ),
      [
        '“Sayangku Mr. Bennet,” kata Mrs. Long.',
        'Dr. Watson dan St. Paul datang, dll. Harganya 3.5 dinar.',
        'J. R. Tolkien menulis.',
      ],
    );
    expect(splitSentences('Buah, mis. Apel. Lalu'), [
      'Buah, mis. Apel.',
      'Lalu',
    ]);
  });

  test('numbering at the start does not split', () {
    expect(splitSentences('IX. Ada hal. Ada lagi.'), [
      'IX. Ada hal.',
      'Ada lagi.',
    ]);
    expect(splitSentences('3. Satu. Dua.'), ['3. Satu.', 'Dua.']);
  });

  test('ellipsis', () {
    expect(splitSentences('Jadi… Begitulah... Selesai.'), [
      'Jadi…',
      'Begitulah...',
      'Selesai.',
    ]);
    expect(splitSentences('Tunggu… dulu.'), ['Tunggu… dulu.']);
  });

  test('empty and whitespace', () {
    expect(splitSentences(''), isEmpty);
    expect(splitSentences('  Satu.  Dua.  '), ['Satu.', 'Dua.']);
  });
}
