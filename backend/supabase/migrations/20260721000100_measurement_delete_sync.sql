-- 측정 기록 삭제 시 profiles 재동기화.
-- 최신 기록을 지우면 프로필에 지워진 값이 남으므로,
-- 남아 있는 가장 최근 측정값으로 다시 맞춘다 (남은 기록이 없으면 null).
create or replace function public.resync_profile_after_measurement_delete()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  latest public.body_measurements%rowtype;
begin
  select * into latest
    from public.body_measurements
   where user_id = old.user_id
   order by measured_at desc
   limit 1;

  update public.profiles
     set weight          = latest.weight,
         body_fat        = latest.body_fat,
         skeletal_muscle = latest.skeletal_muscle
   where user_id = old.user_id;
  return old;
end $$;

create trigger body_measurement_delete_sync
  after delete on public.body_measurements
  for each row execute function public.resync_profile_after_measurement_delete();
