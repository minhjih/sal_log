import SwiftUI
import Charts
import Foundation

/// 바디 탭: 멤버별 체중·골격근량·체지방률 추이 (Swift Charts)
struct BodyView: View {
    @EnvironmentObject private var app: AppState
    let onScan: () -> Void
    let onManualEntry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("바디")
                        .font(.system(size: 19, weight: .bold))
                    Spacer()
                    Text("인바디 흐름 모아보기")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 2)

                sharedBanner

                ForEach(app.members) { member in
                    MemberBodyPanel(member: member, onScan: onScan,
                                    onManualEntry: onManualEntry)
                }

                Text("민감한 신체 데이터는 그룹 연결 및 항목별 공유 동의가 완료된 멤버끼리만 서버(RLS)에서 내려줘요. 공유 설정은 그룹 관리에서 바꿀 수 있어요.")
                    .font(.system(size: 11))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }

    private var sharedBanner: some View {
        HStack {
            Text("공유 중").font(.system(size: 12, weight: .bold))
            Spacer()
            Text("체중 · 골격근량 · 체지방률 · 대사량")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(
            LinearGradient(colors: [Theme.me.opacity(0.12), Theme.lover.opacity(0.12)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

struct MemberBodyPanel: View {
    @EnvironmentObject private var app: AppState
    let member: MemberOverview
    let onScan: () -> Void
    let onManualEntry: () -> Void

    @State private var recordsExpanded = false
    @State private var measurementToDelete: BodyMeasurement?

    private var isMe: Bool { member.userId == app.myId }
    private var profile: BodyProfile? { isMe ? app.myProfile : member.profile }
    private var history: [BodyMeasurement] {
        member.measurements.sorted { $0.measuredAt < $1.measuredAt }
    }
    private var latest: BodyMeasurement? { history.last }
    private var previous: BodyMeasurement? { history.dropLast().last }

    var body: some View {
        VStack(spacing: 11) {
            // 헤더
            HStack {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: member.colorHex))
                        .frame(width: 34, height: 34)
                        .overlay(Text(member.initial)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color(hex: "#101016")))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName).font(.system(size: 14, weight: .semibold))
                        Text(latestLabel)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("BMR").font(.system(size: 9.5)).foregroundStyle(Theme.muted)
                    Text(profile.flatMap(HealthMath.bmr).map { "\($0)" } ?? "—")
                        .font(.system(size: 17, weight: .medium))
                }
            }

            if canSeeBody {
                // 지표
                HStack(spacing: 10) {
                    metric("체중", latest?.weight, unit: "kg",
                           delta: delta(\.weight), goodDown: true)
                    metric("골격근량", latest?.skeletalMuscle, unit: "kg",
                           delta: delta(\.skeletalMuscle), goodDown: false)
                    metric("체지방률", latest?.bodyFat, unit: "%",
                           delta: delta(\.bodyFat), goodDown: true)
                }

                // 체중 추이 차트
                if history.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("체중 추이").font(.system(size: 13, weight: .bold))
                            Spacer()
                            Text("TDEE \(profile.flatMap(HealthMath.tdee).map { "\($0)" } ?? "—") kcal")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                        chart
                    }
                    .padding(12)
                    .card(radius: 16)
                }
            } else {
                Text("아직 신체 수치를 공유하지 않는 멤버예요.\n성과(운동·식단)만 함께 보고 있어요.")
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if isMe, !history.isEmpty {
                recordList
            }

            if isMe {
                HStack(spacing: 8) {
                    Button {
                        onScan()
                    } label: {
                        Text("⌞ ⌝  인바디 스캔")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Theme.line, style: .init(lineWidth: 1, dash: [5]))
                            )
                    }

                    Button {
                        onManualEntry()
                    } label: {
                        Text("✎  직접 입력")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(13)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Theme.line, style: .init(lineWidth: 1, dash: [5]))
                            )
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isMe ? Theme.me.opacity(0.2) : Theme.line)
        )
        .confirmationDialog(
            "이 기록을 삭제할까요?",
            isPresented: .init(
                get: { measurementToDelete != nil },
                set: { if !$0 { measurementToDelete = nil } }
            ),
            presenting: measurementToDelete
        ) { record in
            Button("삭제", role: .destructive) {
                Task { await delete(record) }
            }
            Button("취소", role: .cancel) {}
        } message: { record in
            Text("\(record.measuredAt.formatted(.dateTime.month().day())) 기록이 삭제돼요. 프로필 수치는 남은 최신 기록으로 다시 맞춰져요.")
        }
    }

    // ── 기록 관리 (내 기록만 삭제 가능) ────────────────────
    private var recordList: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { recordsExpanded.toggle() }
            } label: {
                HStack {
                    Text("기록 관리").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(history.count)건")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.faint)
                    Image(systemName: recordsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }

            if recordsExpanded {
                ForEach(history.reversed()) { record in
                    HStack(spacing: 8) {
                        Text(record.measuredAt.formatted(.dateTime.month().day()))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 48, alignment: .leading)
                        Text(recordSummary(record))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Button {
                            measurementToDelete = record
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 26, height: 26)
                                .background(Theme.surface2)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(10)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func recordSummary(_ record: BodyMeasurement) -> String {
        var parts = [String(format: "%.1fkg", record.weight)]
        if let smm = record.skeletalMuscle { parts.append(String(format: "근육 %.1f", smm)) }
        if let fat = record.bodyFat { parts.append(String(format: "체지방 %.1f%%", fat)) }
        return parts.joined(separator: " · ")
    }

    private func delete(_ record: BodyMeasurement) async {
        do {
            try await BodyService.deleteMeasurement(id: record.id)
            await app.refreshBootstrap()
        } catch {
            app.errorMessage = "기록을 삭제하지 못했어요. 다시 시도해 주세요."
        }
    }

    private var canSeeBody: Bool {
        isMe || latest != nil || profile?.weight != nil
    }

    private var latestLabel: String {
        guard let latest else { return "인바디 기록 없음" }
        return "마지막 인바디 " + latest.measuredAt.formatted(.dateTime.month().day())
    }

    private func delta(_ key: KeyPath<BodyMeasurement, Double?>) -> Double? {
        guard let l = latest?[keyPath: key], let p = previous?[keyPath: key] else { return nil }
        return ((l - p) * 10).rounded() / 10
    }

    private func delta(_ key: KeyPath<BodyMeasurement, Double>) -> Double? {
        guard let l = latest?[keyPath: key], let p = previous?[keyPath: key] else { return nil }
        return ((l - p) * 10).rounded() / 10
    }

    private func metric(
        _ label: String, _ value: Double?, unit: String, delta: Double?, goodDown: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 20, weight: .light))
                Text(unit).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            if let delta, delta != 0 {
                let good = (delta < 0) == goodDown
                Text("\(delta > 0 ? "▲" : "▼") \(abs(delta), specifier: "%.1f")\(unit)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(good ? Theme.green : Theme.me)
            } else if delta == 0 {
                Text("유지").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }

    private var chart: some View {
        Chart(history) { record in
            LineMark(
                x: .value("날짜", record.measuredAt),
                y: .value("체중", record.weight)
            )
            .foregroundStyle(Color(hex: member.colorHex))
            .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            PointMark(
                x: .value("날짜", record.measuredAt),
                y: .value("체중", record.weight)
            )
            .foregroundStyle(Theme.bg)
            .symbolSize(60)

            PointMark(
                x: .value("날짜", record.measuredAt),
                y: .value("체중", record.weight)
            )
            .foregroundStyle(Color(hex: member.colorHex))
            .symbolSize(24)
            .annotation(position: .top, spacing: 4) {
                Text(String(format: "%.1f", record.weight))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.muted)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: history.map(\.measuredAt)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(),
                               centered: true)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 96)
    }

    private var yDomain: ClosedRange<Double> {
        let weights = history.map(\.weight)
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        return (min - 0.8)...(max + 0.8)
    }
}
