-- ═══════════════════════════════════════════════════════════
-- Storage 정책 수정: 대소문자 문자열 비교 → UUID 타입 비교
--
-- 기존 정책은 (storage.foldername(name))[2] = auth.uid()::text 로
-- 텍스트 비교했는데, iOS의 UUID.uuidString은 대문자이고
-- auth.uid()::text는 소문자라 항상 불일치 → 업로드가 무조건
-- RLS에 걸려 실패했다. UUID로 캐스팅해 비교하면 대소문자와
-- 무관하게 동작한다.
-- ═══════════════════════════════════════════════════════════

drop policy if exists "clips storage: self upload" on storage.objects;
create policy "clips storage: self upload"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'clips'
  and ((storage.foldername(name))[2])::uuid = auth.uid()
  and public.is_member(((storage.foldername(name))[1])::uuid, auth.uid())
);

drop policy if exists "clips storage: self delete" on storage.objects;
create policy "clips storage: self delete"
on storage.objects for delete to authenticated
using (
  bucket_id = 'clips'
  and ((storage.foldername(name))[2])::uuid = auth.uid()
);

drop policy if exists "inbody storage: self all" on storage.objects;
create policy "inbody storage: self all"
on storage.objects for all to authenticated
using (
  bucket_id = 'inbody' and ((storage.foldername(name))[1])::uuid = auth.uid()
)
with check (
  bucket_id = 'inbody' and ((storage.foldername(name))[1])::uuid = auth.uid()
);
