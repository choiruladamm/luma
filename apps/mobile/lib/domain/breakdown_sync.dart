/// The active block in a Bedahin explanation: the one crossing the reading line.
///
/// [tops] = top position of each block (sections 1..n, then Tokoh & istilah and
/// Praktekinnya if present), relative to the top of the scroll area, in order.
/// Moves to the next block only when its top has passed [line] by [margin]; goes
/// back to the previous block only when the active block's top has dropped [margin]
/// below [line]. So small back-and-forth scrolling near a boundary doesn't make
/// the highlight flicker. [atEnd] (scrolled to the bottom, content really scrolls)
/// = last block, so a short block at the end can still become active.
int activeBlock(
  List<double> tops, {
  required double line,
  required int current,
  double margin = 24,
  bool atEnd = false,
}) {
  if (tops.isEmpty) return 0;
  if (atEnd) return tops.length - 1;
  int lastAbove(double y) {
    var i = 0;
    for (var j = 0; j < tops.length; j++) {
      if (tops[j] <= y) i = j;
    }
    return i;
  }

  final down = lastAbove(line - margin);
  if (down > current) return down;
  final up = lastAbove(line + margin);
  if (up < current) return up;
  return current.clamp(0, tops.length - 1);
}
