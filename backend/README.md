# Kilog backend (Supabase)

커플/친구 그룹 다이어트 브이로그 앱 **Kilog**의 백엔드입니다.
Postgres 스키마 + RLS + RPC + Storage 정책 전부가 `supabase/migrations/`에 SQL로 정의되어 있습니다.

> 처음 설정한다면 **[SETUP.md](SETUP.md)** 를 따라 하세요 — 프로젝트 생성부터 앱 연결·동작 확인까지 단계별 가이드입니다.

## 데이터 구조

```
users                 계정 공개 신원 (nickname, avatar_url)          — auth.users 1:1
profiles              신체 프로필 (height/weight/body_fat/skeletal_muscle,
                      visibility, +sex/age/activity_factor)          — 민감 데이터, 본인만 직접 조회
groups                그룹 (couple | friends, max_members 2~12)
group_members         멤버십 (role, status, color_hex)
group_invites         초대 토큰 — sha256 해시만 저장, 만료·사용횟수 제한, 폐기 가능
sharing_preferences   그룹별·항목별 공유 동의 (body/weight/body_fat/food/workout/balance)
clips                 브이로그 클립 (video_key/thumbnail_key → storage, processing_status)
food_logs             식사 기록 (calories, clip_id로 클립과 연결 가능)
workout_logs          운동 기록 (calories, duration, body_part)
body_measurements     인바디 이력 (weight/body_fat/skeletal_muscle, measured_at)
exercise_catalog      운동 MET 카탈로그 (2011 Compendium 기반, 시드 포함)
food_catalog          음식 칼로리 카탈로그 (시드 포함)
```

## 마이그레이션

| 파일 | 내용 |
|---|---|
| `20260719000100_init.sql` | 테이블·enum·인덱스·카탈로그 시드·트리거 (`handle_new_user`, 인바디→프로필 동기화) |
| `20260719000200_rls.sql` | 전 테이블 RLS. 신체 데이터는 본인 + 동의 기반, 로그는 항목별 공유 동의 검사 |
| `20260719000300_rpc.sql` | `create_group` `create_invite` `preview_invite` `accept_invite` `expand_group` `leave_group` `get_bootstrap` |
| `20260719000400_storage_realtime.sql` | `clips`/`inbody` 버킷 + 경로 기반 정책, Realtime publication |

## 보안 설계 요점

- **초대 토큰은 해시로만 저장** (`sha256(upper(token))`). 원문 `KL-XXXXXX` 토큰은
  `create_group`/`create_invite` 응답에서 1회만 반환되며, 만료(기본 7일)·사용 횟수 제한·폐기(`revoked_at`)를
  전부 서버에서 검증합니다. 수락은 `accept_invite` RPC가 정원 검사와 함께 원자적으로 처리합니다.
- **신체 데이터 접근은 2중 게이트**: `profiles.visibility = 'members'` **그리고**
  `sharing_preferences`의 항목별 플래그가 모두 true일 때만 `get_bootstrap`이 해당 항목을 내려보냅니다.
  `profiles`/`body_measurements` 테이블 자체는 본인 외 select 불가.
- **식사/운동 로그**는 RLS에서 작성자의 `share_food`/`share_workout` 동의를 행 단위로 검사합니다.
- **Storage**: `clips/<group_id>/<user_id>/...` 경로 규칙을 정책으로 강제 — 업로드는 본인 폴더에만,
  조회는 그룹 멤버만. 재생·표시는 signed URL로만 합니다.
- `is_member` 등 helper는 `security definer`로 정의해 RLS 정책 재귀를 방지했습니다.

## 로컬 실행

```bash
brew install supabase/tap/supabase   # 또는 npx supabase
cd backend
supabase start                       # 로컬 스택 기동
supabase db reset                    # migrations 적용 + 시드
```

## 프로덕션 배포

```bash
supabase link --project-ref <PROJECT_REF>
supabase db push
```

이후 대시보드에서:
1. **Auth → Providers**: Apple / Google / Kakao 활성화 (client id·secret 입력)
2. **Auth → URL Configuration**: redirect URL에 `app.kilog://auth-callback` 추가
3. 프론트엔드 `SupabaseConfig.swift`에 Project URL + anon key 입력

## 클라이언트 호출 흐름

```
가입     auth.signUp(email, password, data: {nickname})
          → 트리거가 users + profiles 행 생성
부트스트랩 rpc('get_bootstrap') → user/profile/group/members(동의 반영)/invite
그룹 생성 rpc('create_group', {p_name, p_type}) → invite_token (이때만 원문 노출)
초대 확인 rpc('preview_invite', {p_token})
초대 수락 rpc('accept_invite', {p_token})
클립 저장 storage.upload('clips', 'gid/uid/uuid.mp4') → insert clips(ready)
          → 태그가 있으면 food_logs / workout_logs에 clip_id와 함께 insert
실시간    channel: postgres_changes(clips|food_logs|workout_logs where group_id)
```
