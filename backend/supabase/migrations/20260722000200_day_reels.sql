-- ═══════════════════════════════════════════════════════════
-- 하루 합성본(day_reels)
--
--  · 지난 날짜의 개별 클립들은 클라이언트가 하나의 세로 브이로그로 합성해
--    'reels' 버킷에 올리고, 여기에 그룹·날짜당 한 행으로 기록한다.
--  · 합성본이 확정(ready)되면 그날의 개별 클립(영상+행)은 삭제한다.
--    (food/workout 로그는 clip_id on delete set null 로 보존 → 통계 유지)
--  · unique(group_id, reel_date)로 두 멤버가 같은 날을 중복 합성하지 않게 한다.
--    먼저 'building' 행을 넣는 쪽이 그날을 맡고, 나머지는 insert 충돌로 건너뜀.
-- ═══════════════════════════════════════════════════════════

create table public.day_reels (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.groups (id) on delete cascade,
  reel_date   date not null,
  video_key   text,
  status      text not null default 'building' check (status in ('building', 'ready')),
  created_by  uuid references public.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (group_id, reel_date)
);

create index day_reels_group_date_idx on public.day_reels (group_id, reel_date desc);

alter table public.day_reels enable row level security;

create policy "reels: member select" on public.day_reels
  for select using (public.is_member(group_id, auth.uid()));

create policy "reels: member insert" on public.day_reels
  for insert with check (
    public.is_member(group_id, auth.uid()) and created_by = auth.uid()
  );

create policy "reels: member update" on public.day_reels
  for update using (public.is_member(group_id, auth.uid()));

create policy "reels: member delete" on public.day_reels
  for delete using (public.is_member(group_id, auth.uid()));

-- ── reels 스토리지 버킷 (경로: <group_id>/<reel_date>.mp4) ──
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('reels', 'reels', false, 209715200, array['video/mp4'])
on conflict (id) do nothing;

create policy "reels storage: member read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'reels'
    and public.is_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

create policy "reels storage: member write" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'reels'
    and public.is_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

create policy "reels storage: member delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'reels'
    and public.is_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

-- ── 합성 완료된 날의 개별 클립 일괄 삭제 ──────────────────
-- RLS상 클립 삭제는 본인 것만 가능하므로, 합성을 맡은 멤버가 상대방 클립까지
-- 지울 수 있도록 security definer로 처리. 반드시 그날 ready 릴이 있을 때만
-- 삭제하고(안전장치), 로그(food/workout)는 clip_id on delete set null 로 보존.
create or replace function public.archive_day_clips(
  p_group_id uuid, p_date date, p_start timestamptz, p_end timestamptz
) returns int
language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if not public.is_member(p_group_id, auth.uid()) then
    raise exception 'NOT_MEMBER';
  end if;
  if not exists (
    select 1 from day_reels
     where group_id = p_group_id and reel_date = p_date
       and status = 'ready' and video_key is not null
  ) then
    raise exception 'NO_READY_REEL';
  end if;

  delete from storage.objects o
   where o.bucket_id = 'clips' and o.name in (
     select c.video_key from clips c
      where c.group_id = p_group_id and c.video_key is not null
        and c.recorded_at >= p_start and c.recorded_at < p_end
   );
  delete from clips c
   where c.group_id = p_group_id
     and c.recorded_at >= p_start and c.recorded_at < p_end;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.archive_day_clips(uuid, date, timestamptz, timestamptz)
  from anon;
