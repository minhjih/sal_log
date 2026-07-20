# Kilog 백엔드 셋업 가이드 (Supabase)

처음부터 실서비스 연결까지, 순서대로 따라 하면 되는 가이드입니다. 소요 시간 약 20분.

## 1. Supabase 프로젝트 만들기 (5분)

1. https://supabase.com → 가입/로그인 → **New project**
2. 설정:
   - Name: `kilog`
   - Database Password: 강력한 비밀번호 생성 후 보관 (CLI 배포 때 필요)
   - Region: **Northeast Asia (Seoul)** — 한국 사용자 기준 지연 최소
3. 생성 완료까지 1~2분 대기

## 2. 마이그레이션 적용 (5분)

### 방법 A — Supabase CLI (권장: 이후 스키마 변경 관리가 쉬움)

```bash
brew install supabase/tap/supabase   # 또는: npm i -g supabase
cd backend
supabase login                        # 브라우저 인증
supabase link --project-ref <PROJECT_REF>   # 대시보드 URL의 프로젝트 ID, DB 비밀번호 입력
supabase db push                      # migrations 4개 순서대로 적용
```

### 방법 B — 대시보드 SQL Editor (CLI 설치가 싫을 때)

대시보드 → **SQL Editor** → New query에 아래 파일 내용을 **순서대로** 붙여넣고 Run:

1. `supabase/migrations/20260719000100_init.sql`
2. `supabase/migrations/20260719000200_rls.sql`
3. `supabase/migrations/20260719000300_rpc.sql`
4. `supabase/migrations/20260719000400_storage_realtime.sql`

적용 확인: **Table Editor**에 `users`, `groups`, `clips` 등 10개 테이블 + 카탈로그 2개가 보이고,
**Storage**에 `clips` / `inbody` 버킷이 생겨 있으면 성공.

## 3. Auth 설정 (5분)

대시보드 → **Authentication**:

### 3-1. URL Configuration
- Site URL: `https://kilog.app` (도메인 없으면 일단 아무 값이나 가능)
- **Redirect URLs**에 추가: `app.kilog://auth-callback` ← OAuth 복귀에 필수

### 3-2. Providers
- **Email**: 기본 활성화. 개발 중에는 *Confirm email* 꺼두면 테스트가 편함
  (Authentication → Sign In / Up → Email → Confirm email 토글)
- **Apple** (실기기 출시에 필수):
  - Apple Developer에서 App ID에 *Sign in with Apple* 활성화
  - 네이티브(iOS 앱 내) 로그인은 **Client IDs에 앱 번들 ID**(예: `com.yourteam.kilog`)를 등록하면 끝
- **Google**: Google Cloud Console에서 OAuth Client (iOS 유형) 생성 → client ID/secret 입력
- **Kakao**: Kakao Developers에서 앱 생성 → REST API 키/시크릿 입력,
  Redirect URI에 Supabase가 표시해주는 콜백 URL 등록

> Google/Kakao는 나중에 붙여도 됩니다. 이메일 로그인만으로 앱 전체 기능이 동작해요.

## 4. 앱에 키 연결 (1분)

대시보드 → **Settings → API**:

- Project URL → `frontend/kilog/Core/Supa.swift`의 `SupabaseConfig.url`
- `anon` `public` key → `SupabaseConfig.anonKey`

```swift
enum SupabaseConfig {
    static let url = URL(string: "https://xxxx.supabase.co")!
    static let anonKey = "eyJhbGciOi..."   // anon key (공개돼도 안전 — RLS가 접근 제어)
    static let redirectURL = URL(string: "app.kilog://auth-callback")!
}
```

⚠️ `service_role` 키는 **절대 앱에 넣지 마세요.** RLS를 전부 우회하는 관리자 키입니다.

## 5. 동작 확인 체크리스트

앱 실행 후 순서대로:

- [ ] 이메일 가입 → Table Editor의 `users`/`profiles`에 행 자동 생성 (트리거)
- [ ] 그룹 만들기 → `groups`·`group_members`·`group_invites`(해시)·`sharing_preferences` 생성
- [ ] 초대 링크 복사 → 두 번째 계정으로 코드 입력 → 미리보기 → 수락 → 멤버 2명
- [ ] 클립 촬영(꾹 눌러 최대 5초) → Storage `clips/<group>/<user>/`에 mp4 업로드 + `clips` 행
- [ ] 음식/운동 태그 → `food_logs`/`workout_logs`에 `clip_id`와 함께 저장
- [ ] 인바디 스캔 → `body_measurements` 생성, `profiles` 수치 자동 갱신
- [ ] 상대 기기에서 몇 초 내 클립 자동 반영 (Realtime)

## 6. 운영 팁

- **스키마 변경**: `backend/supabase/migrations/`에 새 파일 추가 → `supabase db push`.
  대시보드에서 직접 고치지 말고 항상 마이그레이션 파일로 (이력 관리)
- **RLS 점검**: SQL Editor에서
  `select * from pg_policies where schemaname = 'public';` 로 전체 정책 확인
- **무료 플랜 한도**: DB 500MB · Storage 1GB · 월 5GB 전송. 영상 앱이라 Storage가 먼저 참 —
  클립 업로드 전 압축(H.264, 720p면 충분)을 유지하고, 필요 시 Pro($25/월)로
- **초대 도메인**: `kilog.app` 도메인을 실제로 사면 Universal Link를 붙여 웹 초대 → 앱 자동 열기가 가능.
  그 전까지는 앱에서 "초대 코드 입력"으로 동일하게 동작

## 7. 클립 자동 정리 (7일 보존)

`20260720000700` 마이그레이션이 매일 03:17(UTC)에 7일 지난 클립의 영상 파일과
클립 행을 삭제하는 `purge_expired_clips()`를 pg_cron으로 등록합니다.
식사/운동 기록은 보존되므로 칼로리 통계는 유지돼요.

- pg_cron이 자동 활성화되지 않았다면: 대시보드 → **Database → Extensions**에서
  `pg_cron` 검색 → Enable 후 마이그레이션을 다시 push (또는 SQL Editor에서 do 블록만 재실행)
- 등록 확인: SQL Editor에서 `select * from cron.job;`
- 수동 실행: `select public.purge_expired_clips(7);`
