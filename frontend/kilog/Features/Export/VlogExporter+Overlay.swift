import UIKit
import AVFoundation
import SwiftUI
import Foundation

// 오버레이(인트로·세그먼트 HUD·아웃트로·진행바) CALayer 구성
extension VlogExporter {

    static func overlayLayer(
        input: Input,
        bounds: [Double],          // [introEnd, seg1End, …, lastSegEnd]
        segDurations: [Double],
        totalSec: Double,
        rows: [Row]
    ) -> CALayer {
        let overlay = CALayer()
        overlay.frame = CGRect(x: 0, y: 0, width: width, height: height)
        overlay.isGeometryFlipped = true   // 캔버스처럼 좌상단 원점으로

        let outroStart = bounds.last ?? Self.introSec

        // ── 세그먼트 공통: 중앙 이음선 + 줄 하단 그라데이션 ──
        let seam = gradientLayer(
            colors: [UIColor(Theme.me), UIColor(Theme.lover)],
            frame: CGRect(x: 0, y: height / 2 - 1.5, width: width, height: 3)
        )
        window(seam, from: introSec, to: outroStart, total: totalSec)
        overlay.addSublayer(seam)

        for rowIndex in 0..<rows.count {
            let stripBottom = CGFloat(rowIndex + 1) * height / 2
            let shade = gradientLayer(
                colors: [UIColor.black.withAlphaComponent(0), UIColor.black.withAlphaComponent(0.6)],
                frame: CGRect(x: 0, y: stripBottom - 78, width: width, height: 78),
                vertical: true
            )
            window(shade, from: introSec, to: outroStart, total: totalSec)
            overlay.addSublayer(shade)

            // 이름 (좌하단, 항상 표시)
            let row = rows[rowIndex]
            let name = textLayer(row.member.nickname, size: 17, weight: .bold,
                                 color: UIColor(Color(hex: row.member.colorHex)),
                                 alignment: .left)
            name.frame = CGRect(x: 26, y: stripBottom - 40, width: 300, height: 24)
            window(name, from: introSec, to: outroStart, total: totalSec)
            overlay.addSublayer(name)
        }

        // ── 인트로 ────────────────────────────────────────
        overlay.addSublayer(introLayer(dateLabel: input.dateLabel, total: totalSec))

        // ── 세그먼트별 HUD ────────────────────────────────
        for (si, segment) in input.segments.enumerated() {
            let segStart = bounds[si]      // bounds[0]는 인트로 끝 = 첫 세그 시작
            let segEnd = bounds[si + 1]

            // 시간 칩 (상단 중앙)
            let chipBG = CALayer()
            chipBG.frame = CGRect(x: width / 2 - 54, y: 24, width: 108, height: 40)
            chipBG.backgroundColor = UIColor.black.withAlphaComponent(0.45).cgColor
            chipBG.cornerRadius = 20
            window(chipBG, from: segStart, to: segEnd, total: totalSec)
            overlay.addSublayer(chipBG)

            let chipText = textLayer(segment.timeLabel, size: 22, weight: .semibold,
                                     color: .white, alignment: .center)
            chipText.frame = CGRect(x: width / 2 - 54, y: 31, width: 108, height: 28)
            window(chipText, from: segStart, to: segEnd, total: totalSec)
            overlay.addSublayer(chipText)

            for (rowIndex, row) in rows.enumerated() {
                let stripTop = CGFloat(rowIndex) * height / 2
                let stripBottom = stripTop + height / 2
                guard let clip = segment.clips[row.member.userId] else { continue }

                // 영상이 없는 클립: 캡션을 스트립 중앙에 크게
                if clip.clip.videoKey == nil || input.localFiles[clip.id] == nil {
                    let caption = textLayer(clip.caption, size: 24, weight: .semibold,
                                            color: .white, alignment: .center)
                    caption.frame = CGRect(x: 100, y: stripTop + height / 4 - 16,
                                           width: width - 200, height: 64)
                    caption.isWrapped = true
                    window(caption, from: segStart, to: segEnd, total: totalSec)
                    overlay.addSublayer(caption)
                } else {
                    // 캡션 (중앙 하단)
                    let caption = textLayer(clip.caption, size: 20, weight: .medium,
                                            color: UIColor.white.withAlphaComponent(0.94),
                                            alignment: .center)
                    caption.frame = CGRect(x: 160, y: stripBottom - 42,
                                           width: width - 320, height: 26)
                    window(caption, from: segStart, to: segEnd, total: totalSec)
                    overlay.addSublayer(caption)
                }

                // kcal (우하단)
                if let tag = clip.tag {
                    let sign = tag.isMove ? "−" : "+"
                    let color = tag.isMove ? UIColor(Theme.green) : .white
                    let kcal = textLayer("\(sign)\(tag.kcal.formatted()) kcal",
                                         size: 20, weight: .bold,
                                         color: color, alignment: .right)
                    kcal.frame = CGRect(x: width - 326, y: stripBottom - 42,
                                        width: 300, height: 26)
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
    private static func introLayer(dateLabel: String, total: Double) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        layer.backgroundColor = UIColor(Theme.bg).cgColor

        let title = textLayer("sal—log", size: 54, weight: .light,
                              color: UIColor(Theme.text), alignment: .center)
        title.frame = CGRect(x: 0, y: height / 2 - 62, width: width, height: 66)
        layer.addSublayer(title)

        let underline = gradientLayer(
            colors: [UIColor(Theme.me), UIColor(Theme.lover)],
            frame: CGRect(x: width / 2 - 55, y: height / 2 + 8, width: 110, height: 3)
        )
        layer.addSublayer(underline)

        let subtitle = textLayer("\(dateLabel) · 둘이 찍은 하루", size: 22, weight: .medium,
                                 color: UIColor(Theme.muted), alignment: .center)
        subtitle.frame = CGRect(x: 0, y: height / 2 + 40, width: width, height: 30)
        layer.addSublayer(subtitle)

        window(layer, from: 0, to: introSec, total: total, fadeOut: 0.3)
        return layer
    }

    // ── 아웃트로 ──────────────────────────────────────────
    private static func outroLayer(rows: [Row], from start: Double, total: Double) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        layer.backgroundColor = UIColor(Theme.bg).cgColor

        let heading = textLayer("오늘, 우리", size: 22, weight: .medium,
                                color: UIColor(Theme.muted), alignment: .center)
        heading.frame = CGRect(x: 0, y: 96, width: width, height: 30)
        layer.addSublayer(heading)

        for (i, row) in rows.prefix(2).enumerated() {
            let centerX = width / 2 + (rows.count == 1 ? 0 : (i == 0 ? -130 : 130))
            let card = CALayer()
            card.frame = CGRect(x: centerX - 110, y: 160, width: 220, height: 220)
            card.backgroundColor = UIColor(Theme.surface).cgColor
            card.cornerRadius = 22
            layer.addSublayer(card)

            let name = textLayer(row.member.nickname, size: 22, weight: .semibold,
                                 color: UIColor(Color(hex: row.member.colorHex)),
                                 alignment: .center)
            name.frame = CGRect(x: centerX - 110, y: 186, width: 220, height: 28)
            layer.addSublayer(name)

            let balance = row.stats.balance
            let balanceText = textLayer(
                "\(balance > 0 ? "+" : "")\(balance.formatted())",
                size: 42, weight: .light, color: UIColor(Theme.text), alignment: .center
            )
            balanceText.frame = CGRect(x: centerX - 110, y: 232, width: 220, height: 50)
            layer.addSublayer(balanceText)

            let unit = textLayer("kcal 수지", size: 17, weight: .regular,
                                 color: UIColor(Theme.muted), alignment: .center)
            unit.frame = CGRect(x: centerX - 110, y: 284, width: 220, height: 22)
            layer.addSublayer(unit)

            let detail = textLayer(
                "섭취 \(row.stats.intake) · 소모 \(row.stats.burnTotal)",
                size: 17, weight: .regular, color: UIColor(Theme.muted), alignment: .center
            )
            detail.frame = CGRect(x: centerX - 110, y: 334, width: 220, height: 22)
            layer.addSublayer(detail)
        }

        let underline = gradientLayer(
            colors: [UIColor(Theme.me), UIColor(Theme.lover)],
            frame: CGRect(x: width / 2 - 38, y: 428, width: 76, height: 3)
        )
        layer.addSublayer(underline)

        let tagline = textLayer("sal—log · 같은 하루, 같은 다짐", size: 18, weight: .medium,
                                color: UIColor(Theme.faint), alignment: .center)
        tagline.frame = CGRect(x: 0, y: 460, width: width, height: 24)
        layer.addSublayer(tagline)

        window(layer, from: start, to: total, total: total, fadeIn: 0.4)
        return layer
    }

    // ── 진행 바 ───────────────────────────────────────────
    private static func progressLayer(bounds: [Double], total: Double) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(x: 0, y: 0, width: width, height: 24)

        let n = bounds.count - 1
        let gap: CGFloat = 5
        let barWidth = (width - 48 - CGFloat(n - 1) * gap) / CGFloat(n)

        for i in 0..<n {
            let x = 24 + CGFloat(i) * (barWidth + gap)
            let track = CALayer()
            track.frame = CGRect(x: x, y: 14, width: barWidth, height: 3)
            track.cornerRadius = 1.5
            track.backgroundColor = UIColor.white.withAlphaComponent(0.28).cgColor
            container.addSublayer(track)

            let fill = CALayer()
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            fill.frame = CGRect(x: x, y: 14, width: barWidth, height: 3)
            fill.cornerRadius = 1.5
            fill.backgroundColor = UIColor.white.cgColor
            container.addSublayer(fill)

            // 구간 동안 0 → 최대 너비로 채우기
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
            fill.bounds = CGRect(x: 0, y: 0, width: 0, height: 3)
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
    static func window(
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
