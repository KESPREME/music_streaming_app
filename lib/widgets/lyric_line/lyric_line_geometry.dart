// lib/widgets/lyric_line/lyric_line_geometry.dart
// Where every character of a laid-out lyric line sits - per VISUAL ROW.
//
// WHY THIS IS ITS OWN FILE
//
// The old renderer measured one number per character: the caret's x. That is a
// fact about a single row. On a line that WRAPS, x resets to about zero at the
// start of row two, so:
//
//   * the lit clip (one rect, full height) lit BOTH rows up to the same x,
//     which read as "two lines at a time";
//   * every lifted word was drawn at `top: 0`, so a word on row two painted
//     over row one at its row-two x ("You're going t|o put / ɛme outg   o");
//   * a word that straddled the wrap got a negative or too-narrow box and
//     re-wrapped inside itself.
//
// So the unit here is the ROW: its character range, its band (top..bottom),
// and per-character left/right edges that belong to a row. Everything the
// renderer does - the clip, the lift, the swell - is expressed per row.
//
// Pure data from a laid-out [TextPainter]; no Flutter widgets, so it can be
// pinned in a unit test against a deliberately narrow, wrapping layout.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show BoxHeightStyle, BoxWidthStyle;

import 'package:flutter/painting.dart';

/// One visual row of a laid-out line.
class LyricRow {
  const LyricRow({
    required this.start,
    required this.end,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  /// Characters `[start, end)` belong to this row. Trailing whitespace at a
  /// wrap, and any text cut off by an ellipsis, belong to the last row they
  /// follow so the wipe passes through them at that row's right edge.
  final int start;
  final int end;

  /// Horizontal extent of the row's drawn characters.
  final double left;
  final double right;

  /// The row's line box. Rows are contiguous: one row's bottom is the next
  /// row's top, which is what lets a clip per row tile the paragraph exactly.
  final double top;
  final double bottom;

  double get height => bottom - top;

  @override
  String toString() =>
      'LyricRow([$start,$end) x:${left.toStringAsFixed(1)}..'
      '${right.toStringAsFixed(1)} y:${top.toStringAsFixed(1)}..'
      '${bottom.toStringAsFixed(1)})';
}

/// The per-row geometry of one laid-out line.
class LyricLineGeometry {
  LyricLineGeometry._({
    required this.length,
    required this.charLeft,
    required this.charRight,
    required this.charRow,
    required this.rows,
  });

  /// Measures [painter], which must already be laid out for [text].
  factory LyricLineGeometry.measure(TextPainter painter, String text) {
    final n = text.length;
    final left = Float64List(n);
    final right = Float64List(n);
    final rowOf = Int32List(n);
    final hasBox = List<bool>.filled(n, false);

    final rowTops = <double>[];
    final rowBottoms = <double>[];

    for (var i = 0; i < n; i++) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
        // `max` stretches every box to the full line box, so rows are
        // contiguous bands and a clip per row tiles the paragraph with no gap.
        boxHeightStyle: BoxHeightStyle.max,
        boxWidthStyle: BoxWidthStyle.tight,
      );
      if (boxes.isEmpty) continue;

      var l = double.infinity;
      var r = double.negativeInfinity;
      var t = double.infinity;
      var b = double.negativeInfinity;
      for (final box in boxes) {
        l = math.min(l, box.left);
        r = math.max(r, box.right);
        t = math.min(t, box.top);
        b = math.max(b, box.bottom);
      }

      // A new row starts when this character's band begins at or below the
      // current row's bottom. Compared with slack: bands that are contiguous
      // differ by a rounding hair, not by zero.
      if (rowTops.isEmpty || t >= rowBottoms.last - 0.5) {
        // Guard against a degenerate band re-opening the same row.
        if (rowTops.isEmpty || t > rowTops.last + 0.5) {
          rowTops.add(t);
          rowBottoms.add(b);
        }
      } else {
        rowBottoms[rowBottoms.length - 1] =
            math.max(rowBottoms.last, b);
      }
      left[i] = l;
      right[i] = r;
      rowOf[i] = rowTops.length - 1;
      hasBox[i] = true;
    }

    if (rowTops.isEmpty) {
      // Nothing measurable (empty text, or fully ellipsised): one empty row so
      // callers never index an empty list.
      return LyricLineGeometry._(
        length: n,
        charLeft: left,
        charRight: right,
        charRow: rowOf,
        rows: <LyricRow>[
          LyricRow(
            start: 0,
            end: n,
            left: 0,
            right: 0,
            top: 0,
            bottom: painter.height,
          ),
        ],
      );
    }

    // Characters with no box (a collapsed space at a wrap, text past an
    // ellipsis) inherit the previous character's right edge and row, so the
    // wipe crosses them at the edge of the row they trail.
    var prevRight = 0.0;
    var prevRow = 0;
    for (var i = 0; i < n; i++) {
      if (hasBox[i]) {
        prevRight = right[i];
        prevRow = rowOf[i];
      } else {
        left[i] = prevRight;
        right[i] = prevRight;
        rowOf[i] = prevRow;
      }
    }

    final rowCount = rowTops.length;
    final starts = List<int>.filled(rowCount, n);
    final ends = List<int>.filled(rowCount, 0);
    final lefts = List<double>.filled(rowCount, double.infinity);
    final rights = List<double>.filled(rowCount, double.negativeInfinity);
    for (var i = 0; i < n; i++) {
      final row = rowOf[i];
      if (i < starts[row]) starts[row] = i;
      if (i + 1 > ends[row]) ends[row] = i + 1;
      if (hasBox[i]) {
        lefts[row] = math.min(lefts[row], left[i]);
        rights[row] = math.max(rights[row], right[i]);
      }
    }

    final rows = <LyricRow>[
      for (var r = 0; r < rowCount; r++)
        LyricRow(
          start: starts[r] > ends[r] ? 0 : starts[r],
          end: ends[r],
          left: lefts[r].isFinite ? lefts[r] : 0,
          right: rights[r].isFinite ? rights[r] : 0,
          top: rowTops[r],
          // A row's bottom is the next row's top, so the bands tile exactly;
          // the last row ends where the paragraph does.
          bottom: r + 1 < rowCount ? rowTops[r + 1] : rowBottoms[r],
        ),
    ];

    return LyricLineGeometry._(
      length: n,
      charLeft: left,
      charRight: right,
      charRow: rowOf,
      rows: rows,
    );
  }

