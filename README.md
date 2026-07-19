# sal—log

커플로 시작해 친구들까지 — 같이 기록하고 같이 확인하는 다이어트 브이로그 앱.

React 프로토타입(`sal-log-v8-auth-groups.jsx`)을 기반으로 **백엔드(Supabase)** 와
**프론트엔드(SwiftUI iOS)** 를 분리 구현했습니다.

```
sal_log/
├── backend/    Supabase — Postgres 스키마·RLS·RPC·Storage·Realtime (SQL 마이그레이션)
├── frontend/   SwiftUI iOS 앱 (XcodeGen 프로젝트, Supabase Swift SDK)
└── sal-log-v8-auth-groups.jsx   원본 React 프로토타입 (참고용)
```

## 주요 기능

- **인증·그룹**: 이메일/Apple/Google/Kakao 로그인, 서버 발급 만료형 초대 토큰(해시 저장)으로 그룹 참여, 커플→친구 그룹 확장
- **오늘**: 위(나)/아래(파트너) 2트랙 연속 브이로그 재생, 최대 6초 클립 촬영, 음식/운동 태그 (MET 자동 칼로리)
- **바디**: Vision OCR로 인바디 검사지 스캔 → 체중·골격근량·체지방률 추출, Katch-McArdle BMR, Swift Charts 추이
- **코치**: 오늘 자극 부위 분석 → 내일 운동 추천, 칼로리 수지 기반 식단 추천
- **내보내기**: AVFoundation 합성으로 인트로/아웃트로 포함 16:9 브이로그 mp4 생성·공유
- **프라이버시**: 신체 데이터는 항목별 공유 동의 + RLS로 서버에서 차단

시작 방법은 [`backend/README.md`](backend/README.md), [`frontend/README.md`](frontend/README.md) 참고.
