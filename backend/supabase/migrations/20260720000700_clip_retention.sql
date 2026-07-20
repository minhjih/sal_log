-- ═══════════════════════════════════════════════════════════
-- 클립 보존 기간(7일) 자동 정리
--
--  · 7일 지난 클립: storage 영상/썸네일 + clips 행 삭제
--  · food_logs / workout_logs는 clip_id만 null이 되고 보존
--    → 영상은 사라져도 칼로리 통계·이력은 유지
--  · pg_cron으로 매일 03:17(UTC) 실행. pg_cron을 쓸 수 없는
--    환경에서는 스케줄 등록만 건너뛴다(함수는 수동 호출 가능).
-- ═══════════════════════════════════════════════════════════

create or replace function public.purge_expired_clips(p_keep_days int default 7)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_cutoff timestamptz := now() - make_interval(days => p_keep_days);
  v_count  int;
begin
  -- 1) 만료 클립의 storage 객체 제거 (영상 + 썸네일)
  delete from storage.objects o
   where o.bucket_id = 'clips'
     and o.name in (
       select c.video_key from clips c
        where c.recorded_at < v_cutoff and c.video_key is not null
       union all
       select c.thumbnail_key from clips c
        where c.recorded_at < v_cutoff and c.thumbnail_key is not null
     );

  -- 2) 클립 행 삭제 (로그의 clip_id는 FK on delete set null로 보존)
  delete from clips where recorded_at < v_cutoff;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.purge_expired_clips(int) from public, anon, authenticated;

-- 매일 실행 스케줄 (pg_cron이 있는 환경에서만)
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule(
    'purge-expired-clips',
    '17 3 * * *',
    $job$ select public.purge_expired_clips(7) $job$
  );
exception when others then
  raise notice 'pg_cron unavailable, skipping schedule: %', sqlerrm;
end $$;
