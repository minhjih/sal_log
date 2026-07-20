import UIKit
import AVFoundation
import SwiftUI
import Foundation

// 오버레이(인트로·세그먼트 HUD·아웃트로·진행바) CALayer 구성.
// 모든 좌표·폰트는 fs(기준 폭 960 대비 스케일)와 캔버스 크기에서 계산해
// 4:5 / 9:16 / 16:9 어느 화면비에서도 같은 룩을 유지한다.
extension VlogExporter {

    func overlayLayer(
        input: Input,
        bounds: [Double],          // [introEnd, seg1End, …, lastSegEnd]
        segDurations: [Double],
        totalSec: Double,
        rows: [Row]
    ) -> CALayer {
        let W = size.width
        let overlay = CALayer()
        overlay.frame = CGRect(origin: .zero, size: size)
        overlay.isGeometryFlipped = true   // 캔버스처럼 좌상단 원점으로

        let outroStart = bounds.last ?? Self.introSec
        let stripH = stripHeight
        let top = contentTop   // 콘텐츠(4:5) 블록 시작 — 위아래는 검은 레터박스

        // ── 세그먼트 공통: 중앙 이음선 + 줄 하단 그라데이션 + 이름 ──
        let seam = Self.gradientLayer(
            colors: [UIColor(Theme.me), UIColor(Theme.lover)],
            frame: CGRect(x: 0, y: top + stripH - 1.5 * fs, width: W, height: 3 * fs)
        )
        window(seam, from: Self.introSec, to: outroStart, total: totalSec)
        overlay.addSublayer(seam)

        for (rowIndex, row) in rows.enumerated() {
            let stripBottom = top + CGFloat(rowIndex + 1) * stripH
            let shade = Self.gradientLayer(
                colors: [UIColor.black.withAlphaComponent(0),
                         UIColor.black.withAlphaComponent(0.6)],
                frame: CGRect(x: 0, y: stripBottom - 78 * fs, width: W, height: 78 * fs),
                vertical: true
            )
            window(shade, from: Self.introSec, to: outroStart, total: totalSec)
            overlay.addSublayer(shade)

            let name = Self.textLayer(row.member.displayName, size: 17 * fs, weight: .bold,
                                      color: UIColor(Color(hex: row.member.colorHex)),
                                      alignment: .left)
            name.frame = CGRect(x: 26 * fs, y: stripBottom - 40 * fs,
                                width: 300 * fs, height: 24 * fs)
            window(name, from: Self.introSec, to: outroStart, total: totalSec)
            overlay.addSublayer(name)
        }

        // ── 인트로 ────────────────────────────────────────
        overlay.addSublayer(introLayer(dateLabel: input.dateLabel, total: totalSec))

        // ── 세그먼트별 HUD ────────────────────────────────
        for (si, segment) in input.segments.enumerated() {
            let segStart = bounds[si]
            let segEnd = bounds[si + 1]

            // 시간 칩 (콘텐츠 영역 상단 중앙)
            let chipBG = CALayer()
            chipBG.frame = CGRect(x: W / 2 - 54 * fs, y: top + 24 * fs,
                                  width: 108 * fs, height: 40 * fs)
            chipBG.backgroundColor = UIColor.black.withAlphaComponent(0.45).cgColor
            chipBG.cornerRadius = 20 * fs
            window(chipBG, from: segStart, to: segEnd, total: totalSec)
            overlay.addSublayer(chipBG)

            let chipText = Self.textLayer(segment.timeLabel, size: 22 * fs, weight: .semibold,
                                          color: .white, alignment: .center)
            chipText.frame = CGRect(x: W / 2 - 54 * fs, y: top + 31 * fs,
                                    width: 108 * fs, height: 28 * fs)
            window(chipText, from: segStart, to: segEnd, total: totalSec)
            overlay.addSublayer(chipText)

            for (rowIndex, row) in rows.enumerated() {
                let stripTop = top + CGFloat(rowIndex) * stripH
                let stripBottom = stripTop + stripH
                guard let clip = segment.clips[row.member.userId] else { continue }

                if clip.clip.videoKey == nil || input.localFiles[clip.id] == nil {
                    // 영상 없는 클립: 캡션을 스트립 중앙에 크게
                    let caption = Self.textLayer(clip.caption, size: 24 * fs, weight: .semibold,
                                                 color: .white, alignment: .center)
                    caption.frame = CGRect(x: 100 * fs, y: stripTop + stripH / 2 - 32 * fs,
                                           width: W - 200 * fs, height: 64 * fs)
                    caption.isWrapped = true
                    window(caption, from: segStart, to: segEnd, total: totalSec)
                    overlay.addSublayer(caption)
                } else {
                    // 캡션 (중앙 하단)
                    let caption = Self.textLayer(clip.caption, size: 20 * fs, weight: .medium,
                                                 color: UIColor.white.withAlphaComponent(0.94),
                                                 alignment: .center)
                    caption.frame = CGRect(x: 160 * fs, y: stripBottom - 42 * fs,
                                           width: W - 320 * fs, height: 26 * fs)
                    window(caption, from: segStart, to: segEnd, total: totalSec)
                    overlay.addSublayer(caption)
                }

                // kcal (우하단)
                if let tag = clip.tag {
                    let sign = tag.isMove ? "−" : "+"
                    let color = tag.isMove ? UIColor(Theme.green) : .white
                    let kcal = Self.textLayer("\(sign)\(tag.kcal.formatted()) kcal",
                                              size: 20 * fs, weight: .bold,
                                              color: color, alignment: .right)
                    kcal.frame = CGRect(x: W - 326 * fs, y: stripBottom - 42 * fs,
                                        width: 300 * fs, height: 26 * fs)
                    window(kcal, from: segStart, to: segEnd, total: totalSec)
                    overlay.addSublayer(kcal)
                }
            }
        }

        // ── 아웃트로 ──────────────────────────────────────
        overlay.addSublayer(outroLayer(rows: rows, from: outroStart, total: totalSec))

        // ── 진행 바 (상단, 인트로+세그+아웃트로 칸) ────────
        overlay.addSublayer(progressLayer(
            bounds: [0] + bounds + [totalSec], total: totalSec
        ))

        return overlay
    }

