import { useState, useRef, useEffect, useMemo } from "react";

/* ═════════════════════════════════════════════════════
   sal-log v6 — 커플 다이어트 브이로그

   · 가로(16:9) 연속 분할 브이로그: 좌(나)/우(애인) 동시 재생
   · 가입 시 인바디 검사지 스캔 → 체중·골격근량·체지방률 자동 인식(데모)
     → 기초대사량(Katch-McArdle)·TDEE 계산에 그대로 사용
   · 바디 탭: 체중/골격근량/체지방률 추이 확인
   · 코치 탭: 오늘 자극한 부위 분석 → 내일 운동 추천(MET 기반 예상 소모),
     오늘 수지 기반 음식 추천
   ═════════════════════════════════════════════════════ */

const C = {
  bg: "#0B0B0F", surface: "#15151B", surface2: "#1D1D25", line: "#26262E",
  text: "#F4F2ED", muted: "#8C8C97", faint: "#55555F",
  me: "#FF7A9E", lover: "#6FC3FF", green: "#7BE3A0",
};
const DUO = `linear-gradient(90deg, ${C.me}, ${C.lover})`;
const MAX_CLIP_SEC = 6;
const DEFAULT_SEG_MS = 3000;
const MAX_SEG_MS = 8000;

const USERS = {
  me: { name: "나", initial: "M", color: C.me },
  lover: { name: "애인", initial: "J", color: C.lover },
};

const INITIAL_GROUP = {
  id: "grp_demo_couple",
  name: "우리의 30일",
  type: "couple", // couple | friends
  inviteCode: "SAL-7K2M9Q",
  inviteUrl: "https://sal-log.app/join/SAL-7K2M9Q",
  ownerId: "me",
  maxMembers: 2,
  members: [
    { userId: "me", name: "민지", initial: "M", role: "owner", status: "active", color: C.me, shareBody: true, shareCoach: true },
    { userId: "lover", name: "준호", initial: "J", role: "member", status: "active", color: C.lover, shareBody: true, shareCoach: true },
  ],
};

const FRIEND_COLORS = [C.me, C.lover, C.green, "#C7A6FF", "#FFD36F", "#87E0D1"];

function makeInviteCode() {
  return `SAL-${Math.random().toString(36).slice(2, 8).toUpperCase()}`;
}


/* ── 운동 MET DB + 자극 부위 (2011 Compendium 기반) ── */
const MET_DB = [
  { name: "걷기 (보통)", met: 3.5, part: "유산소" },
  { name: "걷기 (빠르게)", met: 4.3, part: "유산소" },
  { name: "러닝 8km/h", met: 8.3, part: "유산소" },
  { name: "러닝 10km/h", met: 9.8, part: "유산소" },
  { name: "자전거", met: 7.5, part: "하체" },
  { name: "실내 사이클", met: 6.8, part: "하체" },
  { name: "웨이트 (보통)", met: 3.5, part: "상체" },
  { name: "웨이트 (고강도)", met: 6.0, part: "상체" },
  { name: "스쿼트·런지", met: 5.0, part: "하체" },
  { name: "수영 (자유형)", met: 5.8, part: "전신" },
  { name: "요가", met: 2.5, part: "코어" },
  { name: "필라테스", met: 3.0, part: "코어" },
  { name: "등산", met: 6.0, part: "하체" },
  { name: "계단 오르기", met: 4.0, part: "하체" },
  { name: "줄넘기", met: 11.8, part: "유산소" },
  { name: "홈트 (맨몸)", met: 3.8, part: "전신" },
  { name: "플랭크·복근", met: 3.8, part: "코어" },
  { name: "배드민턴", met: 5.5, part: "전신" },
];
const PARTS = ["하체", "상체", "코어", "유산소"];
const PART_PICK = {
  하체: { ex: "스쿼트·런지", min: 30 },
  상체: { ex: "웨이트 (보통)", min: 40 },
  코어: { ex: "플랭크·복근", min: 20 },
  유산소: { ex: "러닝 8km/h", min: 30 },
};

const FOOD_DB = [
  { name: "샐러드", kcal: 250 }, { name: "아메리카노", kcal: 5 },
  { name: "편의점 도시락", kcal: 650 }, { name: "라면", kcal: 550 },
  { name: "마라탕", kcal: 950 }, { name: "삼겹살 1인분", kcal: 600 },
  { name: "치킨 반 마리", kcal: 800 }, { name: "김밥 한 줄", kcal: 480 },
  { name: "과자 한 봉", kcal: 320 },
];

const FOOD_REC = {
  surplus: {
    why: "오늘 수지가 흑자(+)예요. 내일은 가볍고 단백질 위주로 가볼까요?",
    items: [
      { name: "닭가슴살 샐러드", kcal: 350, note: "단백질 30g" },
      { name: "두부 포케", kcal: 420, note: "포만감 좋고 가벼움" },
      { name: "그릭요거트 볼", kcal: 280, note: "아침 대용 추천" },
    ],
  },
  deficit: {
    why: "오늘 수지가 적자(−)예요. 근손실 방지를 위해 단백질을 챙겨요.",
    items: [
      { name: "연어 스테이크 정식", kcal: 550, note: "오메가3 + 단백질" },
      { name: "소고기 미역국 정식", kcal: 600, note: "회복식으로 좋음" },
      { name: "닭가슴살 리조또", kcal: 520, note: "운동 후 한 끼" },
    ],
  },
};

/* ── 신체 계산 ── */
function calcBMR(p) {
  if (!p.weight) return null;
  if (p.bodyFat != null && p.bodyFat > 0) {
    const lbm = p.weight * (1 - p.bodyFat / 100);
    return Math.round(370 + 21.6 * lbm); // Katch-McArdle (인바디 최적)
  }
  if (!p.height || !p.age) return null;
  const s = p.sex === "M" ? 5 : -161;
  return Math.round(10 * p.weight + 6.25 * p.height - 5 * p.age + s);
}
const calcTDEE = (p) => {
  const b = calcBMR(p);
  return b ? Math.round(b * (p.activity || 1.375)) : null;
};
const metKcal = (met, weight, min) =>
  Math.round((met * 3.5 * (weight || 60)) / 200 * min);

const nowHM = () => {
  const d = new Date();
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
};
const dateLabel = () => {
  const d = new Date();
  const days = ["일", "월", "화", "수", "목", "금", "토"];
  return `${d.getMonth() + 1}.${d.getDate()} ${days[d.getDay()]}`;
};

const INITIAL_PROFILES = {
  me: {
    sex: "F", age: 26, height: 162, weight: 54, smm: 22.0, bodyFat: 24, activity: 1.375,
    history: [
      { d: "5.02", w: 56.1, s: 21.6, f: 26.2 },
      { d: "6.01", w: 55.2, s: 21.8, f: 25.3 },
      { d: "7.01", w: 54.0, s: 22.0, f: 24.0 },
    ],
  },
  lover: {
    sex: "M", age: 27, height: 176, weight: 72, smm: 33.5, bodyFat: 18, activity: 1.375,
    history: [
      { d: "5.02", w: 74.5, s: 32.8, f: 20.1 },
      { d: "6.01", w: 73.2, s: 33.1, f: 19.0 },
      { d: "7.01", w: 72.0, s: 33.5, f: 18.0 },
    ],
  },
};

const INITIAL_CLIPS = [
  { id: 1, user: "lover", videoUrl: null, time: "07:40", caption: "출근 전 한강 러닝", tag: { type: "move", name: "러닝 8km/h", kcal: 302, min: 30, part: "유산소" } },
  { id: 2, user: "me", videoUrl: null, time: "08:12", caption: "아침은 아아로 퉁", tag: { type: "food", name: "아메리카노", kcal: 5 } },
  { id: 3, user: "me", videoUrl: null, time: "12:31", caption: "참을 수 없었다", tag: { type: "food", name: "마라탕", kcal: 950 } },
  { id: 4, user: "lover", videoUrl: null, time: "12:33", caption: "나는 참았다 (도시락)", tag: { type: "food", name: "편의점 도시락", kcal: 650 } },
];

/* ═══════ 타임라인 (연속 하나의 영상) ═══════ */
const toMin = (t) => +t.slice(0, 2) * 60 + +t.slice(3, 5);
function buildSegments(clips) {
  const sorted = [...clips].sort((a, b) => toMin(a.time) - toMin(b.time));
  const segs = [];
  for (const c of sorted) {
    const last = segs[segs.length - 1];
    if (last && !last.clips[c.user] && Math.abs(toMin(last.time) - toMin(c.time)) <= 1)
      last.clips[c.user] = c;
    else segs.push({ time: c.time, clips: { [c.user]: c } });
  }
  return segs;
}
function sideAt(segs, idx, u) {
  for (let i = idx; i >= 0; i--)
    if (segs[i].clips[u]) return { clip: segs[i].clips[u], active: i === idx };
  return { clip: null, active: false };
}
const segDur = (seg, durMap) => {
  let d = 0;
  Object.values(seg.clips).forEach((c) => {
    d = Math.max(d, c.videoUrl ? durMap[c.id] || DEFAULT_SEG_MS : DEFAULT_SEG_MS);
  });
  return Math.min(Math.max(d, 1600), MAX_SEG_MS); // 긴 영상에 맞춤
};

/* ═══════ 가로(16:9) 내보내기 캔버스 ═══════ */
const F = "-apple-system, 'Apple SD Gothic Neo', sans-serif";
const W = 960, H = 540; // landscape
const T_INTRO = 1400, T_OUTRO = 2200;
const ease = (x) => 1 - Math.pow(1 - x, 3);

