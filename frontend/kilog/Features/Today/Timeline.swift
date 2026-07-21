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
    static let maxClipSec: Double = 5.0

    /// 서로 정확히 같은 시각에 찍지 않아도 끊기지 않도록, 하루를 몇 개의
    /// 시간대 버킷(새벽/아침/점심/저녁/밤)으로 나누고 같은 버킷 안에서는
    /// 멤버별 클립을 순서대로 짝지어 양쪽 트랙이 동시에 연속 재생되게 한다.
    static func buildSegments(_ clips: [TaggedClip]) -> [Segment] {
        func bucket(_ date: Date) -> Int {
            switch Calendar.current.component(.hour, from: date) {
            case 0..<6: return 0    // 새벽
            case 6..<11: return 1   // 아침
            case 11..<15: return 2  // 점심
            case 15..<20: return 3  // 저녁
            default: return 4       // 밤
            }
        }

        let sorted = clips.sorted { $0.recordedAt < $1.recordedAt }
        let grouped = Dictionary(grouping: sorted) { bucket($0.recordedAt) }

        var segments: [Segment] = []
        for key in grouped.keys.sorted() {
            var perUser: [UUID: [TaggedClip]] = [:]
            for clip in grouped[key]! {
                perUser[clip.userId, default: []].append(clip)
            }
            let rounds = perUser.values.map(\.count).max() ?? 0
            for k in 0..<rounds {
                var paired: [UUID: TaggedClip] = [:]
                for (userId, list) in perUser where k < list.count {
                    paired[userId] = list[k]
                }
                let time = paired.values.map(\.recordedAt).min() ?? Date()
                segments.append(Segment(time: time, clips: paired))
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
