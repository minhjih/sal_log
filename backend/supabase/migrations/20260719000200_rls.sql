-- ═══════════════════════════════════════════════════════════
-- sal-log · Row Level Security
--
-- 원칙
--  · users(닉네임·아바타)는 같은 그룹 멤버끼리 조회 가능.
--  · profiles/body_measurements(민감 신체 데이터)는 본인만 직접
--    select. 멤버의 수치는 visibility + sharing_preferences 동의를
--    검사하는 RPC(get_bootstrap)를 통해서만 항목별로 노출.
--  · food/workout_logs는 작성자 본인 + share_food/share_workout에
--    동의한 멤버의 것만 그룹원이 조회.
--  · 쓰기는 항상 본인 행만. 그룹 생성·초대 발급/수락 등 다중 행
--    작업은 security definer RPC로만 수행.
-- ═══════════════════════════════════════════════════════════

-- ── helpers (security definer → RLS 재귀 방지) ─────────────
create or replace function public.is_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members
     where group_id = p_group_id and user_id = p_user_id and status = 'active'
  );
$$;

create or replace function public.shares_group(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select p_a = p_b or exists (
    select 1
      from group_members a
      join group_members b on b.group_id = a.group_id
     where a.user_id = p_a and a.status = 'active'
       and b.user_id = p_b and b.status = 'active'
  );
$$;

revoke all on function public.is_member(uuid, uuid) from anon;
revoke all on function public.shares_group(uuid, uuid) from anon;

-- ── users ─────────────────────────────────────────────────
alter table public.users enable row level security;

create policy "users: self or co-member select" on public.users
  for select using (id = auth.uid() or public.shares_group(auth.uid(), id));

create policy "users: self update" on public.users
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy "users: self insert" on public.users
  for insert with check (id = auth.uid());

-- ── profiles (본인만 직접 접근) ────────────────────────────
alter table public.profiles enable row level security;

create policy "profiles: self select" on public.profiles
  for select using (user_id = auth.uid());

create policy "profiles: self update" on public.profiles
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "profiles: self insert" on public.profiles
  for insert with check (user_id = auth.uid());

-- ── groups ────────────────────────────────────────────────
alter table public.groups enable row level security;

create policy "groups: member select" on public.groups
  for select using (public.is_member(id, auth.uid()));

create policy "groups: owner update" on public.groups
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- 생성은 create_group RPC로만.

-- ── group_members ─────────────────────────────────────────
alter table public.group_members enable row level security;

create policy "members: member select" on public.group_members
  for select using (public.is_member(group_id, auth.uid()));

create policy "members: self update" on public.group_members
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "members: self leave" on public.group_members
  for delete using (user_id = auth.uid() and role <> 'owner');

-- 일반 업데이트 경로에서 role/status 승격 금지.
-- security definer RPC는 함수 소유자 권한(current_user <> 'authenticated')으로
-- 실행되므로 트리거를 통과한다.
create or replace function public.guard_member_update()
returns trigger language plpgsql as $$
begin
  if current_user = 'authenticated'
     and (new.role <> old.role or new.status <> old.status) then
    raise exception 'role/status can only be changed by server functions';
  end if;
  return new;
end $$;

create trigger group_members_guard
  before update on public.group_members
  for each row execute function public.guard_member_update();

-- ── group_invites ─────────────────────────────────────────
alter table public.group_invites enable row level security;

-- 해시만 저장되므로 select를 열어도 토큰 원문은 유출되지 않지만,
-- 메타(만료·사용 횟수)는 멤버에게만 보여준다. 발급/폐기/수락은 전부 RPC.
create policy "invites: member select" on public.group_invites
  for select using (public.is_member(group_id, auth.uid()));

-- ── sharing_preferences ───────────────────────────────────
alter table public.sharing_preferences enable row level security;

create policy "sharing: member select" on public.sharing_preferences
  for select using (public.is_member(group_id, auth.uid()));

create policy "sharing: self upsert" on public.sharing_preferences
  for insert with check (user_id = auth.uid() and public.is_member(group_id, auth.uid()));

create policy "sharing: self update" on public.sharing_preferences
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── clips ─────────────────────────────────────────────────
alter table public.clips enable row level security;

create policy "clips: member select" on public.clips
  for select using (public.is_member(group_id, auth.uid()));

create policy "clips: self insert" on public.clips
  for insert with check (user_id = auth.uid() and public.is_member(group_id, auth.uid()));

create policy "clips: self update" on public.clips
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "clips: self delete" on public.clips
  for delete using (user_id = auth.uid());

-- ── food_logs (본인 + 공유 동의자만) ───────────────────────
alter table public.food_logs enable row level security;

create policy "food: consent select" on public.food_logs
  for select using (
    user_id = auth.uid()
    or (
      public.is_member(group_id, auth.uid())
      and exists (
        select 1 from public.sharing_preferences sp
         where sp.group_id = food_logs.group_id
           and sp.user_id = food_logs.user_id
           and sp.share_food
      )
    )
  );

create policy "food: self insert" on public.food_logs
  for insert with check (user_id = auth.uid() and public.is_member(group_id, auth.uid()));

create policy "food: self update" on public.food_logs
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "food: self delete" on public.food_logs
  for delete using (user_id = auth.uid());

-- ── workout_logs (본인 + 공유 동의자만) ────────────────────
alter table public.workout_logs enable row level security;

create policy "workout: consent select" on public.workout_logs
  for select using (
    user_id = auth.uid()
    or (
      public.is_member(group_id, auth.uid())
      and exists (
        select 1 from public.sharing_preferences sp
         where sp.group_id = workout_logs.group_id
           and sp.user_id = workout_logs.user_id
           and sp.share_workout
      )
    )
  );

create policy "workout: self insert" on public.workout_logs
  for insert with check (user_id = auth.uid() and public.is_member(group_id, auth.uid()));

create policy "workout: self update" on public.workout_logs
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "workout: self delete" on public.workout_logs
  for delete using (user_id = auth.uid());

-- ── body_measurements (본인만 직접 접근 · 공유는 RPC로) ────
alter table public.body_measurements enable row level security;

create policy "body: self select" on public.body_measurements
  for select using (user_id = auth.uid());

create policy "body: self insert" on public.body_measurements
  for insert with check (user_id = auth.uid());

create policy "body: self delete" on public.body_measurements
  for delete using (user_id = auth.uid());

-- ── 카탈로그 (읽기 전용) ──────────────────────────────────
alter table public.exercise_catalog enable row level security;
alter table public.food_catalog enable row level security;

create policy "exercise: read" on public.exercise_catalog
  for select to authenticated using (true);

create policy "food catalog: read" on public.food_catalog
  for select to authenticated using (true);