function rr(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}
function drawCover(ctx, v, x, y, w, h) {
  const vw = v.videoWidth || 16, vh = v.videoHeight || 9;
  const s = Math.max(w / vw, h / vh);
  ctx.save();
  ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip();
  ctx.drawImage(v, x + (w - vw * s) / 2, y + (h - vh * s) / 2, vw * s, vh * s);
  ctx.restore();
}
function wrapText(ctx, text, x, y, maxW, lh) {
  const words = (text || "").split(" ");
  let line = "", yy = y;
  for (const w of words) {
    const t = line ? line + " " + w : w;
    if (ctx.measureText(t).width > maxW && line) { ctx.fillText(line, x, yy); line = w; yy += lh; }
    else line = t;
  }
  ctx.fillText(line, x, yy);
}
function drawIntro(ctx, p) {
  ctx.fillStyle = C.bg; ctx.fillRect(0, 0, W, H);
  const a = ease(Math.min(1, p * 2));
  ctx.globalAlpha = a; ctx.textAlign = "center";
  ctx.fillStyle = C.text; ctx.font = `300 54px ${F}`;
  ctx.fillText("sal—log", W / 2, H / 2 - 16 + (1 - a) * 20);
  const g = ctx.createLinearGradient(W / 2 - 55, 0, W / 2 + 55, 0);
  g.addColorStop(0, C.me); g.addColorStop(1, C.lover);
  ctx.fillStyle = g; ctx.fillRect(W / 2 - 55 * a, H / 2 + 8, 110 * a, 3);
  ctx.fillStyle = C.muted; ctx.font = `500 22px ${F}`;
  ctx.fillText(`${dateLabel()} · 둘이 찍은 하루`, W / 2, H / 2 + 56 + (1 - a) * 20);
  ctx.globalAlpha = 1;
}
function drawSeg(ctx, segs, idx, p, els) {
  const stripH = H / 2; // 위(나) / 아래(애인) — 가로로 넓은 두 줄
  ["me", "lover"].forEach((u, i) => {
    const y0 = i * stripH;
    const { clip, active } = sideAt(segs, idx, u);
    const el = clip && clip.videoUrl && els[clip.id];
    if (el && el.readyState >= 2) {
      drawCover(ctx, el, 0, y0, W, stripH);
      if (!active) { ctx.fillStyle = "rgba(0,0,0,.42)"; ctx.fillRect(0, y0, W, stripH); }
    } else {
      ctx.fillStyle = "#101016"; ctx.fillRect(0, y0, W, stripH);
      ctx.textAlign = "center";
      if (clip) {
        ctx.fillStyle = active ? C.text : C.faint;
        ctx.font = `600 24px ${F}`;
        wrapText(ctx, clip.caption, W / 2, y0 + stripH / 2 + 2, W - 200, 32);
      } else {
        ctx.fillStyle = USERS[u].color; ctx.globalAlpha = 0.22;
        ctx.font = `700 78px ${F}`;
        ctx.fillText(USERS[u].initial, W / 2, y0 + stripH / 2 + 26);
        ctx.globalAlpha = 1;
      }
    }
    // 각 줄 하단 가독성 그라데이션
    const sh = ctx.createLinearGradient(0, y0 + stripH - 78, 0, y0 + stripH);
    sh.addColorStop(0, "rgba(0,0,0,0)"); sh.addColorStop(1, "rgba(0,0,0,.6)");
    ctx.fillStyle = sh; ctx.fillRect(0, y0 + stripH - 78, W, 78);
  });

  // 중앙 가로 이음선 (시그니처: 나→애인 그라데이션)
  const g = ctx.createLinearGradient(0, 0, W, 0);
  g.addColorStop(0, C.me); g.addColorStop(1, C.lover);
  ctx.fillStyle = g; ctx.fillRect(0, stripH - 1.5, W, 3);

  const a = ease(Math.min(1, p * 3));
  ctx.globalAlpha = a;

  // 시간 칩 (상단 중앙)
  ctx.textAlign = "center";
  ctx.fillStyle = "rgba(0,0,0,.45)";
  rr(ctx, W / 2 - 54, 24, 108, 40, 20); ctx.fill();
  ctx.fillStyle = "#FFF"; ctx.font = `600 22px ${F}`;
  ctx.fillText(segs[idx].time, W / 2, 52);

  // 각 줄: 이름(좌하단) · 캡션(중앙 하단) · kcal(우하단)
  ["me", "lover"].forEach((u, i) => {
    const y0 = i * stripH;
    const c = segs[idx].clips[u];
    ctx.textAlign = "left";
    ctx.fillStyle = USERS[u].color; ctx.font = `700 17px ${F}`;
    ctx.fillText(USERS[u].name, 26, y0 + stripH - 22);
    if (!c) return;
    ctx.textAlign = "center";
    ctx.fillStyle = "rgba(255,255,255,.94)"; ctx.font = `500 20px ${F}`;
    ctx.fillText(c.caption || "", W / 2, y0 + stripH - 22);
    if (c.tag) {
      const mv = c.tag.type === "move";
      ctx.textAlign = "right";
      ctx.fillStyle = mv ? C.green : "#FFF";
      ctx.font = `700 20px ${F}`;
      ctx.fillText(`${mv ? "−" : "+"}${c.tag.kcal.toLocaleString()} kcal`, W - 26, y0 + stripH - 22);
    }
  });
  ctx.globalAlpha = 1;
}
function drawOutro(ctx, p, stats) {
  ctx.fillStyle = C.bg; ctx.fillRect(0, 0, W, H);
  const a = ease(Math.min(1, p * 2.2));
  ctx.globalAlpha = a; ctx.textAlign = "center";
  ctx.fillStyle = C.muted; ctx.font = `500 22px ${F}`;
  ctx.fillText("오늘, 우리", W / 2, 120);
  ["me", "lover"].forEach((u, i) => {
    const cx = W / 2 + (i === 0 ? -130 : 130);
    const s = stats[u];
    ctx.fillStyle = C.surface;
    rr(ctx, cx - 110, 160, 220, 220, 22); ctx.fill();
    ctx.fillStyle = USERS[u].color; ctx.font = `600 22px ${F}`;
    ctx.fillText(USERS[u].name, cx, 208);
    ctx.fillStyle = C.text; ctx.font = `300 42px ${F}`;
    ctx.fillText(`${s.balance > 0 ? "+" : ""}${s.balance.toLocaleString()}`, cx, 268);
    ctx.fillStyle = C.muted; ctx.font = `400 17px ${F}`;
    ctx.fillText("kcal 수지", cx, 298);
    ctx.fillText(`섭취 ${s.intake} · 소모 ${s.burnTotal}`, cx, 352);
  });
  const g = ctx.createLinearGradient(W / 2 - 55, 0, W / 2 + 55, 0);
  g.addColorStop(0, C.me); g.addColorStop(1, C.lover);
  ctx.fillStyle = g; ctx.fillRect(W / 2 - 38, 428, 76, 3);
  ctx.fillStyle = C.faint; ctx.font = `500 18px ${F}`;
  ctx.fillText("sal—log · 같은 하루, 같은 다짐", W / 2, 476);
  ctx.globalAlpha = 1;
}

/* ═══════ 인바디 스캔 (데모 OCR) ═══════ */
function ScanFlow({ baseProfile, onDone, onClose, firstTime }) {
  const [step, setStep] = useState("scan"); // scan → analyzing → confirm
  const [imgUrl, setImgUrl] = useState(null);
  const [parsed, setParsed] = useState(null);

  const onUpload = (e) => {
    const f = e.target.files?.[0];
    if (!f) return;
    setImgUrl(URL.createObjectURL(f));
    setStep("analyzing");
    // 데모: 실제 앱에서는 OCR로 검사지의 체중/골격근량/체지방률을 인식
    setTimeout(() => {
      const jit = (v, r) => Math.round((v + (Math.random() * 2 - 1) * r) * 10) / 10;
      setParsed({
        weight: jit(baseProfile.weight || 60, 0.6),
        smm: jit(baseProfile.smm || 25, 0.4),
        bodyFat: jit(baseProfile.bodyFat || 22, 0.8),
      });
      setStep("confirm");
    }, 1800);
  };
  const set = (k, v) => setParsed({ ...parsed, [k]: v === "" ? null : +v });
  const bmrPreview = parsed ? calcBMR({ ...baseProfile, ...parsed }) : null;

  return (
    <div className="overlay center" onClick={firstTime ? undefined : onClose}>
      <div className="scan-card" onClick={(e) => e.stopPropagation()}>
        {step === "scan" && (
          <>
            <div className="scan-title">인바디 검사지 스캔</div>
            <p className="scan-desc">
              검사지 사진을 올리면 체중·골격근량·체지방률을 읽어와<br />
              기초대사량 계산에 바로 사용해요.
            </p>
            <label className="scan-drop">
              <input type="file" accept="image/*" capture="environment" hidden onChange={onUpload} />
              <span className="scan-icon">⌞ ⌝</span>
              <b>검사지 촬영 / 업로드</b>
              <span className="scan-sub">인바디 결과지 전체가 보이게 찍어주세요</span>
            </label>
            <button className="scan-skip" onClick={() => onDone(null)}>
              나중에 할게요 — 직접 입력
            </button>
          </>
        )}

        {step === "analyzing" && (
          <div className="scan-analyzing">
            {imgUrl && <img src={imgUrl} alt="인바디 검사지" className="scan-preview" />}
            <div className="scan-spinner" />
            <b>검사지 읽는 중…</b>
            <span>체중 · 골격근량 · 체지방률 인식</span>
          </div>
        )}

        {step === "confirm" && parsed && (
          <>
            <div className="scan-title">인식 결과 확인</div>
            <p className="scan-desc">숫자가 다르면 바로 수정할 수 있어요.</p>
            <div className="parse-grid">
              {[["weight", "체중", "kg"], ["smm", "골격근량", "kg"], ["bodyFat", "체지방률", "%"]].map(([k, label, unit]) => (
                <label className="parse-field" key={k}>
                  <span>{label}</span>
                  <div>
                    <input type="number" step="0.1" value={parsed[k] ?? ""} onChange={(e) => set(k, e.target.value)} />
                    <em>{unit}</em>
                  </div>
                </label>
              ))}
            </div>
            {bmrPreview && (
              <div className="parse-bmr">
                기초대사량 <b>{bmrPreview.toLocaleString()} kcal</b>
                <span>Katch-McArdle · 제지방량 기반</span>
              </div>
            )}
            <button className="save-btn" onClick={() => onDone(parsed)}>
              {firstTime ? "이 수치로 시작하기" : "저장"}
            </button>
          </>
        )}
      </div>
    </div>
  );
}

