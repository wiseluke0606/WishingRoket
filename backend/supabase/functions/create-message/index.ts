// 소망 로켓 (Wishing Rocket) - 메시지 생성 Edge Function
// Deno 환경에서 작동하며, 클라이언트로부터 받은 메시지를 필터링하여 데이터베이스에 저장합니다.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

// 1. 상수 정의
const MAX_CONTENT_LENGTH = 100;
const DEFAULT_FALLBACK_COLOR = "#C7CEEA"; // 기본 파스텔 라벤더
const ALLOWED_PASTEL_COLORS = [
  "#FFB7B2", // 파스텔 핑크
  "#FFDAC1", // 파스텔 오렌지
  "#B5EAD7", // 파스텔 민트
  "#C7CEEA", // 파스텔 라벤더
  "#D5AAFF", // 파스텔 퍼플
];

// 비속어 목록 (단어 치환용)
const BANNED_WORDS = ["바보", "멍청이", "쓰레기", "나쁜놈", "광고"];
const FILTER_REPLACEMENT = "♥";

// 2. CORS 헤더 생성 함수
function buildCorsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json; charset=utf-8",
  };
}

// 3. HTML 태그 이스케이프 함수 (XSS 방지)
function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

// 4. 비속어 필터링 및 단어 치환 함수
function filterBannedWords(text: string): string {
  let filteredText = text;
  for (const word of BANNED_WORDS) {
    const regex = new RegExp(word, "gi");
    const replacement = FILTER_REPLACEMENT.repeat(word.length);
    filteredText = filteredText.replace(regex, replacement);
  }
  return filteredText;
}

// 5. 색상 유효성 검사 및 정규화 함수
function validateAndGetColor(colorInput: string): string {
  const normalizedColor = colorInput?.toUpperCase();
  if (ALLOWED_PASTEL_COLORS.includes(normalizedColor)) {
    return normalizedColor;
  }
  // 유효하지 않은 색상인 경우 정의된 색상 목록 중 랜덤하게 하나를 선택하여 반환
  const randomIndex = Math.floor(Math.random() * ALLOWED_PASTEL_COLORS.length);
  return ALLOWED_PASTEL_COLORS[randomIndex];
}

// 6. JSON 응답 생성 함수
function createJsonResponse(data: object, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: buildCorsHeaders(),
  });
}

// 7. Supabase Client 초기화 및 DB 삽입 기능 함수
async function insertMessageToDatabase(content: string, color: string): Promise<{ success: boolean; data?: any; error?: string }> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseServiceKey) {
    return { success: false, error: "데이터베이스 환경 변수가 올바르게 설정되지 않았습니다." };
  }

  // Service Role Key를 활용하여 RLS를 우회할 수 있는 클라이언트 생성
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  const { data, error } = await supabase
    .from("messages")
    .insert([{ content, color }])
    .select();

  if (error) {
    return { success: false, error: error.message };
  }

  return { success: true, data: data[0] };
}

// Deno Edge Function 메인 핸들러
Deno.serve(async (req) => {
  // CORS 사전 요청(Preflight) 처리
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: buildCorsHeaders() });
  }

  // POST 요청만 수락
  if (req.method !== "POST") {
    return createJsonResponse({ error: "허용되지 않는 메소드 요청입니다. POST 메소드만 지원합니다." }, 405);
  }

  try {
    const body = await req.json();
    const rawContent = body.content || "";
    const rawColor = body.color || "";

    // 1단계: 글자 수 검증 (1자 이상 100자 이하)
    const trimmedContent = rawContent.trim();
    if (trimmedContent.length === 0) {
      return createJsonResponse({ error: "메시지 내용을 입력해 주세요." }, 400);
    }
    if (trimmedContent.length > MAX_CONTENT_LENGTH) {
      return createJsonResponse({ error: `메시지는 최대 ${MAX_CONTENT_LENGTH}자까지만 입력 가능합니다.` }, 400);
    }

    // 2단계: XSS 방지 처리
    const escapedContent = escapeHtml(trimmedContent);

    // 3단계: 비속어 필터 처리
    const finalContent = filterBannedWords(escapedContent);

    // 4단계: 카드 색상 검증 및 반환
    const finalColor = validateAndGetColor(rawColor);

    // 5단계: 데이터베이스 저장 실행
    const dbResult = await insertMessageToDatabase(finalContent, finalColor);

    if (!dbResult.success) {
      return createJsonResponse({ error: `데이터베이스 저장 오류: ${dbResult.error}` }, 500);
    }

    return createJsonResponse({
      message: "메시지가 우주로 정상적으로 쏘아 올려졌습니다.",
      data: dbResult.data,
    }, 200);

  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "알 수 없는 에러가 발생했습니다.";
    return createJsonResponse({ error: `요청을 처리하는 중 오류가 발생했습니다: ${errorMessage}` }, 400);
  }
});
