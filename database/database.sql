-- 소망 로켓 (Wishing Rocket) 데이터베이스 설정 스크립트

-- 1. messages 테이블 생성
-- id: UUID 고유 식별자 (기본값 랜덤 생성)
-- content: 메시지 내용 (최대 100자 제한)
-- color: 파스텔톤 우주 카드 배경색 Hex 코드
-- created_at: 생성 일시 (기본값 현재 시간)
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content TEXT NOT NULL CONSTRAINT content_length_check CHECK (char_length(content) <= 100),
    color VARCHAR(7) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Row Level Security (RLS) 활성화
-- 기본적으로 모든 직접적인 쓰기/수정/삭제 권한을 차단합니다.
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- 3. RLS 정책 설정: 누구나 조회(SELECT)는 가능하도록 설정
-- 익명 사용자(anon)를 포함하여 모든 사용자가 읽을 수 있도록 허용합니다.
-- 쓰기(INSERT)는 이 정책에 포함되지 않으므로, 클라이언트의 직접적인 데이터 추가는 차단됩니다.
-- 백엔드(Edge Function)는 Service Role Key를 사용하여 RLS를 우회하므로 쓰기가 가능합니다.
CREATE POLICY "Allow public read access" 
ON public.messages 
FOR SELECT 
TO public 
USING (true);

-- 4. 실시간(Realtime) 구독 활성화
-- messages 테이블에 실시간 변경 이벤트를 발행하도록 Supabase Realtime Publication에 추가합니다.
-- 이미 추가되어 있는 경우에 발생할 수 있는 중복 에러를 방지하기 위해 DO 블록을 사용하여 안전하게 처리합니다.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
EXCEPTION
  WHEN duplicate_object THEN
    -- 이미 테이블이 publication에 추가되어 있는 경우 무시
    NULL;
  WHEN undefined_object THEN
    -- supabase_realtime publication이 존재하지 않는 경우 무시
    NULL;
END $$;
