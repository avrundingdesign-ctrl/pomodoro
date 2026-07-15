import SwiftUI

/// One jigsaw piece of a `rows × cols` puzzle covering `rect`.
///
/// Every interior edge carries a classic mushroom-shaped knob. Whether the
/// knob bulges into this piece or its neighbour is decided by a deterministic
/// hash of the edge position, so the two adjacent pieces always trace the
/// exact same curve and the full set tiles the rectangle without gaps.
/// Outer edges stay flat.
struct JigsawPieceShape: Shape {
    let row: Int
    let col: Int
    let rows: Int
    let cols: Int

    func path(in rect: CGRect) -> Path {
        let w = rect.width / CGFloat(cols)
        let h = rect.height / CGFloat(rows)
        // Knobs scale with the smaller cell side so they look uniform.
        let knob = min(w, h)

        let x0 = rect.minX + CGFloat(col) * w
        let y0 = rect.minY + CGFloat(row) * h
        let tl = CGPoint(x: x0, y: y0)
        let tr = CGPoint(x: x0 + w, y: y0)
        let br = CGPoint(x: x0 + w, y: y0 + h)
        let bl = CGPoint(x: x0, y: y0 + h)

        var p = Path()
        p.move(to: tl)
        // Clockwise; the perpendicular used by `edge` always points outward.
        edge(&p, from: tl, to: tr, sign: topSign, knob: knob)
        edge(&p, from: tr, to: br, sign: rightSign, knob: knob)
        edge(&p, from: br, to: bl, sign: bottomSign, knob: knob)
        edge(&p, from: bl, to: tl, sign: leftSign, knob: knob)
        p.closeSubpath()
        return p
    }

    // MARK: - Edge tab directions

    // Convention: horizontal edge below (r, c) protrudes downward when the
    // hash is true; vertical edge right of (r, c) protrudes rightward.
    // +1 = knob bulges out of this piece, -1 = neighbour's knob bulges in.
    private var topSign: CGFloat { row == 0 ? 0 : (Self.tab(row - 1, col, 2) ? -1 : 1) }
    private var bottomSign: CGFloat { row == rows - 1 ? 0 : (Self.tab(row, col, 2) ? 1 : -1) }
    private var leftSign: CGFloat { col == 0 ? 0 : (Self.tab(row, col - 1, 1) ? -1 : 1) }
    private var rightSign: CGFloat { col == cols - 1 ? 0 : (Self.tab(row, col, 1) ? 1 : -1) }

    /// Deterministic per-edge coin flip (splitmix-style hash).
    private static func tab(_ r: Int, _ c: Int, _ salt: UInt64) -> Bool {
        var x = UInt64(bitPattern: Int64(r)) &* 0x9E3779B97F4A7C15
        x ^= UInt64(bitPattern: Int64(c)) &* 0xBF58476D1CE4E5B9
        x ^= salt &* 0x94D049BB133111EB
        x = (x ^ (x >> 31)) &* 0xD6E8FEB86659FD93
        return (x >> 33) & 1 == 0
    }

    // MARK: - Edge geometry

    /// Appends one edge from `a` to `b`. `sign` = 0 draws a straight line;
    /// ±1 draws a symmetric mushroom knob toward (+) or away from (–) the
    /// outward perpendicular of the travel direction. `knob` is the length
    /// unit for the knob (the smaller cell side).
    private func edge(_ p: inout Path, from a: CGPoint, to b: CGPoint,
                      sign: CGFloat, knob: CGFloat) {
        guard sign != 0 else {
            p.addLine(to: b)
            return
        }
        let dx = b.x - a.x, dy = b.y - a.y
        // Outward perpendicular of clockwise travel: (dy, -dx) normalized.
        let len = (dx * dx + dy * dy).squareRoot()
        let nx = dy / len * sign, ny = -dx / len * sign

        // (t, u): t runs 0→1 along the edge, u is in knob units along the
        // perpendicular. Mushroom: pinch at the neck, bulge past it.
        func pt(_ t: CGFloat, _ u: CGFloat) -> CGPoint {
            CGPoint(x: a.x + dx * t + nx * u * knob,
                    y: a.y + dy * t + ny * u * knob)
        }

        p.addLine(to: pt(0.40, 0))
        p.addCurve(to: pt(0.50, 0.19),
                   control1: pt(0.52, 0.02),
                   control2: pt(0.33, 0.19))
        p.addCurve(to: pt(0.60, 0),
                   control1: pt(0.67, 0.19),
                   control2: pt(0.48, 0.02))
        p.addLine(to: b)
    }
}
