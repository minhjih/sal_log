# Kilog frontend (SwiftUI · iOS 17+)

커플/친구 그룹 다이어트 브이로그 앱 **Kilog**의 iOS 클라이언트입니다.
React 프로토타입(v8)의 디자인·플로우를 SwiftUI로 이식하고, 데모로만 구현되어 있던
부분을 전부 실제 동작으로 교체했습니다.

폴더 구조는 Xcode 기본 템플릿 프로젝트 **kilog**에 바로 붙여넣을 수 있게 맞춰져 있습니다.

## 프로젝트에 넣는 법

Xcode에서 `kilog` 프로젝트를 연 상태에서:

1. **템플릿 파일 정리**
   - `ContentView.swift` 삭제
   - `kilogApp.swift`의 내용을 이 저장소의 `kilog/kilogApp.swift` 내용으로 교체
     (진입점 `struct kilogApp: App` 이름까지 맞춰져 있어 그대로 덮어쓰면 됩니다)

2. **폴더 추가** — Finder에서 이 저장소의 `frontend/kilog/` 안에 있는 4개 폴더를
   Xcode 네비게이터의 `kilog/kilog` (앱 타깃 폴더) 아래로 드래그:
   ```
   App/        AppState, HomeView
   Core/       Theme, Models, HealthMath, Catalogs, Supa
   Services/   AuthService, GroupService, ClipService, BodyService
   Features/   Auth, Today, Capture, Body, Coach, Group, Export
   ```
   드롭 옵션에서 **"Copy items if needed" + "Create groups"** 체크,
   Target Membership에 `kilog` 앱 타깃이 선택돼 있는지 확인.
   (`kilogTests` / `kilogUITests`는 그대로 두면 됩니다.)

3. **SPM 의존성** — File → Add Package Dependencies →
   `https://github.com/supabase/supabase-swift` (2.x) → 제품 `Supabase`를 kilog 타깃에 추가

4. **Info 설정** — 타깃 → Info 탭에 추가:
   | Key | 값 예시 |
   |---|---|
   | `NSCameraUsageDescription` | 브이로그 클립을 촬영하기 위해 카메라를 사용해요. |
   | `NSMicrophoneUsageDescription` | 클립에 소리를 담기 위해 마이크를 사용해요. |
   | `NSPhotoLibraryUsageDescription` | 영상·인바디 검사지 사진을 불러오기 위해 앨범에 접근해요. |
   | `NSPhotoLibraryAddUsageDescription` | 완성된 브이로그 영상을 사진 앨범에 저장해요. |
   | URL Types → URL Schemes | `app.kilog` (OAuth 콜백·초대 딥링크) |

5. **Capability** — Signing & Capabilities → **Sign in with Apple** 추가

6. **백엔드 연결** — `Core/Supa.swift`의 `SupabaseConfig`에 Supabase 프로젝트 URL과
   anon key 입력 (backend/README.md 참고)

실기기 실행 권장 (카메라·Vision OCR).

## 구조

```
kilog/
├── kilogApp.swift   앱 진입점 · 딥링크 처리 · RootView(단계 라우팅)
├── App/             AppState(세션→그룹→피드 상태머신), HomeView(탭 셸)
├── Core/            Theme(팔레트), Models(스키마 1:1), HealthMath(BMR·TDEE·MET), Catalogs, Supa(클라이언트)
├── Services/        AuthService, GroupService(RPC), ClipService(업로드·signed URL·Realtime), BodyService
└── Features/
    ├── Auth/        AuthFlowView(웰컴·로그인), GroupSetupView(생성/초대 확인/수락)
    ├── Today/       Timeline(세그먼트 엔진), TheaterView(2트랙 플레이어), TodayView
    ├── Capture/     CameraModel(AVCapture), CaptureView(촬영→메타→저장)
    ├── Body/        InBodyOCR(Vision), ScanFlowView, BodyView(Swift Charts)
    ├── Coach/       CoachView(부위 분석·MET 추천·수지 기반 식단)
    ├── Group/       GroupSheetView(멤버·초대 토큰·공유 설정)
    └── Export/      VlogExporter(+Overlay), ExportView
```

## 프로토타입 대비 "제대로 구현"된 것

| 프로토타입 (데모) | 이 앱 (실구현) |
|---|---|
| 버튼만 있는 가짜 로그인 | Supabase Auth — 이메일/비밀번호, **Sign in with Apple**(nonce 검증), Google·Kakao OAuth(ASWebAuthenticationSession) |
| `Math.random()` 가짜 초대 코드 | 서버 RPC가 발급하는 해시 저장·만료형(7일)·사용횟수 제한 토큰, `preview_invite`→`accept_invite` 흐름, 딥링크(`kilog.app/join/…`) 자동 입력 |
| `setTimeout` 가짜 OCR | **Vision 프레임워크** 한국어 텍스트 인식으로 인바디 검사지에서 체중·골격근량·체지방률 추출 (키워드+행 매칭, 범위 휴리스틱 폴백) |
| 메모리 상태뿐인 데이터 | Supabase Postgres 저장 + **Realtime** 구독으로 파트너 기록 실시간 반영 |
| getUserMedia 웹캠 | AVCaptureSession 전면 카메라, 셔터를 꾹 누르는 동안 녹화, 최대 5초(`maxRecordedDuration`), PhotosPicker 업로드 대체 경로 |
| `<video>` 태그 2개 재생 | AVPlayer 2트랙 연속 재생 엔진 (세그먼트 빌드/홀드 로직 동일 이식) |
| canvas + MediaRecorder 내보내기 | **AVMutableComposition + CoreAnimationTool** — 인트로/아웃트로/자막/시간 칩/진행 바를 CALayer로 합성해 960×540 mp4 생성, ShareLink 공유 |
| 데모 멤버 추가 버튼 | 실제 초대 수락으로만 멤버 증가, 커플→친구 그룹 확장은 오너 전용 RPC |
| 공유 여부 하드코딩 | 항목별 sharing_preferences 토글 → 서버 RLS가 실제로 차단 |

## 계산 로직 (프로토타입과 동일)

- **BMR**: 체지방률이 있으면 Katch-McArdle `370 + 21.6 × LBM`, 없으면 Mifflin-St Jeor
- **TDEE**: `BMR × activity_factor` (기본 1.38)
- **운동 소모**: `MET × 3.5 × 체중 / 200 × 분` (2011 Compendium)
- **수지**: `섭취 − (BMR + 운동 소모)` — 적자(−)면 초록, 흑자(+)면 핑크
- **코치**: 오늘 자극 부위(하체/상체/코어/유산소, ‘전신’은 전부 커버) 분석 → 미자극 부위 상위 2개 추천,
  전부 자극 시 회복(요가) 추천. 음식은 수지 부호 기준 추천 세트.
