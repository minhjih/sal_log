-- ═══════════════════════════════════════════════════════════
-- 운동별 부하 근육 분포 (muscle_loads jsonb)
--
-- 부위(상체/하체/코어)만으로는 부하가 안 보이므로, 운동마다
-- 세부 근육별 부하 비율(합=1.0)을 시드한다:
--   가슴 / 등 / 어깨 / 팔 / 복근 / 둔근 / 대퇴 / 햄스트링 / 종아리
-- workout_logs에도 기록 시점 분포를 저장해 인체 모형 비교에 사용.
-- 운동생리학 일반 통념 기반의 근사치이며 참고용.
-- ═══════════════════════════════════════════════════════════

alter table public.exercise_catalog
  add column if not exists muscle_loads jsonb not null default '{}'::jsonb;

alter table public.workout_logs
  add column if not exists muscle_loads jsonb;

-- ── 웨이트: 가슴 ──────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"가슴":0.6,"어깨":0.2,"팔":0.2}' where name in
  ('벤치프레스','덤벨 벤치프레스','인클라인 벤치프레스','체스트프레스 머신','푸시업');
update public.exercise_catalog set muscle_loads =
  '{"가슴":0.5,"팔":0.35,"어깨":0.15}' where name = '딥스';
update public.exercise_catalog set muscle_loads =
  '{"가슴":0.85,"어깨":0.15}' where name in ('펙덱 플라이','케이블 크로스오버');

-- ── 웨이트: 등 ────────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"등":0.65,"팔":0.25,"어깨":0.1}' where name in
  ('렛풀다운','어시스트 풀업','풀업·턱걸이');
update public.exercise_catalog set muscle_loads =
  '{"등":0.6,"팔":0.2,"어깨":0.2}' where name in
  ('시티드 로우','바벨 로우','덤벨 로우','티바 로우');
update public.exercise_catalog set muscle_loads =
  '{"햄스트링":0.4,"둔근":0.3,"등":0.3}' where name in
  ('데드리프트','루마니안 데드리프트');

-- ── 웨이트: 어깨 ──────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"어깨":0.6,"팔":0.3,"가슴":0.1}' where name in
  ('오버헤드프레스','덤벨 숄더프레스');
update public.exercise_catalog set muscle_loads =
  '{"어깨":0.9,"팔":0.1}' where name in
  ('사이드 레터럴 레이즈','프론트 레이즈','리어델트 플라이','페이스풀');
update public.exercise_catalog set muscle_loads =
  '{"어깨":0.6,"등":0.4}' where name = '슈러그';

-- ── 웨이트: 팔 ────────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"팔":1.0}' where name in
  ('바벨 컬','덤벨 컬','해머 컬','케이블 푸시다운','라잉 트라이셉스');

-- ── 웨이트: 하체 ──────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.5,"둔근":0.3,"햄스트링":0.1,"복근":0.1}' where name in
  ('바벨 스쿼트','프론트 스쿼트','고블릿 스쿼트','스미스머신 스쿼트',
   '맨몸 스쿼트','스쿼트·런지');
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.45,"둔근":0.35,"햄스트링":0.2}' where name in
  ('덤벨 런지','불가리안 스플릿 스쿼트');
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.6,"둔근":0.3,"햄스트링":0.1}' where name = '레그프레스';
update public.exercise_catalog set muscle_loads =
  '{"대퇴":1.0}' where name = '레그 익스텐션';
update public.exercise_catalog set muscle_loads =
  '{"햄스트링":1.0}' where name = '레그 컬';
update public.exercise_catalog set muscle_loads =
  '{"둔근":0.7,"햄스트링":0.3}' where name = '힙 쓰러스트';
update public.exercise_catalog set muscle_loads =
  '{"둔근":1.0}' where name = '힙 어브덕션';
update public.exercise_catalog set muscle_loads =
  '{"종아리":1.0}' where name = '카프 레이즈';

-- ── 코어 ──────────────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"복근":1.0}' where name in
  ('크런치','레그 레이즈','케이블 크런치','러시안 트위스트');
update public.exercise_catalog set muscle_loads =
  '{"복근":0.8,"어깨":0.2}' where name in ('AB 롤아웃','플랭크·복근');
update public.exercise_catalog set muscle_loads =
  '{"복근":0.8,"둔근":0.2}' where name = '훌라후프';
update public.exercise_catalog set muscle_loads =
  '{"복근":0.5,"둔근":0.2,"햄스트링":0.15,"어깨":0.15}' where name in
  ('요가','빈야사 요가','핫요가','필라테스','스트레칭','폼롤러·마사지');

-- ── 전신 웨이트/맨몸 ──────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"둔근":0.3,"햄스트링":0.2,"어깨":0.2,"복근":0.15,"대퇴":0.15}' where name = '케틀벨';
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.3,"가슴":0.25,"복근":0.25,"어깨":0.2}' where name = '버피';
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.25,"복근":0.2,"가슴":0.15,"등":0.15,"어깨":0.15,"둔근":0.1}' where name in
  ('크로스핏 (WOD)','HIIT','서킷 트레이닝','홈트 (맨몸)');

-- ── 유산소: 달리기/걷기 계열 ──────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.4,"종아리":0.3,"햄스트링":0.2,"둔근":0.1}' where name in
  ('걷기 (보통)','걷기 (빠르게)','러닝 6.4km/h (조깅)','러닝 8km/h','러닝 10km/h',
   '러닝 11.3km/h','러닝 12.9km/h','트레일 러닝','파워 워킹','산책 (느긋하게)',
   '트레드밀 인클라인 걷기','장보기','반려견 산책');

