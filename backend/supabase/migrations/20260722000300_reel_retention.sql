-- ═══════════════════════════════════════════════════════════
-- 하루 합성본(day_reels) 보존 기간(7일) 자동 정리
--
--  · reel_date 기준 7일 지난 합성본: reels storage 영상 + day_reels 행 삭제
--  · food/workout 로그는 이미 clip_id set null 로 보존되므로 통계엔 영향 없음
--  · pg_cron으로 매일 03:31(UTC) 실행. pg_cron이 없으면 스케줄만 건너뜀
--    (함수는 수동/클라이언트에서 호출 가능)
-- ═══════════════════════════════════════════════════════════

create or replace function public.purge_expired_reels(p_keep_days int default 7)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_cutoff date := current_date - p_keep_days;
  v_count  int;
begin
  delete from storage.objects o
   where o.bucket_id = 'reels'
     and o.name in (
       select r.video_key from day_reels r
        where r.reel_date < v_cutoff and r.video_key is not null
     );

  delete from day_reels where reel_date < v_cutoff;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.purge_expired_reels(int) from public, anon, authenticated;

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule(
    'purge-expired-reels', '31 3 * * *',
    $cron$ select public.purge_expired_reels(7); $cron$
  );
exception when others then
  raise notice 'pg_cron 미사용 환경 — reel purge 스케줄 등록 건너뜀';
end $$;