/* ═══════ 촬영 플로우 ═══════ */
function CaptureFlow({ user, weight, onSave, onClose }) {
  const [step, setStep] = useState("record");
  const [recording, setRecording] = useState(false);
  const [videoUrl, setVideoUrl] = useState(null);
  const [camError, setCamError] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [caption, setCaption] = useState("");
  const [time, setTime] = useState(nowHM());
  const [tagMode, setTagMode] = useState("none");
  const [move, setMove] = useState(MET_DB[2]);
  const [minutes, setMinutes] = useState(30);
  const [food, setFood] = useState(FOOD_DB[0]);
  const liveRef = useRef(null);
  const streamRef = useRef(null);
  const recRef = useRef(null);
  const timerRef = useRef(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "user" }, audio: false,
        });
        if (cancelled) { stream.getTracks().forEach((t) => t.stop()); return; }
        streamRef.current = stream;
        if (liveRef.current) liveRef.current.srcObject = stream;
      } catch (e) { setCamError(true); }
    })();
    return () => {
      cancelled = true;
      clearInterval(timerRef.current);
      streamRef.current?.getTracks().forEach((t) => t.stop());
    };
  }, []);

  const stopCam = () => {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  };
  const startRec = () => {
    if (!streamRef.current || recording) return;
    const chunks = [];
    const mime = ["video/mp4", "video/webm;codecs=vp9", "video/webm"]
      .find((m) => window.MediaRecorder && MediaRecorder.isTypeSupported(m));
    const rec = new MediaRecorder(streamRef.current, mime ? { mimeType: mime } : undefined);
    rec.ondataavailable = (e) => e.data.size && chunks.push(e.data);
    rec.onstop = () => {
      setVideoUrl(URL.createObjectURL(new Blob(chunks, { type: rec.mimeType })));
      stopCam(); setStep("meta");
    };
    rec.start(); recRef.current = rec;
    setRecording(true); setElapsed(0);
    const t0 = Date.now();
    timerRef.current = setInterval(() => {
      const s = (Date.now() - t0) / 1000;
      setElapsed(s);
      if (s >= MAX_CLIP_SEC) stopRec();
    }, 100);
  };
  const stopRec = () => {
    clearInterval(timerRef.current);
    if (recRef.current?.state === "recording") recRef.current.stop();
    setRecording(false);
  };
  const onUpload = (e) => {
    const f = e.target.files?.[0];
    if (!f) return;
    setVideoUrl(URL.createObjectURL(f));
    stopCam(); setStep("meta");
  };

  const moveKcal = metKcal(move.met, weight, minutes);
  const save = () => {
    let tag = null;
    if (tagMode === "food") tag = { type: "food", name: food.name, kcal: food.kcal };
    if (tagMode === "move") tag = { type: "move", name: move.name, kcal: moveKcal, min: minutes, part: move.part };
    onSave({
      id: Date.now(), user, videoUrl, time,
      caption: caption.trim() || (tag ? tag.name : "지금 이 순간"),
      tag,
    });
  };

  return (
    <div className="overlay" onClick={onClose}>
      <div className="capture" onClick={(e) => e.stopPropagation()}>
        {step === "record" && (
          <>
            <div className="cam-wrap">
              {!camError ? (
                <video ref={liveRef} autoPlay muted playsInline className="cam" />
              ) : (
                <div className="cam cam-off">
                  <p>카메라를 사용할 수 없어요.<br />영상을 올려서 기록해 주세요.</p>
                </div>
              )}
              <div className="cam-hud">
                <span className="cam-hour">{nowHM()}</span>
                <span className="cam-hint">
                  {recording ? `● ${elapsed.toFixed(1)}s / ${MAX_CLIP_SEC}s` : "가로로 눕혀 찍으면 더 예뻐요 · 최대 6초"}
                </span>
              </div>
            </div>
            <div className="cam-bar">
              <label className="cam-side">
                <input type="file" accept="video/*" capture="user" hidden onChange={onUpload} />
                올리기
              </label>
              <button className={"shutter" + (recording ? " on" : "")}
                style={{ "--u": USERS[user].color }}
                onClick={recording ? stopRec : startRec}
                disabled={camError}><span /></button>
              <button className="cam-side" onClick={onClose}>취소</button>
            </div>
          </>
        )}

        {step === "meta" && (
          <div className="meta">
            <video src={videoUrl} autoPlay muted loop playsInline className="meta-video" />
            <div className="meta-panel">
              <div className="meta-row">
                <input className="caption-input" placeholder="한 줄 캡션 (선택)"
                  value={caption} maxLength={24} onChange={(e) => setCaption(e.target.value)} />
                <label className="time-field">
                  <span>영상 시간</span>
                  <input type="time" value={time} onChange={(e) => setTime(e.target.value)} />
                </label>
              </div>
              <div className="tag-toggle">
                {[["none", "그냥 일상"], ["food", "먹었어요"], ["move", "움직였어요"]].map(([v, t]) => (
                  <button key={v} className={tagMode === v ? "on" : ""} onClick={() => setTagMode(v)}>{t}</button>
                ))}
              </div>
              {tagMode === "food" && (
                <div className="chips">
                  {FOOD_DB.map((f) => (
                    <button key={f.name} className={"chip" + (food.name === f.name ? " on" : "")}
                      onClick={() => setFood(f)}>{f.name}<em>+{f.kcal}</em></button>
                  ))}
                </div>
              )}
              {tagMode === "move" && (
                <div className="picker">
                  <div className="chips scrolly">
                    {MET_DB.map((m) => (
                      <button key={m.name} className={"chip" + (move.name === m.name ? " on" : "")}
                        onClick={() => setMove(m)}>{m.name}<em>{m.part}</em></button>
                    ))}
                  </div>
                  <div className="minute-row">
                    <input type="range" min="5" max="120" step="5" value={minutes}
                      onChange={(e) => setMinutes(+e.target.value)} />
                    <span className="minute-val">{minutes}분</span>
                  </div>
                  <div className="auto-calc">
                    <b>−{moveKcal.toLocaleString()} kcal</b> 자동 계산
                    <span>MET {move.met} × {weight}kg × {minutes}분 · Compendium 기반</span>
                  </div>
                </div>
              )}
              <button className="save-btn" onClick={save}>오늘 영상에 넣기</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}


/* ═══════ 인증 · 그룹 가입 플로우 ═══════ */
function AuthGroupFlow({ onComplete }) {
  const [step, setStep] = useState("welcome");
  const [loginMode, setLoginMode] = useState("email");
  const [email, setEmail] = useState("minji@example.com");
  const [nickname, setNickname] = useState("민지");
  const [groupType, setGroupType] = useState("couple");
  const [groupName, setGroupName] = useState("우리의 30일");
  const [inviteInput, setInviteInput] = useState("");
  const [acceptedInvite, setAcceptedInvite] = useState(null);

  const finishCreate = () => {
    const code = makeInviteCode();
    onComplete({
      account: { id: "me", email, nickname, provider: loginMode },
      group: {
        ...INITIAL_GROUP,
        id: `grp_${Date.now()}`,
        name: groupName || (groupType === "couple" ? "우리의 셋로그" : "같이 하는 셋로그"),
        type: groupType,
        maxMembers: groupType === "couple" ? 2 : 12,
        inviteCode: code,
        inviteUrl: `https://sal-log.app/join/${code}`,
        members: [{ userId: "me", name: nickname || "나", initial: (nickname || "나")[0], role: "owner", status: "active", color: C.me, shareBody: true, shareCoach: true }],
      },
    });
  };

  const previewInvite = () => {
    const code = (inviteInput || "SAL-7K2M9Q").trim().toUpperCase();
    setAcceptedInvite({ code, groupName: "여름 바디 챌린지", type: code.includes("FRIEND") ? "friends" : "couple", inviter: "준호", members: 1 });
    setStep("accept");
  };

  const finishJoin = () => {
    const g = acceptedInvite || { code: "SAL-7K2M9Q", groupName: "우리의 30일", type: "couple", inviter: "준호" };
    onComplete({
      account: { id: "me", email, nickname, provider: loginMode },
      group: {
        ...INITIAL_GROUP,
        id: `grp_joined_${g.code}`,
        name: g.groupName,
        type: g.type,
        maxMembers: g.type === "couple" ? 2 : 12,
        inviteCode: g.code,
        inviteUrl: `https://sal-log.app/join/${g.code}`,
        members: [
          { userId: "lover", name: g.inviter, initial: g.inviter[0], role: "owner", status: "active", color: C.lover, shareBody: true, shareCoach: true },
          { userId: "me", name: nickname || "나", initial: (nickname || "나")[0], role: "member", status: "active", color: C.me, shareBody: true, shareCoach: true },
        ],
      },
    });
  };

  return (
    <div className="auth-shell">
      <div className="auth-brand"><span className="wordmark">sal<i>—</i>log</span><p>같이 기록하고, 같이 확인하는 셋로그</p></div>
      {step === "welcome" && <div className="auth-card hero-card"><span className="eyebrow">COUPLE FIRST · GROUP READY</span><h1>혼자 하는 다이어트를<br/>우리의 기록으로.</h1><p>커플로 시작하고, 친구들과도 초대 링크 하나로 같은 셋로그를 만들 수 있어요.</p><button className="save-btn" onClick={() => setStep("login")}>시작하기</button><button className="ghost-btn" onClick={() => { setStep("login"); setInviteInput("SAL-7K2M9Q"); }}>초대 링크로 들어왔어요</button></div>}
      {step === "login" && <div className="auth-card"><div className="auth-step">1 / 3 · 로그인</div><h2>내 계정 만들기</h2><p className="auth-desc">그룹이 바뀌어도 내 운동·식단·인바디 기록은 내 계정에 안전하게 남아요.</p><div className="social-row"><button className={loginMode === "kakao" ? "on" : ""} onClick={() => setLoginMode("kakao")}>카카오</button><button className={loginMode === "apple" ? "on" : ""} onClick={() => setLoginMode("apple")}>Apple</button><button className={loginMode === "google" ? "on" : ""} onClick={() => setLoginMode("google")}>Google</button></div><label className="auth-field"><span>이메일</span><input value={email} onChange={(e) => setEmail(e.target.value)} type="email" /></label><label className="auth-field"><span>앱에서 사용할 이름</span><input value={nickname} onChange={(e) => setNickname(e.target.value)} maxLength={12} /></label><button className="save-btn" onClick={() => setStep("groupChoice")}>계속</button></div>}
      {step === "groupChoice" && <div className="auth-card"><div className="auth-step">2 / 3 · 그룹 연결</div><h2>누구와 함께할까요?</h2><div className="choice-grid"><button onClick={() => setStep("create")}><b>새 그룹 만들기</b><span>내가 방장이 되어 초대</span></button><button onClick={() => setStep("join")}><b>초대받은 그룹 참여</b><span>링크 또는 코드 입력</span></button></div><div className="model-note"><b>확장 가능한 구조</b><span>커플과 친구 그룹 모두 같은 그룹·멤버·초대 데이터 모델을 사용해요.</span></div></div>}
      {step === "create" && <div className="auth-card"><div className="auth-step">3 / 3 · 그룹 만들기</div><h2>우리 셋로그 만들기</h2><div className="type-toggle"><button className={groupType === "couple" ? "on" : ""} onClick={() => setGroupType("couple")}><b>커플</b><span>2명 · 서로의 변화 중심</span></button><button className={groupType === "friends" ? "on" : ""} onClick={() => setGroupType("friends")}><b>친구들</b><span>최대 12명 · 챌린지형</span></button></div><label className="auth-field"><span>그룹 이름</span><input value={groupName} onChange={(e) => setGroupName(e.target.value)} /></label><div className="permission-box"><b>기본 공유 범위</b><span>오늘 기록 · 운동 성과 · 코치 추천</span><span>체중·체지방은 멤버별 동의 후 공유</span></div><button className="save-btn" onClick={finishCreate}>그룹 만들고 초대하기</button><button className="back-btn" onClick={() => setStep("groupChoice")}>이전</button></div>}
      {step === "join" && <div className="auth-card"><div className="auth-step">3 / 3 · 초대 확인</div><h2>초대 링크 또는 코드</h2><p className="auth-desc">웹 초대 링크로 앱을 열면 코드가 자동 입력되는 흐름입니다.</p><label className="auth-field"><span>초대 코드</span><input value={inviteInput} onChange={(e) => setInviteInput(e.target.value)} placeholder="SAL-XXXXXX" /></label><button className="save-btn" onClick={previewInvite}>초대 확인</button><button className="back-btn" onClick={() => setStep("groupChoice")}>이전</button></div>}
      {step === "accept" && acceptedInvite && <div className="auth-card"><div className="invite-preview"><div className="invite-avatars"><span>J</span><span>+</span></div><h2>{acceptedInvite.groupName}</h2><p>{acceptedInvite.inviter}님이 {acceptedInvite.type === "couple" ? "커플 셋로그" : "친구 셋로그"}에 초대했어요.</p><div className="invite-meta"><span>{acceptedInvite.type === "couple" ? "최대 2명" : "최대 12명"}</span><span>코드 {acceptedInvite.code}</span></div></div><div className="consent-box"><b>참여하면 공유되는 정보</b><span>영상 기록과 운동·식단 성과</span><span>신체 수치는 참여 후 별도로 공개 설정</span></div><button className="save-btn" onClick={finishJoin}>초대 수락하고 참여</button><button className="back-btn" onClick={() => setStep("join")}>다른 코드 입력</button></div>}
    </div>
  );
}

function GroupSheet({ group, onClose, onUpdate }) {
  const [copied, setCopied] = useState(false);
  const [newName, setNewName] = useState("");
  const copyInvite = async () => {
    try { await navigator.clipboard?.writeText(group.inviteUrl); } catch (e) {}
    setCopied(true); setTimeout(() => setCopied(false), 1200);
  };
  const addDemoMember = () => {
    if (group.members.length >= group.maxMembers) return;
    const idx = group.members.length;
    const name = newName.trim() || `친구 ${idx}`;
    onUpdate({ ...group, type: "friends", maxMembers: 12, members: [...group.members, { userId: `friend_${Date.now()}`, name, initial: name[0], role: "member", status: "active", color: FRIEND_COLORS[idx % FRIEND_COLORS.length], shareBody: false, shareCoach: true }] });
    setNewName("");
  };
  return <div className="overlay center" onClick={onClose}><div className="group-sheet" onClick={(e) => e.stopPropagation()}><div className="sheet-head"><div><span>{group.type === "couple" ? "커플 그룹" : "친구 그룹"}</span><h2>{group.name}</h2></div><button onClick={onClose}>×</button></div><div className="member-list">{group.members.map((m) => <div className="member-row" key={m.userId}><span className="member-avatar" style={{ background: m.color }}>{m.initial}</span><div><b>{m.name}</b><span>{m.role === "owner" ? "방장" : "멤버"} · {m.shareBody ? "신체 정보 공유" : "성과만 공유"}</span></div><em>{m.status === "active" ? "참여 중" : "대기"}</em></div>)}</div><div className="invite-box"><span>초대 링크</span><code>{group.inviteUrl}</code><button onClick={copyInvite}>{copied ? "복사됨" : "링크 복사"}</button></div>{group.type === "couple" && group.members.length >= 2 ? <button className="expand-group" onClick={() => onUpdate({ ...group, type: "friends", maxMembers: 12 })}>친구도 초대할 수 있게 그룹 확장</button> : <div className="add-member"><input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="데모 멤버 이름"/><button onClick={addDemoMember}>초대 수락 시뮬레이션</button></div>}<p className="sheet-note">실서비스에서는 초대 토큰을 서버에서 1회성·만료형으로 발급하고, 수락 시 group_members에 가입 상태를 생성합니다.</p></div></div>;
}

/* ═══════ 바디 페이지 (체중·골격근량·체지방률 추이) ═══════ */
function BodyPage({ profiles, activeUser, onScan }) {
  const PersonBody = ({ u }) => {
    const profile = profiles[u];
    const hist = profile.history || [];
    const latest = hist[hist.length - 1];
    const prev = hist[hist.length - 2];
    const delta = (k) => (latest && prev ? Math.round((latest[k] - prev[k]) * 10) / 10 : null);
    const bmr = calcBMR(profile), tdee = calcTDEE(profile);

    const chartW = 300, chartH = 84;
    const ws = hist.map((h) => h.w);
    const min = Math.min(...ws) - 0.5, max = Math.max(...ws) + 0.5;
    const pt = (i) => {
      const x = 16 + (i / Math.max(1, hist.length - 1)) * (chartW - 32);
      const y = 12 + (1 - (ws[i] - min) / (max - min || 1)) * (chartH - 28);
      return [x, y];
    };
    const path = hist.map((_, i) => pt(i).join(",")).join(" ");

    const Metric = ({ label, value, unit, d, goodDown }) => (
      <div className="metric compact">
        <span className="metric-label">{label}</span>
        <b>{value ?? "—"}<em>{unit}</em></b>
        {d != null && d !== 0 && (
          <span className={"metric-delta " + ((d < 0) === goodDown ? "good" : "bad")}>
            {d > 0 ? "▲" : "▼"} {Math.abs(d)}{unit}
          </span>
        )}
        {d === 0 && <span className="metric-delta flat">유지</span>}
      </div>
    );

    return (
      <section className={"partner-panel" + (u === activeUser ? " active" : "")}>
        <div className="partner-head">
          <div className="partner-id">
            <span className="partner-avatar" style={{ background: USERS[u].color }}>{USERS[u].initial}</span>
            <div><b>{USERS[u].name}</b><span>마지막 인바디 {latest ? latest.d : "—"}</span></div>
          </div>
          <div className="partner-bmr"><span>BMR</span><b>{bmr?.toLocaleString() || "—"}</b></div>
        </div>

        <div className="metric-grid">
          <Metric label="체중" value={latest?.w} unit="kg" d={delta("w")} goodDown={true} />
          <Metric label="골격근량" value={latest?.s} unit="kg" d={delta("s")} goodDown={false} />
          <Metric label="체지방률" value={latest?.f} unit="%" d={delta("f")} goodDown={true} />
        </div>

        <div className="chart-card compact-chart">
          <div className="chart-head"><span>체중 추이</span><em>TDEE {tdee?.toLocaleString() || "—"} kcal</em></div>
          <svg width="100%" viewBox={`0 0 ${chartW} ${chartH}`} className="chart">
            <polyline points={path} fill="none" stroke={USERS[u].color} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
            {hist.map((h, i) => {
              const [x, y] = pt(i);
              return <g key={i}><circle cx={x} cy={y} r="3.5" fill={C.bg} stroke={USERS[u].color} strokeWidth="2" /><text x={x} y={chartH - 3} textAnchor="middle" fontSize="9" fill={C.faint}>{h.d}</text><text x={x} y={y - 7} textAnchor="middle" fontSize="9.5" fill={C.muted}>{h.w}</text></g>;
            })}
          </svg>
        </div>

        {u === activeUser && <button className="scan-again" onClick={onScan}>⌞ ⌝ 내 새 인바디 검사지 스캔</button>}
      </section>
    );
  };

  return (
    <div className="page">
      <div className="page-head"><b>커플 바디</b><span>서로의 변화를 함께 확인해요</span></div>
      <div className="shared-banner"><b>공유 중</b><span>체중 · 골격근량 · 체지방률 · 대사량</span></div>
      <PersonBody u="me" />
      <PersonBody u="lover" />
      <p className="footnote">민감한 신체 데이터는 커플 연결 및 상호 동의가 완료된 사용자끼리만 공유하도록 백엔드 권한을 구성하세요.</p>
    </div>
  );
}

/* ═══════ 코치 페이지 (내일 운동 · 음식 추천) ═══════ */
function CoachPage({ profiles, clips, stats }) {
  const PersonCoach = ({ u }) => {
    const profile = profiles[u];
    const myMoves = clips.filter((c) => c.user === u && c.tag?.type === "move");
    const trained = new Set(myMoves.map((c) => c.tag.part || MET_DB.find((m) => m.name === c.tag.name)?.part).filter(Boolean));
    const untrained = PARTS.filter((p) => !trained.has(p) && !trained.has("전신"));
    const allTrained = untrained.length === 0;
    const recs = (allTrained ? [{ part: "회복", ex: "요가", min: 20, met: 2.5 }] : untrained.slice(0, 2).map((part) => {
      const pick = PART_PICK[part];
      const ex = MET_DB.find((m) => m.name === pick.ex);
      return { part, ...pick, met: ex.met };
    })).map((r) => ({ ...r, kcal: metKcal(r.met, profile.weight, r.min) }));
    const s = stats[u];
    const food = s.balance > 0 ? FOOD_REC.surplus : FOOD_REC.deficit;

    return (
      <section className="partner-panel coach-person">
        <div className="partner-head">
          <div className="partner-id"><span className="partner-avatar" style={{ background: USERS[u].color }}>{USERS[u].initial}</span><div><b>{USERS[u].name}의 코치</b><span>오늘 수지 {s.balance > 0 ? "+" : ""}{s.balance.toLocaleString()} kcal</span></div></div>
          <span className={"balance-pill " + (s.balance <= 0 ? "good" : "over")}>{s.balance <= 0 ? "적자" : "흑자"}</span>
        </div>
        <div className="part-row">{PARTS.map((p) => <span key={p} className={"part" + (trained.has(p) || trained.has("전신") ? " hit" : "")}>{p}</span>)}</div>
        <div className="mini-section-title">내일 추천 운동</div>
        {recs.map((r) => <div className="rec-row" key={r.ex}><span className="rec-part">{r.part}</span><div className="rec-body"><b>{r.ex}</b><span>{r.min}분 · {profile.weight}kg 기준</span></div><span className="rec-kcal">−{r.kcal}</span></div>)}
        <div className="mini-section-title">추천 음식</div>
        {food.items.slice(0, 2).map((f) => <div className="rec-row" key={f.name}><span className="rec-part food">밥</span><div className="rec-body"><b>{f.name}</b><span>{f.note}</span></div><span className="rec-kcal plain">+{f.kcal}</span></div>)}
      </section>
    );
  };

  return (
    <div className="page">
      <div className="page-head"><b>커플 코치</b><span>각자에게 맞는 내일 계획</span></div>
      <div className="shared-banner"><b>함께 보기</b><span>추천 운동과 식단을 서로 확인하고 응원해요</span></div>
      <PersonCoach u="me" />
      <PersonCoach u="lover" />
      <p className="footnote">추천은 운동 기록·칼로리 수지·인바디 수치를 바탕으로 한 참고용이에요.</p>
    </div>
  );
}

/* ═══════ 메인 앱 ═══════ */
export default function SalLog() {
  const [session, setSession] = useState(null);
  const [group, setGroup] = useState(INITIAL_GROUP);
  const [groupOpen, setGroupOpen] = useState(false);
  const [user, setUser] = useState("me");
  const [profiles, setProfiles] = useState(INITIAL_PROFILES);
  const [clips, setClips] = useState(INITIAL_CLIPS);
  const [tab, setTab] = useState("today"); // today | coach | body
  const [capture, setCapture] = useState(false);
  const [scanOpen, setScanOpen] = useState(false);
  const [onboarding, setOnboarding] = useState(false); // 로그인·그룹 연결 후 선택적 인바디 스캔
  const [exporter, setExporter] = useState(false);
  const [ready, setReady] = useState(false);

  const [segIdx, setSegIdx] = useState(0);
  const [playing, setPlaying] = useState(true);
  const [durMap, setDurMap] = useState({});
  const leftRef = useRef(null);
  const rightRef = useRef(null);
  const sideRefs = { me: leftRef, lover: rightRef };

  const canvasRef = useRef(null);
  const rafRef = useRef(null);
  const blobRef = useRef(null);
  const extRef = useRef("webm");
  const poolEls = useRef({});

  const segs = useMemo(() => buildSegments(clips), [clips]);
  const seg = segs[segIdx] || null;

  const statsFor = (u) => {
    const mine = clips.filter((c) => c.user === u && c.tag);
    const intake = mine.filter((c) => c.tag.type === "food").reduce((a, c) => a + c.tag.kcal, 0);
    const burn = mine.filter((c) => c.tag.type === "move").reduce((a, c) => a + c.tag.kcal, 0);
    const bmr = calcBMR(profiles[u]) || 0;
    return { intake, burn, bmr, burnTotal: bmr + burn, balance: intake - (bmr + burn) };
  };
  const stats = { me: statsFor("me"), lover: statsFor("lover") };
  const myStats = stats[user];
  const myBmr = calcBMR(profiles[user]);

  /* 연속 재생 엔진 */
  useEffect(() => {
    if (tab !== "today" || !playing || !seg) return;
    ["me", "lover"].forEach((u) => {
      const el = sideRefs[u].current;
      if (!el) return;
      const { clip, active } = sideAt(segs, segIdx, u);
      if (active && clip.videoUrl) {
        if (!el.src.endsWith(clip.videoUrl)) el.src = clip.videoUrl;
        el.currentTime = 0;
        el.play().catch(() => {});
      } else if (clip && clip.videoUrl) {
        if (!el.src.endsWith(clip.videoUrl)) el.src = clip.videoUrl;
        el.pause();
      } else el.removeAttribute("src");
    });
    const id = setTimeout(() => setSegIdx((i) => (i + 1) % segs.length), segDur(seg, durMap));
    return () => clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab, playing, segIdx, segs, durMap]);

  useEffect(() => { if (segIdx >= segs.length) setSegIdx(0); }, [segs.length, segIdx]);

  const saveClip = (clip) => {
    const next = [...clips, clip];
    setClips(next);
    setCapture(false);
    const ns = buildSegments(next);
    const idx = ns.findIndex((s) => Object.values(s.clips).some((c) => c.id === clip.id));
    if (idx >= 0) { setTab("today"); setSegIdx(idx); setPlaying(true); }
  };

  const applyScan = (parsed) => {
    if (parsed) {
      const p = profiles[user];
      const entry = { d: dateLabel().split(" ")[0], w: parsed.weight, s: parsed.smm, f: parsed.bodyFat };
      setProfiles({
        ...profiles,
        [user]: {
          ...p, weight: parsed.weight, smm: parsed.smm, bodyFat: parsed.bodyFat,
          history: [...(p.history || []), entry],
        },
      });
    }
    setOnboarding(false);
    setScanOpen(false);
  };

  /* 내보내기 (가로 16:9 하나의 영상으로 녹화) */
  const runExport = () => {
    const cv = canvasRef.current;
    if (!cv || segs.length === 0) return;
    cancelAnimationFrame(rafRef.current);
    setReady(false);
    const ctx = cv.getContext("2d");
    const durs = segs.map((s) => segDur(s, durMap));
    const total = T_INTRO + durs.reduce((a, b) => a + b, 0) + T_OUTRO;
    const bounds = [0, T_INTRO];
    durs.forEach((d) => bounds.push(bounds[bounds.length - 1] + d));
    bounds.push(total);

    let rec = null, chunks = [];
    try {
      const mime = ["video/mp4", "video/webm;codecs=vp9", "video/webm"]
        .find((m) => window.MediaRecorder && MediaRecorder.isTypeSupported(m));
      if (mime) {
        extRef.current = mime.startsWith("video/mp4") ? "mp4" : "webm";
        rec = new MediaRecorder(cv.captureStream(30), { mimeType: mime });
        rec.ondataavailable = (e) => e.data.size && chunks.push(e.data);
        rec.onstop = () => {
          blobRef.current = new Blob(chunks, { type: rec.mimeType });
          setReady(true);
        };
        rec.start();
      }
    } catch (e) { /* 녹화 미지원 → 재생만 */ }

    let curIdx = -2;
    const t0 = performance.now();
    const tick = (now) => {
      const t = Math.min(now - t0, total);
      let idx = -1;
      for (let i = 1; i < bounds.length - 2; i++)
        if (t >= bounds[i] && t < bounds[i + 1]) { idx = i - 1; break; }
      if (t >= bounds[bounds.length - 2]) idx = -9;

      if (idx !== curIdx) {
        Object.values(poolEls.current).forEach((v) => v && v.pause());
        if (idx >= 0)
          ["me", "lover"].forEach((u) => {
            const c = segs[idx].clips[u];
            const el = c && poolEls.current[c.id];
            if (el) { try { el.currentTime = 0; el.play(); } catch (e) {} }
          });
        curIdx = idx;
      }

      if (t < T_INTRO) drawIntro(ctx, t / T_INTRO);
      else if (idx >= 0) drawSeg(ctx, segs, idx, (t - bounds[idx + 1]) / durs[idx], poolEls.current);
      else drawOutro(ctx, (t - bounds[bounds.length - 2]) / T_OUTRO, stats);

      const n = bounds.length - 1;
      const barW = (W - 48 - (n - 1) * 5) / n;
      for (let i = 0; i < n; i++) {
        const s0 = bounds[i], e0 = bounds[i + 1];
        const p = t <= s0 ? 0 : t >= e0 ? 1 : (t - s0) / (e0 - s0);
        const x = 24 + i * (barW + 5);
        ctx.fillStyle = "rgba(255,255,255,.28)";
        rr(ctx, x, 14, barW, 3, 1.5); ctx.fill();
        if (p > 0) { ctx.fillStyle = "#FFF"; rr(ctx, x, 14, barW * p, 3, 1.5); ctx.fill(); }
      }

      if (t < total) rafRef.current = requestAnimationFrame(tick);
      else {
        Object.values(poolEls.current).forEach((v) => v && v.pause());
        if (rec && rec.state === "recording") rec.stop();
        else if (!rec) setReady(true);
      }
    };
    rafRef.current = requestAnimationFrame(tick);
  };

  useEffect(() => {
    if (exporter) { setPlaying(false); runExport(); }
    else setPlaying(true);
    return () => cancelAnimationFrame(rafRef.current);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [exporter]);

  const shareVideo = async () => {
    const blob = blobRef.current;
    if (!blob) return;
    const file = new File([blob], `sal-log.${extRef.current}`, { type: blob.type });
    try {
      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file], title: "sal-log" });
        return;
      }
    } catch (e) { /* 공유 취소/미지원 → 저장 */ }
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `sal-log.${extRef.current}`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  const curDur = seg ? segDur(seg, durMap) : DEFAULT_SEG_MS;

  const completeAuth = ({ account, group: nextGroup }) => {
    setSession(account);
    setGroup(nextGroup);
    setOnboarding(true);
  };

  if (!session) {
    return <div className="stage"><style>{css}</style><div className="iphone auth-phone"><AuthGroupFlow onComplete={completeAuth} /><div className="home-indicator" /></div></div>;
  }

  return (
    <div className="stage">
      <style>{css}</style>

      <div style={{ display: "none" }}>
        {clips.filter((c) => c.videoUrl).map((c) => (
          <video key={c.id} src={c.videoUrl} muted loop playsInline preload="auto"
            ref={(el) => { poolEls.current[c.id] = el; }}
            onLoadedMetadata={(e) => {
              const ms = Math.round(e.target.duration * 1000);
              if (ms && isFinite(ms)) setDurMap((m) => ({ ...m, [c.id]: ms }));
            }} />
        ))}
      </div>

      <div className="iphone">
        <div className="island" />
        <div className="statusbar"><span>{nowHM()}</span><span>􀙇 􀛨</span></div>

        <header className="nav">
          <div className="brand">
            <span className="wordmark">sal<i>—</i>log</span>
            <span className="brand-date">{group.name} · {group.members.length}명 · 오늘 {clips.length}컷</span>
          </div>
          <div className="nav-actions">
            <button className="icon-btn group-btn" onClick={() => setGroupOpen(true)} aria-label="그룹 관리">{group.members.length}</button>
            <button className="icon-btn" onClick={() => setExporter(true)} aria-label="영상 내보내기">
              <svg width="18" height="18" viewBox="0 0 20 20" fill="none">
                <path d="M10 12.5V2.5M10 2.5L6.5 6M10 2.5L13.5 6" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>
                <path d="M4.5 9.5H4a1.5 1.5 0 0 0-1.5 1.5v5A1.5 1.5 0 0 0 4 17.5h12a1.5 1.5 0 0 0 1.5-1.5v-5A1.5 1.5 0 0 0 16 9.5h-.5" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/>
              </svg>
            </button>
            <button className="couple-pill" onClick={() => setUser(user === "me" ? "lover" : "me")}>
              <span className={"dot me" + (user === "me" ? " on" : "")}>M</span>
              <span className={"dot lover" + (user === "lover" ? " on" : "")}>J</span>
            </button>
          </div>
        </header>

        <main className="body">
          {tab === "today" && (
            <>
              {/* 가로(16:9) 연속 브이로그 플레이어 */}
              <section className="theater" onClick={() => setPlaying((p) => !p)}>
                {["me", "lover"].map((u) => {
                  const info = seg ? sideAt(segs, segIdx, u) : { clip: null, active: false };
                  const { clip, active } = info;
                  return (
                    <div className={"side" + (active ? "" : " held")} key={u}>
                      <video ref={sideRefs[u]} muted playsInline className="side-video"
                        style={{ display: clip && clip.videoUrl ? "block" : "none" }} />
                      {(!clip || !clip.videoUrl) && (
                        <div className="side-fill">
                          {clip ? (
                            <p className={"side-caption" + (active ? "" : " dim")}>{clip.caption}</p>
                          ) : (
                            <span className="side-initial" style={{ color: USERS[u].color }}>
                              {USERS[u].initial}
                            </span>
                          )}
                        </div>
                      )}
                      {active && clip?.tag && (
                        <span className={"side-tag" + (clip.tag.type === "move" ? " burn" : "")}>
                          {clip.tag.type === "move" ? "−" : "+"}{clip.tag.kcal}
                        </span>
                      )}
                      {active && clip && (
                        <span className="side-name" style={{ color: USERS[u].color }}>{USERS[u].name}</span>
                      )}
                    </div>
                  );
                })}
                <span className="seam" />
                {seg && <span className="theater-time">{seg.time}</span>}
                {!playing && <span className="paused-glyph">▶</span>}
                <div className="progress">
                  {segs.map((s, i) => (
                    <span key={i} className={"pseg" + (i < segIdx ? " done" : "")}>
                      {i === segIdx && playing && <i style={{ animationDuration: `${curDur}ms` }} />}
                      {i === segIdx && !playing && <i style={{ width: "40%" }} />}
                    </span>
                  ))}
                </div>
                {segs.length === 0 && (
                  <div className="theater-empty">
                    <p>아직 오늘의 영상이 없어요.<br />첫 장면을 찍어볼까요?</p>
                  </div>
                )}
              </section>

              <button className="record-cta" onClick={() => setCapture(true)}>
                <span className="rec-ring" style={{ "--u": USERS[user].color }} />
                <div>
                  <b>지금 찍기</b>
                  <span>먹을 때, 움직일 때 · 시간은 나중에 맞출 수 있어요</span>
                </div>
              </button>

              <section className="duo-stats">
                {["me", "lover"].map((u) => (
                  <div className={"duo-stat-card" + (u === user ? " active" : "")} key={u}>
                    <div className="duo-stat-head"><span className="partner-avatar tiny" style={{ background: USERS[u].color }}>{USERS[u].initial}</span><b>{USERS[u].name}</b><em>{u === user ? "내 계정" : "공유됨"}</em></div>
                    <div className="duo-stat-grid">
                      <div><span>체지방</span><b>{profiles[u].bodyFat}%</b></div>
                      <div><span>운동</span><b className="burn">−{stats[u].burn}</b></div>
                      <div><span>섭취</span><b>+{stats[u].intake}</b></div>
                      <div><span>수지</span><b className={stats[u].balance <= 0 ? "burn" : "over"}>{stats[u].balance > 0 ? "+" : ""}{stats[u].balance}</b></div>
                    </div>
                  </div>
                ))}
              </section>

              <p className="footnote">
                운동 칼로리는 Compendium MET × 체중, 기초대사량은 인바디 스캔 수치 기반
                Katch-McArdle 공식으로 자동 계산돼요.
              </p>
            </>
          )}

          {tab === "coach" && (
            <CoachPage profiles={profiles} clips={clips} stats={stats} />
          )}

          {tab === "body" && (
            <BodyPage profiles={profiles} activeUser={user} onScan={() => setScanOpen(true)} />
          )}
        </main>

        {/* 탭 바 */}
        <nav className="tabbar">
          {[["today", "오늘", "M4 5h16v11H4z M8 20h8"], ["coach", "코치", "M12 3l2.2 5.6L20 10l-5.8 1.4L12 17l-2.2-5.6L4 10l5.8-1.4z"], ["body", "바디", "M3 12h4l2-5 4 10 2-5h6"]].map(([id, label, d]) => (
            <button key={id} className={tab === id ? "on" : ""} onClick={() => setTab(id)}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
                <path d={d} stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              {label}
            </button>
          ))}
        </nav>


        {groupOpen && <GroupSheet group={group} onClose={() => setGroupOpen(false)} onUpdate={setGroup} />}

        {capture && (
          <CaptureFlow user={user} weight={profiles[user].weight}
            onClose={() => setCapture(false)} onSave={saveClip} />
        )}

        {(onboarding || scanOpen) && (
          <ScanFlow baseProfile={profiles[user]} firstTime={onboarding}
            onDone={applyScan} onClose={() => setScanOpen(false)} />
        )}

        {exporter && (
          <div className="overlay center" onClick={() => setExporter(false)}>
            <div className="player" onClick={(e) => e.stopPropagation()}>
              <canvas ref={canvasRef} width={W} height={H} className="player-canvas" />
              <div className="player-bar">
                <button className="pbtn" onClick={() => setExporter(false)}>닫기</button>
                <button className="pbtn" onClick={runExport}>↺ 다시</button>
                <button className={"pbtn primary" + (ready ? "" : " off")} onClick={shareVideo} disabled={!ready}>
                  {ready ? "브이로그 공유" : "합치는 중…"}
                </button>
              </div>
            </div>
          </div>
        )}

        <div className="home-indicator" />
      </div>
    </div>
  );
}

