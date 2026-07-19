# sal-log frontend (SwiftUI · iOS 17+)

커플/친구 그룹 다이어트 브이로그 앱 **sal-log**의 iOS 클라이언트입니다.
React 프로토타입(v8)의 디자인·플로우를 SwiftUI로 이식하고, 데모로만 구현되어 있던
부분을 전부 실제 동작으로 교체했습니다.

## 프로토타입 대비 "제대로 구현"된 것

| 프로토타입 (데모) | 이 앱 (실구현) |
|---|---|
| 버튼만 있는 가짜 로그인 | Supabase Auth — 이메일/비밀번호, **Sign in with Apple**(nonce 검증), Google·Kakao OAuth(ASWebAuthenticationSession) |
| `Math.random()` 가짜 초대 코드 | 서버 RPC가 발급하는 해시 저장·만료형(7일)·사용횟수 제한 토큰, `preview_invite`→`accept_invite` 흐름, 딥링크(`sal-log.app/join/…`) 자동 입력 |
| `setTimeout` 가짜 OCR | **Vision 프레임워크** 한국어 텍스트 인식으로 인바디 검사지에서 체중·골격근량·체지방률 추출 (키워드+행 매칭, 범위 휴리스틱 폴백) |
| 메모리 상태뿐인 데이터 | Supabase Postgres 저장 + **Realtime** 구독으로 파트너 기록 실시간 반영 |
| getUserMedia 웹캠 | AVCaptureSession 전면 카메라, 최대 6초 녹화(`maxRecordedDuration`), PhotosPicker 업로드 대체 경로 |
| `<video>` 태그 2개 재생 | AVPlayer 2트랙 연속 재생 엔진 (세그먼트 빌드/홀드 로직 동일 이식) |
| canvas + MediaRecorder 내보내기 | **AVMutableComposition + CoreAnimationTool** — 인트로/아웃트로/자막/시간 칩/진행 바를 CALayer로 합성해 960×540 mp4 생성, ShareLink 공유 |
| 데모 멤버 추가 버튼 | 실제 초대 수락으로만 멤버 증가, 커플→친구 그룹 확장은 오너 전용 RPC |
| 공유 여부 하드코딩 | 항목별 sharing_preferences 토글 → 서버 RLS가 실제로 차단 |

## 빌드

```bash
brew install xcodegen
cd frontend
xcodegen generate        # SalLog.xcodeproj 생성 (Supabase SPM 자동 해석)
open SalLog.xcodeproj
```

1. `SalLog/Sources/Core/Supa.swift`의 `SupabaseConfig`에 프로젝트 URL과 anon key 입력
2. Signing 팀 설정 (Sign in with Apple capability 포함)
3. 실기기 실행 권장 (카메라·Vision OCR)

## 구조

```
SalLog/Sources
├── App/            SalLogApp(진입·딥링크), AppState(세션→그룹→피드 상태머신), HomeView(탭 셸)
├── Core/           Theme(팔레트), Models(스키마 1:1), HealthMath(BMR·TDEE·MET), Catalogs, Supa(클라이언트)
├── Services/       AuthService, GroupService(RPC), ClipService(업로드·signed URL·Realtime), BodyService
└── Features/
    ├── Auth/       AuthFlowView(웰컴·로그인), GroupSetupView(생성/초대 확인/수락)
    ├── Today/      Timeline(세그먼트 엔진), TheaterView(2트랙 플레이어), TodayView
    ├── Capture/    CameraModel(AVCapture), CaptureView(촬영→메타→저장)
    ├── Body/       InBodyOCR(Vision), ScanFlowView, BodyView(Swift Charts)
    ├── Coach/      CoachView(부위 분석·MET 추천·수지 기반 식단)
    ├── Group/      GroupSheetView(멤버·초대 토큰·공유 설정)
    └── Export/     VlogExporter(+Overlay), ExportView
```

## 계산 로직 (프로토타입과 동일)

- **BMR**: 체지방률이 있으면 Katch-McArdle `370 + 21.6 × LBM`, 없으면 Mifflin-St Jeor
- **TDEE**: `BMR × activity_factor` (기본 1.38)
- **운동 소모**: `MET × 3.5 × 체중 / 200 × 분` (2011 Compendium)
- **수지**: `섭취 − (BMR + 운동 소모)` — 적자(−)면 초록, 흑자(+)면 핑크
- **코치**: 오늘 자극 부위(하체/상체/코어/유산소, ‘전신’은 전부 커버) 분석 → 미자극 부위 상위 2개 추천,
  전부 자극 시 회복(요가) 추천. 음식은 수지 부호 기준 추천 세트.