    // ── 인트로 ────────────────────────────────────────────
    private func introLayer(dateLabel: String, total: Double) -> CALayer {
        let W = size.width, H = size.height
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.backgroundColor = UIColor(Theme.bg).cgColor

        let title = Self.textLayer("ki—log", size: 54 * fs, weight: .light,
                                   color: UIColor(Theme.text), alignment: .center)
        title.frame = CGRect(x: 0, y: H / 2 - 62 * fs, width: W, height: 66 * fs)
        layer.addSublayer(title)

        let underline = Self.gradientLayer(
            colors: [UIColor(Theme.me), UIColor(Theme.lover)],
            frame: CGRect(x: W / 2 - 55 * fs, y: H / 2 + 8 * fs,
                          width: 110 * fs, height: 3 * fs)
        )
        layer.addSublayer(underline)

        let subtitle = Self.textLayer("\(dateLabel) · 둘이 찍은 하루",
                                      size: 22 * fs, weight: .medium,
                                      color: UIColor(Theme.muted), alignment: .center)
        subtitle.frame = CGRect(x: 0, y: H / 2 + 40 * fs, width: W, height: 30 * fs)
        layer.addSublayer(subtitle)

        window(layer, from: 0, to: Self.introSec, total: total, fadeOut: 0.3)
        return layer
    }

    // ── 아웃트로 (세로 중앙 정렬 — 모든 화면비 대응) ───────
    private func outroLayer(rows: [Row], from start: Double, total: Double) -> CALayer {
        let W = size.width, H = size.height
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.backgroundColor = UIColor(Theme.bg).cgColor

        let heading = Self.textLayer("오늘, 우리", size: 22 * fs, weight: .medium,
                                     color: UIColor(Theme.muted), alignment: .center)
        heading.frame = CGRect(x: 0, y: H / 2 - 190 * fs, width: W, height: 30 * fs)
        layer.addSublayer(heading)

        let cardTop = H / 2 - 140 * fs
        for (i, row) in rows.prefix(2).enumerated() {
            let centerX = W / 2 + (rows.count == 1 ? 0 : (i == 0 ? -130 * fs : 130 * fs))
            let card = CALayer()
            card.frame = CGRect(x: centerX - 110 * fs, y: cardTop,
                                width: 220 * fs, height: 220 * fs)
            card.backgroundColor = UIColor(Theme.surface).cgColor
            card.cornerRadius = 22 * fs
            layer.addSublayer(card)

            let name = Self.textLayer(row.member.displayName, size: 22 * fs, weight: .semibold,
                                      color: UIColor(Color(hex: row.member.colorHex)),
                                      alignment: .center)
            name.frame = CGRect(x: centerX - 110 * fs, y: cardTop + 26 * fs,
                                width: 220 * fs, height: 28 * fs)
            layer.addSublayer(name)

            let balance = row.stats.balance
            let balanceText = Self.textLayer(
                "\(balance > 0 ? "+" : "")\(balance.formatted())",
                size: 42 * fs, weight: .light, color: UIColor(Theme.text), alignment: .center
            )
            balanceText.frame = CGRect(x: centerX - 110 * fs, y: cardTop + 72 * fs,
                                       width: 220 * fs, height: 50 * fs)
            layer.addSublayer(balanceText)

            let unit = Self.textLayer("kcal 수지", size: 17 * fs, weight: .regular,
                                      color: UIColor(Theme.muted), alignment: .center)
            unit.frame = CGRect(x: centerX - 110 * fs, y: cardTop + 124 * fs,
                                width: 220 * fs, height: 22 * fs)
            layer.addSublayer(unit)

            let detail = Self.textLayer(
                "섭취 \(row.stats.intake) · 소모 \(row.stats.burnTotal)",
                size: 17 * fs, weight: .regular,
                color: UIColor(Theme.muted), alignment: .center
            )
            detail.frame = CGRect(x: centerX - 110 * fs, y: cardTop + 174 * fs,
                                  width: 220 * fs, height: 22 * fs)
            layer.addSublayer(detail)
        }

        let underline = Self.gradientLayer(
            colors: [UIColor(Theme.me), UIColor(Theme.lover)],
            frame: CGRect(x: W / 2 - 38 * fs, y: H / 2 + 118 * fs,
                          width: 76 * fs, height: 3 * fs)
        )
        layer.addSublayer(underline)

        let tagline = Self.textLayer("ki—log · 같은 하루, 같은 다짐",
                                     size: 18 * fs, weight: .medium,
                                     color: UIColor(Theme.faint), alignment: .center)
        tagline.frame = CGRect(x: 0, y: H / 2 + 148 * fs, width: W, height: 24 * fs)
        layer.addSublayer(tagline)

        window(layer, from: start, to: total, total: total, fadeIn: 0.4)
        return layer
    }