const css = `
* { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }
.stage {
  min-height: 100vh; display: flex; align-items: center; justify-content: center;
  background: #060608; padding: 24px 8px;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Apple SD Gothic Neo", "Pretendard", sans-serif;
}
.iphone {
  position: relative; width: 390px; max-width: 100%; height: 812px;
  background: ${C.bg}; border-radius: 48px; border: 10px solid #000;
  box-shadow: 0 0 0 1px #222, 0 30px 70px rgba(0,0,0,.6);
  overflow: hidden; display: flex; flex-direction: column; color: ${C.text};
}
.island { position: absolute; top: 14px; left: 50%; transform: translateX(-50%);
  width: 110px; height: 30px; background: #000; border-radius: 20px; z-index: 60; }
.statusbar { display: flex; justify-content: space-between; padding: 17px 30px 0;
  font-size: 13px; font-weight: 600; }

.nav { display: flex; justify-content: space-between; align-items: center; padding: 14px 20px 10px; }
.wordmark { font-size: 25px; font-weight: 300; letter-spacing: .04em; }
.wordmark i { font-style: normal; font-weight: 600;
  background: ${DUO}; -webkit-background-clip: text; background-clip: text; color: transparent; }
.brand-date { display: block; font-size: 11.5px; color: ${C.muted}; margin-top: 3px; }
.nav-actions { display: flex; align-items: center; gap: 10px; }
.icon-btn { width: 36px; height: 36px; border-radius: 50%; border: 1px solid ${C.line};
  background: ${C.surface}; color: ${C.text}; cursor: pointer;
  display: flex; align-items: center; justify-content: center; }
.icon-btn:active { background: ${C.surface2}; }
.couple-pill { display: flex; align-items: center; gap: 4px;
  background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 20px; padding: 4px; cursor: pointer; }
.dot { width: 28px; height: 28px; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 12px; font-weight: 700; color: ${C.faint}; transition: all .18s ease; }
.dot.me.on { background: ${C.me}; color: #2b0713; }
.dot.lover.on { background: ${C.lover}; color: #04233a; }

.body { flex: 1; overflow-y: auto; padding: 2px 18px 84px; scrollbar-width: none; }
.body::-webkit-scrollbar { display: none; }

/* ── 가로 브이로그 플레이어 ── */
.theater { position: relative; display: grid; grid-template-rows: 1fr 1fr;
  aspect-ratio: 4 / 5; border-radius: 18px; overflow: hidden;
  background: #101016; border: 1px solid ${C.line}; cursor: pointer; }
.side { position: relative; overflow: hidden; }
.side.held .side-video { filter: brightness(.55); }
.side-video { width: 100%; height: 100%; object-fit: cover; display: block; }
.side-fill { position: absolute; inset: 0; display: flex;
  align-items: center; justify-content: center; padding: 14px; }
.side-caption { font-size: 13px; font-weight: 600; text-align: center; line-height: 1.45; color: ${C.text}; }
.side-caption.dim { color: ${C.faint}; }
.side-initial { font-size: 42px; font-weight: 700; opacity: .22; }
.side-tag { position: absolute; top: 12px; right: 10px;
  background: rgba(0,0,0,.55); backdrop-filter: blur(6px);
  font-size: 10.5px; font-weight: 700; padding: 3px 8px; border-radius: 10px; }
.side-tag.burn { color: ${C.green}; }
.side-name { position: absolute; bottom: 18px; left: 12px; transform: none;
  font-size: 10.5px; font-weight: 700; letter-spacing: .04em;
  text-shadow: 0 1px 6px rgba(0,0,0,.7); }
.seam { position: absolute; left: 0; right: 0; top: 50%; height: 2px;
  transform: translateY(-50%); background: linear-gradient(90deg, ${C.me}, ${C.lover}); }
.theater-time { position: absolute; top: 10px; left: 50%; transform: translateX(-50%);
  background: rgba(0,0,0,.55); backdrop-filter: blur(6px);
  font-size: 11.5px; font-weight: 700; letter-spacing: .06em;
  padding: 4px 11px; border-radius: 11px; }
.paused-glyph { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
  font-size: 34px; color: rgba(255,255,255,.85); text-shadow: 0 2px 14px rgba(0,0,0,.6); }
.progress { position: absolute; left: 10px; right: 10px; bottom: 8px; display: flex; gap: 4px; }
.pseg { flex: 1; height: 3px; border-radius: 2px;
  background: rgba(255,255,255,.28); overflow: hidden; position: relative; }
.pseg.done { background: rgba(255,255,255,.85); }
.pseg i { position: absolute; inset: 0 auto 0 0; width: 0; background: #fff;
  animation: fillbar linear forwards; display: block; }
@keyframes fillbar { from { width: 0; } to { width: 100%; } }
.theater-empty { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
  text-align: center; color: ${C.muted}; font-size: 13.5px; line-height: 1.7; }

.record-cta { display: flex; align-items: center; gap: 14px; width: 100%;
  background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 18px;
  padding: 13px 16px; margin-top: 12px; cursor: pointer; text-align: left; color: ${C.text}; }
.record-cta:active { background: ${C.surface2}; }
.record-cta b { display: block; font-size: 15px; font-weight: 700; }
.record-cta span { display: block; font-size: 11.5px; color: ${C.muted}; margin-top: 2px; }
.rec-ring { width: 42px; height: 42px; border-radius: 50%;
  border: 2.5px solid var(--u); position: relative; flex-shrink: 0; }
.rec-ring::after { content: ""; position: absolute; inset: 6px; border-radius: 50%; background: var(--u); }

.stats { display: grid; grid-template-columns: repeat(4, 1fr);
  background: ${C.surface}; border: 1px solid ${C.line};
  border-radius: 16px; margin-top: 12px; overflow: hidden; }
.stat { padding: 12px 6px 13px; text-align: center; }
.stat + .stat { border-left: 1px solid ${C.line}; }
.stat span { display: block; font-size: 10.5px; color: ${C.muted}; letter-spacing: .04em; margin-bottom: 5px; }
.stat b { font-size: 14.5px; font-weight: 600; }
.stat .burn { color: ${C.green}; }
.stat .over { color: ${C.me}; }
.stat.balance { background: ${C.surface2}; }
.footnote { margin-top: 16px; font-size: 11px; line-height: 1.6; color: ${C.faint}; }

/* ── 페이지 공통 ── */
.page { display: flex; flex-direction: column; gap: 12px; }
.page-head { display: flex; align-items: baseline; justify-content: space-between; padding: 4px 2px 2px; }
.page-head b { font-size: 19px; font-weight: 700; }
.page-head span { font-size: 11.5px; color: ${C.muted}; }

/* ── 바디 ── */
.metric-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
.metric { background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 16px;
  padding: 13px 12px; display: flex; flex-direction: column; gap: 4px; }
.metric-label { font-size: 11px; color: ${C.muted}; }
.metric b { font-size: 20px; font-weight: 300; letter-spacing: -.02em; }
.metric b em { font-style: normal; font-size: 11px; color: ${C.muted}; margin-left: 3px; }
.metric-delta { font-size: 11px; font-weight: 700; }
.metric-delta.good { color: ${C.green}; }
.metric-delta.bad { color: ${C.me}; }
.metric-delta.flat { color: ${C.faint}; }

.chart-card { background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 16px; padding: 14px; }
.chart-head { display: flex; justify-content: space-between; margin-bottom: 8px; }
.chart-head span { font-size: 13px; font-weight: 700; }
.chart-head em { font-style: normal; font-size: 11px; color: ${C.muted}; }
.chart { display: block; }

.bmr-card { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.bmr-card > div { background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 14px;
  padding: 13px 14px; display: flex; flex-direction: column; gap: 3px; }
.bmr-label { font-size: 11px; color: ${C.muted}; }
.bmr-card b { font-size: 22px; font-weight: 300; }
.bmr-card b em { font-style: normal; font-size: 12px; color: ${C.muted}; margin-left: 4px; }
.bmr-formula { font-size: 10.5px; color: ${C.faint}; }

.scan-again { border: 1px dashed ${C.line}; background: none; border-radius: 14px;
  padding: 13px; font-size: 13.5px; font-weight: 600; color: ${C.muted}; cursor: pointer; }
.scan-again:active { background: ${C.surface}; }

/* ── 코치 ── */
.coach-card { background: ${C.surface}; border: 1px solid ${C.line};
  border-radius: 16px; padding: 14px; display: flex; flex-direction: column; gap: 10px; }
.coach-title { font-size: 13.5px; font-weight: 700; }
.part-row { display: flex; gap: 7px; flex-wrap: wrap; }
.part { border: 1px solid ${C.line}; border-radius: 14px; padding: 6px 13px;
  font-size: 12.5px; color: ${C.faint}; }
.part.hit { border-color: transparent; background: ${DUO}; color: #14060c; font-weight: 700; }
.coach-note { font-size: 12px; color: ${C.muted}; line-height: 1.55; }
.coach-note.tight { margin-top: -4px; }
.rec-row { display: flex; align-items: center; gap: 11px; }
.rec-part { width: 44px; text-align: center; font-size: 11px; font-weight: 700;
  color: ${C.lover}; background: ${C.surface2}; border-radius: 9px; padding: 6px 0; flex-shrink: 0; }
.rec-part.food { color: ${C.me}; }
.rec-body { flex: 1; min-width: 0; }
.rec-body b { display: block; font-size: 13.5px; font-weight: 600; }
.rec-body span { font-size: 11px; color: ${C.muted}; }
.rec-kcal { font-size: 13.5px; font-weight: 700; color: ${C.green}; flex-shrink: 0; }
.rec-kcal.plain { color: ${C.text}; }


/* ── 커플 공유 대시보드 ── */
.shared-banner { display: flex; align-items: center; justify-content: space-between; gap: 12px;
  padding: 11px 13px; border-radius: 14px; background: linear-gradient(90deg, rgba(255,122,158,.12), rgba(111,195,255,.12));
  border: 1px solid ${C.line}; }
.shared-banner b { font-size: 12px; color: ${C.text}; }
.shared-banner span { font-size: 10.5px; color: ${C.muted}; text-align: right; }
.partner-panel { display: flex; flex-direction: column; gap: 11px; background: ${C.surface};
  border: 1px solid ${C.line}; border-radius: 18px; padding: 14px; }
.partner-panel.active { box-shadow: inset 0 0 0 1px rgba(255,122,158,.2); }
.partner-head { display: flex; justify-content: space-between; align-items: center; gap: 10px; }
.partner-id { display: flex; align-items: center; gap: 10px; }
.partner-id > div { display: flex; flex-direction: column; gap: 2px; }
.partner-id b { font-size: 14px; }
.partner-id span:not(.partner-avatar) { font-size: 10.5px; color: ${C.muted}; }
.partner-avatar { width: 34px; height: 34px; border-radius: 50%; display: inline-flex; align-items: center;
  justify-content: center; color: #101016; font-weight: 800; font-size: 12px; flex-shrink: 0; }
.partner-avatar.tiny { width: 24px; height: 24px; font-size: 9px; }
.partner-bmr { text-align: right; display: flex; flex-direction: column; }
.partner-bmr span { font-size: 9.5px; color: ${C.muted}; }
.partner-bmr b { font-size: 17px; font-weight: 500; }
.metric.compact { padding: 10px; }
.compact-chart { padding: 11px 12px 8px; }
.balance-pill { border-radius: 12px; padding: 5px 9px; font-size: 10.5px; font-weight: 700; }
.balance-pill.good { color: ${C.green}; background: rgba(123,227,160,.1); }
.balance-pill.over { color: ${C.me}; background: rgba(255,122,158,.1); }
.mini-section-title { font-size: 11px; color: ${C.muted}; border-top: 1px solid ${C.line}; padding-top: 10px; }
.duo-stats { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 12px; }
.duo-stat-card { background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 16px; padding: 11px; }
.duo-stat-card.active { background: ${C.surface2}; }
.duo-stat-head { display: flex; align-items: center; gap: 7px; margin-bottom: 10px; }
.duo-stat-head b { font-size: 12.5px; }
.duo-stat-head em { margin-left: auto; font-style: normal; font-size: 9px; color: ${C.faint}; }
.duo-stat-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.duo-stat-grid > div { display: flex; flex-direction: column; gap: 2px; }
.duo-stat-grid span { font-size: 9.5px; color: ${C.muted}; }
.duo-stat-grid b { font-size: 13px; }
.duo-stat-grid .burn { color: ${C.green}; }
.duo-stat-grid .over { color: ${C.me}; }

/* ── 탭 바 ── */
.tabbar { position: absolute; bottom: 14px; left: 18px; right: 18px;
  display: flex; background: rgba(21,21,27,.92); backdrop-filter: blur(14px);
  border: 1px solid ${C.line}; border-radius: 20px; padding: 6px; z-index: 20; }
.tabbar button { flex: 1; display: flex; flex-direction: column; align-items: center; gap: 3px;
  border: none; background: none; color: ${C.faint}; font-size: 10.5px; font-weight: 600;
  padding: 7px 0 5px; border-radius: 14px; cursor: pointer; }
.tabbar button.on { color: ${C.text}; background: ${C.surface2}; }

/* ── 오버레이 ── */
.overlay { position: absolute; inset: 0; background: rgba(0,0,0,.72); z-index: 50; display: flex; }
.overlay.bottom { align-items: flex-end; }
.overlay.center { align-items: center; justify-content: center; }

/* ── 인바디 스캔 ── */
.scan-card { width: 84%; margin: auto; background: ${C.bg}; border: 1px solid ${C.line};
  border-radius: 22px; padding: 22px 18px; display: flex; flex-direction: column; gap: 12px;
  animation: fadein .25s ease; }
.scan-title { font-size: 17px; font-weight: 700; }
.scan-desc { font-size: 12.5px; color: ${C.muted}; line-height: 1.6; }
.scan-drop { border: 1.5px dashed ${C.line}; border-radius: 16px; padding: 26px 14px;
  display: flex; flex-direction: column; align-items: center; gap: 7px; cursor: pointer; text-align: center; }
.scan-drop:active { background: ${C.surface}; }
.scan-icon { font-size: 22px; letter-spacing: .3em; color: ${C.muted}; }
.scan-drop b { font-size: 14.5px; }
.scan-sub { font-size: 11px; color: ${C.faint}; }
.scan-skip { border: none; background: none; color: ${C.muted}; font-size: 12.5px;
  text-decoration: underline; cursor: pointer; padding: 4px; }
.scan-analyzing { display: flex; flex-direction: column; align-items: center; gap: 10px; padding: 8px 0 4px; }
.scan-preview { width: 110px; height: 140px; object-fit: cover; border-radius: 12px;
  border: 1px solid ${C.line}; }
.scan-spinner { width: 26px; height: 26px; border-radius: 50%;
  border: 3px solid ${C.line}; border-top-color: ${C.me}; animation: spin .8s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }
.scan-analyzing b { font-size: 14px; }
.scan-analyzing span { font-size: 11.5px; color: ${C.muted}; }
.parse-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
.parse-field { display: flex; flex-direction: column; gap: 5px; }
.parse-field > span { font-size: 11px; color: ${C.muted}; }
.parse-field > div { display: flex; align-items: baseline; gap: 4px;
  background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 10px; padding: 9px 10px; }
.parse-field input { width: 100%; background: none; border: none; outline: none;
  color: ${C.text}; font-size: 15px; font-weight: 600; font-family: inherit; }
.parse-field em { font-style: normal; font-size: 11px; color: ${C.muted}; }
.parse-bmr { background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 12px;
  padding: 11px 14px; font-size: 12.5px; color: ${C.muted};
  display: flex; align-items: baseline; gap: 8px; flex-wrap: wrap; }
.parse-bmr b { font-size: 16px; color: ${C.text}; font-weight: 600; }
.parse-bmr span { font-size: 10.5px; color: ${C.faint}; width: 100%; }

/* ── 촬영 ── */
.capture { width: 100%; height: 100%; display: flex; flex-direction: column; background: #000; }
.cam-wrap { position: relative; flex: 1; overflow: hidden; }
.cam { width: 100%; height: 100%; object-fit: cover; display: block; }
.cam-off { display: flex; align-items: center; justify-content: center;
  color: ${C.muted}; text-align: center; font-size: 14px; line-height: 1.6; }
.cam-hud { position: absolute; top: 56px; left: 0; right: 0;
  display: flex; flex-direction: column; align-items: center; gap: 6px; }
.cam-hour { font-size: 26px; font-weight: 700; letter-spacing: .05em; color: #fff;
  text-shadow: 0 1px 10px rgba(0,0,0,.6); }
.cam-hint { font-size: 12px; color: rgba(255,255,255,.85);
  background: rgba(0,0,0,.4); padding: 4px 12px; border-radius: 12px; }
.cam-bar { display: flex; align-items: center; justify-content: space-between;
  padding: 18px 34px 40px; background: #000; }
.cam-side { color: #fff; font-size: 14px; font-weight: 600;
  background: none; border: none; cursor: pointer; width: 56px; text-align: center; }
.shutter { width: 70px; height: 70px; border-radius: 50%;
  border: 3.5px solid #fff; background: transparent; cursor: pointer;
  display: flex; align-items: center; justify-content: center; }
.shutter span { width: 54px; height: 54px; border-radius: 50%; background: var(--u);
  transition: all .18s ease; }
.shutter.on span { width: 28px; height: 28px; border-radius: 8px; }
.shutter:disabled { opacity: .35; }

.meta { width: 100%; height: 100%; display: flex; flex-direction: column; background: #000; }
.meta-video { flex: 1; width: 100%; object-fit: cover; min-height: 0; }
.meta-panel { background: ${C.bg}; border-top: 1px solid ${C.line};
  padding: 16px 16px 30px; display: flex; flex-direction: column; gap: 12px;
  max-height: 64%; overflow-y: auto; }
.meta-row { display: flex; gap: 10px; }
.caption-input { flex: 1; background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 12px;
  padding: 12px 14px; font-size: 15px; color: ${C.text}; outline: none; font-family: inherit; min-width: 0; }
.caption-input::placeholder { color: ${C.faint}; }
.caption-input:focus { border-color: ${C.muted}; }
.time-field { display: flex; flex-direction: column; gap: 4px;
  background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 12px; padding: 7px 12px 8px; }
.time-field span { font-size: 10px; color: ${C.muted}; }
.time-field input { background: none; border: none; color: ${C.text}; font-size: 15px; font-weight: 600;
  outline: none; font-family: inherit; width: 84px; color-scheme: dark; }

.tag-toggle { display: flex; background: ${C.surface}; border-radius: 11px; padding: 3px;
  border: 1px solid ${C.line}; }
.tag-toggle button { flex: 1; border: none; background: none; border-radius: 8px;
  padding: 8px; font-size: 13px; font-weight: 500; color: ${C.muted}; cursor: pointer; }
.tag-toggle button.on { background: ${C.surface2}; color: ${C.text}; font-weight: 600; }
.picker { display: flex; flex-direction: column; gap: 10px; }
.chips { display: flex; flex-wrap: wrap; gap: 7px; }
.chips.scrolly { max-height: 112px; overflow-y: auto; }
.chip { border: 1px solid ${C.line}; background: ${C.surface}; border-radius: 16px;
  padding: 7px 13px; font-size: 13px; color: ${C.text}; cursor: pointer; }
.chip em { font-style: normal; color: ${C.muted}; font-size: 11px; margin-left: 4px; }
.chip.on { border-color: ${C.text}; background: ${C.surface2}; font-weight: 600; }
.minute-row { display: flex; align-items: center; gap: 12px; }
.minute-row input[type="range"] { flex: 1; accent-color: ${C.green}; }
.minute-val { font-size: 13px; font-weight: 700; width: 44px; text-align: right; }
.auto-calc { background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 12px;
  padding: 11px 14px; display: flex; flex-direction: column; gap: 3px; }
.auto-calc b { font-size: 16px; color: ${C.green}; }
.auto-calc span { font-size: 11px; color: ${C.muted}; }
.save-btn { border: none; border-radius: 13px; padding: 14px;
  background: ${DUO}; color: #14060c; font-size: 15px; font-weight: 700; cursor: pointer; }
.save-btn:active { opacity: .85; }

/* ── 내보내기 (가로) ── */
.player { width: 92%; display: flex; flex-direction: column; gap: 12px; animation: fadein .25s ease; }
@keyframes fadein { from { opacity: 0; transform: scale(.97); } }
.player-canvas { width: 100%; aspect-ratio: 16 / 9; border-radius: 16px;
  background: ${C.bg}; display: block; border: 1px solid ${C.line}; }
.player-bar { display: flex; gap: 8px; }
.pbtn { flex: 1; border: 1px solid ${C.line}; border-radius: 12px; padding: 12px;
  font-size: 13.5px; font-weight: 600; cursor: pointer; background: ${C.surface}; color: ${C.text}; }
.pbtn.primary { background: ${DUO}; color: #14060c; border: none; flex: 1.5; }
.pbtn.primary.off { opacity: .45; cursor: default; }

.home-indicator { position: absolute; bottom: 6px; left: 50%; transform: translateX(-50%);
  width: 130px; height: 5px; background: #fff; border-radius: 3px; opacity: .25; z-index: 25; }


/* ── 인증 · 그룹 ── */
.auth-phone { border-color: #111; }
.auth-shell { flex: 1; overflow-y: auto; padding: 58px 20px 34px; display: flex; flex-direction: column; gap: 20px; background: radial-gradient(circle at 85% 0%, rgba(111,195,255,.15), transparent 35%), radial-gradient(circle at 10% 20%, rgba(255,122,158,.16), transparent 34%), #0B0B0F; }
.auth-brand p { margin-top: 5px; color: ${C.muted}; font-size: 12px; }
.auth-card { background: rgba(21,21,27,.94); border: 1px solid ${C.line}; border-radius: 24px; padding: 20px; display: flex; flex-direction: column; gap: 14px; }
.hero-card { margin-top: auto; margin-bottom: auto; }
.eyebrow, .auth-step { color: ${C.lover}; font-size: 10.5px; font-weight: 800; letter-spacing: .1em; }
.auth-card h1 { font-size: 28px; line-height: 1.25; letter-spacing: -.04em; }
.auth-card h2 { font-size: 21px; }
.auth-card > p, .auth-desc { color: ${C.muted}; font-size: 12.5px; line-height: 1.65; }
.ghost-btn, .back-btn { border: none; background: none; color: ${C.muted}; padding: 7px; cursor: pointer; }
.social-row { display: grid; grid-template-columns: repeat(3, 1fr); gap: 7px; }
.social-row button { border: 1px solid ${C.line}; background: ${C.bg}; color: ${C.muted}; border-radius: 11px; padding: 10px 4px; cursor: pointer; }
.social-row button.on { border-color: ${C.text}; color: ${C.text}; background: ${C.surface2}; }
.auth-field { display: flex; flex-direction: column; gap: 6px; }
.auth-field span { font-size: 11px; color: ${C.muted}; }
.auth-field input, .add-member input { border: 1px solid ${C.line}; background: ${C.bg}; color: ${C.text}; border-radius: 12px; padding: 12px 13px; outline: none; font-family: inherit; }
.choice-grid, .type-toggle { display: grid; grid-template-columns: 1fr 1fr; gap: 9px; }
.choice-grid button, .type-toggle button { text-align: left; border: 1px solid ${C.line}; background: ${C.bg}; color: ${C.text}; border-radius: 15px; padding: 15px 12px; cursor: pointer; }
.choice-grid b, .type-toggle b { display: block; font-size: 13.5px; }
.choice-grid span, .type-toggle span { display: block; color: ${C.muted}; font-size: 10.5px; margin-top: 5px; line-height: 1.4; }
.type-toggle button.on { border-color: ${C.lover}; background: rgba(111,195,255,.08); }
.model-note, .permission-box, .consent-box { border-radius: 13px; background: ${C.surface2}; padding: 12px 13px; display: flex; flex-direction: column; gap: 4px; }
.model-note b, .permission-box b, .consent-box b { font-size: 12px; }
.model-note span, .permission-box span, .consent-box span { color: ${C.muted}; font-size: 10.5px; line-height: 1.45; }
.invite-preview { text-align: center; display: flex; flex-direction: column; align-items: center; gap: 8px; }
.invite-avatars { display: flex; }
.invite-avatars span { width: 44px; height: 44px; border-radius: 50%; background: ${C.lover}; color: #06243b; display: grid; place-items: center; font-weight: 800; border: 3px solid ${C.surface}; }
.invite-avatars span + span { margin-left: -10px; background: ${C.surface2}; color: ${C.muted}; }
.invite-preview p { color: ${C.muted}; font-size: 12px; }
.invite-meta { display: flex; gap: 7px; }
.invite-meta span { background: ${C.surface2}; color: ${C.muted}; font-size: 10.5px; border-radius: 12px; padding: 5px 9px; }
.group-btn { font-size: 12px; font-weight: 800; color: ${C.lover}; }
.group-sheet { width: 88%; max-height: 78%; overflow-y: auto; background: ${C.bg}; border: 1px solid ${C.line}; border-radius: 23px; padding: 18px; display: flex; flex-direction: column; gap: 14px; }
.sheet-head { display: flex; justify-content: space-between; align-items: flex-start; }
.sheet-head span { font-size: 10.5px; color: ${C.lover}; font-weight: 700; }
.sheet-head h2 { margin-top: 3px; font-size: 20px; }
.sheet-head button { border: none; background: ${C.surface}; color: ${C.text}; width: 30px; height: 30px; border-radius: 50%; font-size: 20px; }
.member-list { display: flex; flex-direction: column; gap: 8px; }
.member-row { display: flex; align-items: center; gap: 10px; background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 13px; padding: 10px; }
.member-avatar { width: 34px; height: 34px; border-radius: 50%; display: grid; place-items: center; color: #101016; font-weight: 800; }
.member-row > div { flex: 1; }
.member-row b { display: block; font-size: 12.5px; }
.member-row span, .member-row em { font-size: 10px; color: ${C.muted}; font-style: normal; }
.invite-box { background: ${C.surface}; border: 1px solid ${C.line}; border-radius: 14px; padding: 12px; display: grid; gap: 7px; }
.invite-box > span { font-size: 10.5px; color: ${C.muted}; }
.invite-box code { font-size: 10px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: ${C.text}; }
.invite-box button, .expand-group, .add-member button { border: none; background: ${DUO}; color: #14060c; border-radius: 10px; padding: 10px; font-weight: 700; cursor: pointer; }
.add-member { display: grid; grid-template-columns: 1fr auto; gap: 7px; }
.add-member button { padding-inline: 11px; font-size: 11px; }
.sheet-note { color: ${C.faint}; font-size: 10px; line-height: 1.55; }
`;