-- ── 유산소: 자전거/머신 ───────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.5,"둔근":0.2,"종아리":0.2,"햄스트링":0.1}' where name in
  ('자전거','실내 사이클','자전거 출퇴근','로드 사이클 (빠르게)','산악자전거',
   '스피닝 클래스','일립티컬');
update public.exercise_catalog set muscle_loads =
  '{"등":0.4,"대퇴":0.25,"팔":0.2,"복근":0.15}' where name in
  ('로잉머신 (보통)','로잉머신 (고강도)');
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.4,"둔근":0.3,"종아리":0.2,"햄스트링":0.1}' where name in
  ('계단머신 (스텝밀)','계단 오르기','등산','백패킹');

-- ── 수영 ──────────────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"등":0.35,"어깨":0.3,"팔":0.15,"복근":0.1,"대퇴":0.1}' where name in
  ('수영 (자유형)','수영 자유형 (빠르게)','수영 배영');
update public.exercise_catalog set muscle_loads =
  '{"가슴":0.3,"대퇴":0.3,"어깨":0.2,"팔":0.2}' where name = '수영 평영';
update public.exercise_catalog set muscle_loads =
  '{"등":0.3,"어깨":0.3,"가슴":0.2,"복근":0.2}' where name = '수영 접영';
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.3,"어깨":0.25,"복근":0.25,"팔":0.2}' where name = '아쿠아로빅';

-- ── 점프/댄스 ─────────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"종아리":0.5,"대퇴":0.3,"어깨":0.1,"복근":0.1}' where name in
  ('줄넘기','트램펄린');
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.35,"종아리":0.25,"복근":0.2,"둔근":0.2}' where name in
  ('발레','방송댄스','줌바','스윙댄스','사교댄스');
update public.exercise_catalog set muscle_loads =
  '{"팔":0.3,"등":0.25,"복근":0.25,"대퇴":0.2}' where name = '폴댄스';
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.4,"둔근":0.3,"복근":0.2,"종아리":0.1}' where name = '바레';

-- ── 구기/라켓 ─────────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.4,"종아리":0.25,"햄스트링":0.2,"둔근":0.15}' where name in
  ('축구','풋살');
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.35,"종아리":0.25,"어깨":0.2,"복근":0.2}' where name = '농구';
update public.exercise_catalog set muscle_loads =
  '{"어깨":0.3,"대퇴":0.3,"종아리":0.2,"팔":0.2}' where name = '배구';
update public.exercise_catalog set muscle_loads =
  '{"팔":0.3,"어깨":0.25,"대퇴":0.25,"종아리":0.2}' where name in
  ('테니스 (단식)','테니스 (복식)','탁구','배드민턴');
update public.exercise_catalog set muscle_loads =
  '{"팔":0.3,"어깨":0.3,"복근":0.2,"대퇴":0.2}' where name = '야구·캐치볼';
update public.exercise_catalog set muscle_loads =
  '{"복근":0.3,"등":0.25,"어깨":0.25,"팔":0.2}' where name in
  ('골프 (라운딩·걷기)','스크린골프·연습장');
update public.exercise_catalog set muscle_loads =
  '{"팔":0.4,"어깨":0.3,"대퇴":0.3}' where name = '볼링';

-- ── 격투기 ────────────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"어깨":0.3,"팔":0.25,"복근":0.25,"대퇴":0.2}' where name in
  ('복싱 (샌드백)','복싱 (스파링)','킥복싱·카디오복싱');
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.3,"복근":0.25,"어깨":0.15,"등":0.15,"둔근":0.15}' where name in
  ('태권도·무술','주짓수');
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.4,"팔":0.25,"어깨":0.2,"복근":0.15}' where name = '펜싱';

-- ── 아웃도어 ──────────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"등":0.35,"팔":0.3,"복근":0.2,"대퇴":0.15}' where name = '클라이밍·볼더링';
update public.exercise_catalog set muscle_loads =
  '{"등":0.35,"어깨":0.3,"팔":0.2,"복근":0.15}' where name in ('카약·패들링','낚시');
update public.exercise_catalog set muscle_loads =
  '{"복근":0.35,"어깨":0.25,"등":0.2,"대퇴":0.2}' where name in
  ('패들보드 (SUP)','서핑');
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.45,"둔근":0.25,"복근":0.15,"종아리":0.15}' where name in
  ('스키','스노보드','아이스 스케이트','인라인 스케이트');
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.4,"복근":0.3,"둔근":0.3}' where name = '승마';

-- ── 일상 활동 ─────────────────────────────────────────────
update public.exercise_catalog set muscle_loads =
  '{"팔":0.3,"등":0.25,"대퇴":0.25,"어깨":0.2}' where name in
  ('집안일·청소','대청소','정원 가꾸기','세차','이사·짐 나르기');
update public.exercise_catalog set muscle_loads =
  '{"대퇴":0.35,"복근":0.25,"팔":0.2,"등":0.2}' where name = '아이와 놀기 (활동적)';

-- ── 남은 항목: 큰 부위 기반 기본 분포 ─────────────────────
update public.exercise_catalog set muscle_loads = case body_part
    when '유산소' then '{"대퇴":0.4,"종아리":0.3,"햄스트링":0.2,"둔근":0.1}'::jsonb
    when '하체'   then '{"대퇴":0.5,"둔근":0.3,"햄스트링":0.2}'::jsonb
    when '상체'   then '{"가슴":0.3,"등":0.3,"어깨":0.2,"팔":0.2}'::jsonb
    when '코어'   then '{"복근":1.0}'::jsonb
    else '{"대퇴":0.2,"가슴":0.15,"등":0.15,"어깨":0.15,"복근":0.2,"둔근":0.15}'::jsonb
  end
 where muscle_loads = '{}'::jsonb;
