-- ═══════════════════════════════════════════════════════════
-- sal-log · 초기 스키마
--
-- 추천 데이터 구조 기반:
--   users / profiles / groups / group_members / group_invites
--   sharing_preferences / clips / food_logs / workout_logs
--   body_measurements
--
-- 앱 기능상 추가된 컬럼(최소한):
--   · profiles.sex, age, activity_factor  → BMR(Katch-McArdle/Mifflin)·TDEE 계산
--   · group_members.color_hex             → 멤버 컬러(UI)
--   · food_logs/workout_logs.clip_id      → 클립에 태그된 기록 연결
-- ═══════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- ── enum ──────────────────────────────────────────────────
create type public.group_type        as enum ('couple', 'friends');
create type public.member_role       as enum ('owner', 'member');
create type public.member_status     as enum ('active', 'pending', 'left');
create type public.profile_visibility as enum ('private', 'members');
create type public.clip_status       as enum ('uploading', 'ready', 'failed');

-- ── users (auth.users 1:1 공개 신원) ──────────────────────
create table public.users (
  id         uuid primary key references auth.users (id) on delete cascade,
  nickname   text not null default '' check (char_length(nickname) <= 12),
  avatar_url text,
  created_at timestamptz not null default now()
);

-- ── profiles (신체 프로필 · 민감 데이터) ───────────────────
create table public.profiles (
  user_id         uuid primary key references public.users (id) on delete cascade,
  height          numeric(5, 1) check (height between 80 and 250),          -- cm
  weight          numeric(5, 1) check (weight between 20 and 300),          -- kg
  body_fat        numeric(4, 1) check (body_fat between 1 and 70),          -- %
  skeletal_muscle numeric(5, 1) check (skeletal_muscle between 5 and 80),   -- kg
  visibility      public.profile_visibility not null default 'private',
  -- 대사량 계산용 추가 필드
  sex             text check (sex in ('M', 'F')),
  age             int check (age between 1 and 120),
  activity_factor numeric(3, 2) not null default 1.38 check (activity_factor between 1.0 and 2.5),
  updated_at      timestamptz not null default now()
);

-- ── groups ────────────────────────────────────────────────
create table public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 30),
  type        public.group_type not null default 'couple',
  owner_id    uuid not null references public.users (id) on delete cascade,
  max_members int not null default 2 check (max_members between 2 and 12),
  created_at  timestamptz not null default now()
);