    // ── 진행 바 (콘텐츠 영역 상단) ────────────────────────
    private func progressLayer(bounds: [Double], total: Double) -> CALayer {
        let W = size.width
        let container = CALayer()
        container.frame = CGRect(x: 0, y: contentTop, width: W, height: 24 * fs)

        let n = bounds.count - 1
        let gap: CGFloat = 5 * fs
        let barWidth = (W - 48 * fs - CGFloat(n - 1) * gap) / CGFloat(n)

        for i in 0..<n {
            let x = 24 * fs + CGFloat(i) * (barWidth + gap)
            let track = CALayer()
            track.frame = CGRect(x: x, y: 14 * fs, width: barWidth, height: 3 * fs)
            track.cornerRadius = 1.5 * fs
            track.backgroundColor = UIColor.white.withAlphaComponent(0.28).cgColor
            container.addSublayer(track)

            let fill = CALayer()
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            fill.frame = CGRect(x: x, y: 14 * fs, width: barWidth, height: 3 * fs)
            fill.cornerRadius = 1.5 * fs
            fill.backgroundColor = UIColor.white.cgColor
            container.addSublayer(fill)

            let anim = CAKeyframeAnimation(keyPath: "bounds.size.width")
            anim.duration = total
            anim.keyTimes = [
                0,
                NSNumber(value: bounds[i] / total),
                NSNumber(value: bounds[i + 1] / total),
                1,
            ]
            anim.values = [0, 0, barWidth, barWidth]
            anim.beginTime = AVCoreAnimationBeginTimeAtZero
            anim.isRemovedOnCompletion = false
            anim.fillMode = .forwards
            fill.bounds = CGRect(x: 0, y: 0, width: 0, height: 3 * fs)
            fill.add(anim, forKey: "fill")
        }
        return container
    }

    // ── 레이어 유틸 ───────────────────────────────────────
    static func textLayer(
        _ text: String, size: CGFloat, weight: UIFont.Weight,
        color: UIColor, alignment: CATextLayerAlignmentMode
    ) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = text
        layer.font = UIFont.systemFont(ofSize: size, weight: weight)
        layer.fontSize = size
        layer.foregroundColor = color.cgColor
        layer.alignmentMode = alignment
        layer.contentsScale = 2
        layer.truncationMode = .end
        return layer
    }

    static func gradientLayer(
        colors: [UIColor], frame: CGRect, vertical: Bool = false
    ) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.frame = frame
        layer.colors = colors.map(\.cgColor)
        layer.startPoint = vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        layer.endPoint = vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
        return layer
    }

    /// [from, to] 구간에서만 보이도록 opacity 키프레임 적용
    func window(
        _ layer: CALayer, from: Double, to: Double, total: Double,
        fadeIn: Double = 0.15, fadeOut: Double = 0.1
    ) {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.duration = total

        var times: [NSNumber] = []
        var values: [Float] = []
        func key(_ t: Double, _ v: Float) {
            times.append(NSNumber(value: max(0, min(1, t / total))))
            values.append(v)
        }
        key(0, from <= 0.001 ? 1 : 0)
        if from > 0.001 {
            key(from, 0)
            key(min(from + fadeIn, to), 1)
        }
        key(max(to - fadeOut, from), 1)
        if to < total - 0.001 {
            key(to, 0)
            key(total, 0)
        } else {
            key(total, 1)
        }

        anim.keyTimes = times
        anim.values = values
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        layer.opacity = from <= 0.001 ? 1 : 0
        layer.add(anim, forKey: "window")
    }
}