  /// Number of UTF-16 code units in the line.
  final int length;

  /// Per-character horizontal edges, within that character's own row.
  final Float64List charLeft;
  final Float64List charRight;

  /// Which row each character is on.
  final Int32List charRow;

  final List<LyricRow> rows;

  int get rowCount => rows.length;

  /// Calls [visit] once for each row that the character range `[a, b)` touches,
  /// with the horizontal extent of the covered characters on THAT row.
  ///
  /// A word that wraps is therefore visited twice, once per row, each time with
  /// that row's own x range - which is the whole fix for words drawn on the
  /// wrong row.
  void forEachRowSegment(
    int a,
    int b,
    void Function(int row, double x0, double x1) visit,
  ) {
    if (b <= a || length == 0) return;
    final from = a.clamp(0, length);
    final to = b.clamp(0, length);
    if (to <= from) return;
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final s = math.max(from, row.start);
      final e = math.min(to, row.end);
      if (s >= e) continue;
      visit(r, charLeft[s], charRight[e - 1]);
    }
  }

  /// The x on [rowIndex] that a wipe reaching [revealed] (a fractional
  /// character index) has got to.
  ///
  /// [sweepSpans] are the ranges that move at CONSTANT speed: a syllable's
  /// pixel width is crossed evenly however narrow or wide its letters are.
  /// Anything else interpolates inside the character it has reached.
  ///
  /// Row-aware, which is the point: an index on row two answers with an x on
  /// row two, never with row one's.
  double xAt(
    int rowIndex,
    double revealed,
    List<(int, int)> sweepSpans,
  ) {
    final row = rows[rowIndex];
    if (revealed <= row.start) return row.left;
    if (revealed >= row.end) return row.right;

    // Inside a sweep span that lies ENTIRELY on this row: even speed across it.
    for (final (s, e) in sweepSpans) {
      if (revealed < s || revealed > e) continue;
      if (s < row.start || e > row.end) continue; // broken over a wrap
      if (e <= s) continue;
      final t = (revealed - s) / (e - s);
      final x0 = charLeft[s];
      final x1 = charRight[e - 1];
      return (x0 + (x1 - x0) * t).clamp(row.left, row.right).toDouble();
    }

    // Otherwise inside the character: between its edges.
    final i = revealed.floor().clamp(row.start, row.end - 1);
    final f = (revealed - i).clamp(0.0, 1.0).toDouble();
    return (charLeft[i] + (charRight[i] - charLeft[i]) * f)
        .clamp(row.left, row.right)
        .toDouble();
  }
}
