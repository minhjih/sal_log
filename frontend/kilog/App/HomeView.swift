import SwiftUI

/// 로그인·그룹 연결 후의 메인 셸: 헤더 + 탭(오늘/코치/바디) + 시트들
struct HomeView: View {
    @EnvironmentObject private var app: AppState

    enum Tab: String, CaseIterable {
        case today = "오늘"
        case metrics = "지표"
        case body = "바디"
    }

    @State private var tab: Tab = .today
    @State private var showCapture = false
    @State private var showGroup = false
    @State private var showScan = false
    @State private var showManualEntry = false
    @State private var showExport = false
    @State private var showProfile = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch tab {
                case .today:
                    TodayView(onCapture: { showCapture = true })
                case .metrics:
                    MetricsView()
                case .body:
                    BodyView(onScan: { showScan = true },
                             onManualEntry: { showManualEntry = true })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabbar
        }
        .background(Theme.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showCapture) {
            CaptureView()
        }
        .sheet(isPresented: $showGroup) {
            GroupSheetView()
                .presentationDetents([.large])
                .presentationBackground(Theme.bg)
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanFlowView(firstTime: false)
        }
        .fullScreenCover(isPresented: $showManualEntry) {
            ScanFlowView(firstTime: false, startManual: true)
        }
        .fullScreenCover(isPresented: $app.needsOnboardingScan) {
            ScanFlowView(firstTime: true)
        }
        .fullScreenCover(isPresented: $showExport) {
            ExportView()
        }
        .sheet(isPresented: $showProfile) {
            ProfileSheetView()
                .presentationDetents([.large])
                .presentationBackground(Theme.bg)
        }
    }

    // ── 헤더 ──────────────────────────────────────────────
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Wordmark()
                if let group = app.group {
                    Text("\(group.name) · \(app.members.count)명 · 오늘 \(app.feed.clips.count)컷")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()

            HStack(spacing: 10) {
                Button {
                    showGroup = true
                } label: {
                    Text("\(app.members.count)")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.lover)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.line))
                }

                Button {
                    showExport = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 36, height: 36)
                        .background(Theme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.line))
                }

                memberPill
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// 멤버 아바타 필 — 나 + 파트너. 탭하면 내 프로필 편집.
    private var memberPill: some View {
        Button {
            showProfile = true
        } label: {
            HStack(spacing: 4) {
                ForEach(app.members.prefix(2)) { member in
                    Circle()
                        .fill(member.userId == app.myId
                              ? Color(hex: member.colorHex)
                              : Theme.surface2)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(member.initial)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(member.userId == app.myId
                                                 ? Color(hex: "#101016") : Theme.faint)
                        )
                }
            }
            .padding(4)
            .background(Theme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.line))
        }
    }

    // ── 탭 바 ─────────────────────────────────────────────
    private var tabbar: some View {
        HStack {
            tabButton(.today, icon: "play.square")
            tabButton(.metrics, icon: "figure.arms.open")
            tabButton(.body, icon: "chart.line.uptrend.xyaxis")
        }
        .padding(6)
        .background(.ultraThinMaterial.opacity(0.9))
        .background(Theme.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line))
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private func tabButton(_ target: Tab, icon: String) -> some View {
        Button {
            tab = target
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17))
                Text(target.rawValue).font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(tab == target ? Theme.text : Theme.faint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(tab == target ? Theme.surface2 : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
