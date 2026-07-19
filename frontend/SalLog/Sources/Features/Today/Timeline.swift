import Foundation

/// 연속 브이로그 타임라인 — JSX buildSegments/sideAt 이식.
/// 같은 시각(±1분)에 서로 다른 멤버가 찍은 클립을 한 세그먼트로 합친다.
struct Segment: Identifiable, Hashable {
    let id = UUID()
    var time: Date
    /// userId → 해당 세그먼트에서 활성인 클립
    var clips: [UUID: TaggedClip]

    var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: time)
    }
}

enum Timeline {
    static let defaultSegmentSec: Double = 3.0
    static let minSegmentSec: Double = 1.6
    static let maxSegmentSec: Double = 8.0
    static let maxClipSec: Double = 6.0

    static func buildSegments(_ clips: [TaggedClip]) -> [Segment] {
        let sorted = clips.sorted { $0.recordedAt < $1.recordedAt }
        var segments: [Segment] = []
        for clip in sorted {
            if var last = segments.last,
               last.clips[clip.userId] == nil,
               abs(last.time.timeIntervalSince(clip.recordedAt)) <= 60 {
                last.clips[clip.userId] = clip
                segments[segments.count - 1] = last
            } else {
                segments.append(Segment(time: clip.recordedAt, clips: [clip.userId: clip]))
            }
        }
        return segments
    }

    /// idx 시점에 트랙(userId)에 보여줄 클립: 현재 세그먼트에 있으면 active,
    /// 없으면 직전 클립을 홀드(dim 처리)
    static func sideAt(
        _ segments: [Segment], index: Int, userId: UUID
    ) -> (clip: TaggedClip?, active: Bool) {
        guard index < segments.count else { return (nil, false) }
        for i in stride(from: index, through: 0, by: -1) {
            if let clip = segments[i].clips[userId] {
                return (clip, i == index)
            }
        }
        return (nil, false)
    }

    /// 세그먼트 표시 시간: 포함된 클립 실제 길이의 최댓값, 1.6~8초로 클램프
    static func duration(of segment: Segment, durations: [UUID: Double]) -> Double {
        var d: Double = 0
        for clip in segment.clips.values {
            let clipDur = clip.clip.videoKey != nil
                ? (durations[clip.id] ?? defaultSegmentSec)
                : defaultSegmentSec
            d = max(d, clipDur)
        }
        return min(max(d, minSegmentSec), maxSegmentSec)
    }
}
