-- ═══════════════════════════════════════════════════════════
-- 운동별 입력 방식 구분
--
--  time     : 시간이 중요한 운동 (유산소·요가 등) → 분 슬라이더
--  strength : 무게×횟수×세트가 중요한 운동 (웨이트류) → 세트 입력
-- ═══════════════════════════════════════════════════════════

alter table public.exercise_catalog
  add column if not exists mode text not null default 'time'
  check (mode in ('time', 'strength'));

update public.exercise_catalog set mode = 'strength'
 where name in (
   '웨이트 (보통)', '웨이트 (고강도)', '스쿼트·런지', '맨몸 스쿼트',
   '데드리프트', '레그프레스', '벤치프레스', '풀업·턱걸이',
   '숄더프레스', '케틀벨', '버피'
 );