create table public.group_members (
  group_id  uuid not null references public.groups (id) on delete cascade,
  user_id   uuid not null references public.users (id) on delete cascade,
  role      public.member_role   not null default 'member',
  status    public.member_status not null default 'active',
  color_hex text not null default '#FF7A9E' check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index group_members_user_idx on public.group_members (user_id) where status = 'active';

-- ── group_invites (해시 저장 · 원문 토큰은 발급 시 1회만 반환) ──
create table public.group_invites (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references public.groups (id) on delete cascade,
  token_hash text not null unique,           -- sha256(upper(token))
  invited_by uuid not null references public.users (id) on delete cascade,
  expires_at timestamptz not null default now() + interval '7 days',
  max_uses   int not null default 10 check (max_uses between 1 and 50),
  used_count int not null default 0,
  revoked_at timestamptz
);

create index group_invites_group_idx on public.group_invites (group_id) where revoked_at is null;

-- ── sharing_preferences (그룹별 · 항목별 공유 동의) ────────
create table public.sharing_preferences (
  group_id              uuid not null references public.groups (id) on delete cascade,
  user_id               uuid not null references public.users (id) on delete cascade,
  share_body            boolean not null default false,  -- 골격근·인바디 전체
  share_weight          boolean not null default false,
  share_body_fat        boolean not null default false,
  share_food            boolean not null default true,
  share_workout         boolean not null default true,
  share_calorie_balance boolean not null default true,
  primary key (group_id, user_id)
);

-- ── clips (브이로그 한 컷 · 영상 메타) ─────────────────────
create table public.clips (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.users (id) on delete cascade,
  group_id          uuid not null references public.groups (id) on delete cascade,
  video_key         text,                    -- storage 'clips' 버킷 키 (group/user/uuid.mp4)
  thumbnail_key     text,
  caption           text not null default '' check (char_length(caption) <= 40),
  recorded_at       timestamptz not null default now(),
  processing_status public.clip_status not null default 'uploading'
);

create index clips_group_time_idx on public.clips (group_id, recorded_at);

-- ── food_logs / workout_logs ──────────────────────────────
create table public.food_logs (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references public.users (id) on delete cascade,
  group_id  uuid not null references public.groups (id) on delete cascade,
  clip_id   uuid references public.clips (id) on delete set null,
  food_name text not null,
  calories  int not null check (calories between 0 and 5000),
  logged_at timestamptz not null default now()
);

create index food_logs_group_time_idx on public.food_logs (group_id, logged_at);

create table public.workout_logs (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.users (id) on delete cascade,
  group_id         uuid not null references public.groups (id) on delete cascade,
  clip_id          uuid references public.clips (id) on delete set null,
  exercise_name    text not null,
  calories         int not null check (calories between 0 and 5000),
  duration_minutes int not null check (duration_minutes between 1 and 600),
  body_part        text,
  logged_at        timestamptz not null default now()
);

create index workout_logs_group_time_idx on public.workout_logs (group_id, logged_at);

-- ── body_measurements (인바디 이력) ───────────────────────
create table public.body_measurements (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.users (id) on delete cascade,
  weight          numeric(5, 1) not null check (weight between 20 and 300),
  body_fat        numeric(4, 1) check (body_fat between 1 and 70),
  skeletal_muscle numeric(5, 1) check (skeletal_muscle between 5 and 80),
  measured_at     timestamptz not null default now()
);

create index body_measurements_user_idx on public.body_measurements (user_id, measured_at);

-- ── 운동 MET · 음식 카탈로그 (2011 Compendium 기반) ────────
create table public.exercise_catalog (
  id        serial primary key,
  name      text not null unique,
  met       numeric(4, 1) not null,
  body_part text not null,
  sort      int not null default 0
);

create table public.food_catalog (
  id   serial primary key,
  name text not null unique,
  kcal int not null,
  sort int not null default 0
);

insert into public.exercise_catalog (name, met, body_part, sort) values
  ('걷기 (보통)',    3.5,  '유산소', 1),
  ('걷기 (빠르게)',  4.3,  '유산소', 2),
  ('러닝 8km/h',     8.3,  '유산소', 3),
  ('러닝 10km/h',    9.8,  '유산소', 4),
  ('자전거',         7.5,  '하체',   5),
  ('실내 사이클',    6.8,  '하체',   6),
  ('웨이트 (보통)',  3.5,  '상체',   7),
  ('웨이트 (고강도)', 6.0, '상체',   8),
  ('스쿼트·런지',    5.0,  '하체',   9),
  ('수영 (자유형)',  5.8,  '전신',  10),
  ('요가',           2.5,  '코어',  11),
  ('필라테스',       3.0,  '코어',  12),
  ('등산',           6.0,  '하체',  13),
  ('계단 오르기',    4.0,  '하체',  14),
  ('줄넘기',        11.8,  '유산소', 15),
  ('홈트 (맨몸)',    3.8,  '전신',  16),
  ('플랭크·복근',    3.8,  '코어',  17),
  ('배드민턴',       5.5,  '전신',  18);

insert into public.food_catalog (name, kcal, sort) values
  ('샐러드',          250, 1),
  ('아메리카노',        5, 2),
  ('편의점 도시락',   650, 3),
  ('라면',            550, 4),
  ('마라탕',          950, 5),
  ('삼겹살 1인분',    600, 6),
  ('치킨 반 마리',    800, 7),
  ('김밥 한 줄',      480, 8),
  ('과자 한 봉',      320, 9);

-- ── 트리거 ────────────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- 가입 시 users + profiles 자동 생성 (nickname은 회원가입 메타데이터에서)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.users (id, nickname, avatar_url)
  values (
    new.id,
    coalesce(left(new.raw_user_meta_data ->> 'nickname', 12), ''),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;

  insert into public.profiles (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 인바디 기록 추가 시 최신 값이면 profiles에 반영
create or replace function public.sync_profile_from_measurement()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
     set weight          = new.weight,
         body_fat        = coalesce(new.body_fat, body_fat),
         skeletal_muscle = coalesce(new.skeletal_muscle, skeletal_muscle)
   where user_id = new.user_id
     and not exists (
       select 1 from public.body_measurements b
        where b.user_id = new.user_id and b.measured_at > new.measured_at
     );
  return new;
end $$;

create trigger body_measurement_sync
  after insert on public.body_measurements
  for each row execute function public.sync_profile_from_measurement();
