-- ═══════════════════════════════════════════════════════════
-- 호스티드 Supabase는 SQL로 storage.objects를 직접 DELETE하는 것을 막는다
-- ("Direct deletion from storage tables is not allowed"). 따라서 삭제 함수들은
-- DB 행만 지우고, 실제 스토리지 파일은 클라이언트가 Storage API로 정리한다.
--
--  · archive_day_clips  : clips 행만 삭제 (기존엔 storage.objects도 지워 실패했음)
--  · purge_expired_reels: day_reels 행만 삭제
--  · purge_expired_clips: clips 행만 삭제
-- ═══════════════════════════════════════════════════════════

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

  delete from clips c
   where c.group_id = p_group_id
     and c.recorded_at >= p_start and c.recorded_at < p_end;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.archive_day_clips(uuid, date, timestamptz, timestamptz)
  from anon;

create or replace function public.purge_expired_reels(p_keep_days int default 7)
returns int
language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  delete from day_reels where reel_date < current_date - p_keep_days;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.purge_expired_reels(int) from public, anon, authenticated;

create or replace function public.purge_expired_clips(p_keep_days int default 7)
returns int
language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  delete from clips where recorded_at < now() - make_interval(days => p_keep_days);
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.purge_expired_clips(int) from public, anon, authenticated;
