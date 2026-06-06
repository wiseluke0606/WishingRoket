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

-- 2. HTML 이스케이프 함수 정의 (XSS 악성 스크립트 삽입 차단)
CREATE OR REPLACE FUNCTION public.escape_html(text_input TEXT)
RETURNS TEXT AS $$
DECLARE
  escaped TEXT;
BEGIN
  escaped := replace(text_input, '&', '&amp;');
  escaped := replace(escaped, '<', '&lt;');
  escaped := replace(escaped, '>', '&gt;');
  escaped := replace(escaped, '"', '&amp;quot;');
  escaped := replace(escaped, '''', '&#039;');
  RETURN escaped;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 3. 메시지 삽입 전 자동 실행될 트리거 함수 정의 (비속어 필터, 글자수 체크, 색상 정규화)
CREATE OR REPLACE FUNCTION public.before_insert_message()
RETURNS TRIGGER AS $$
DECLARE
  trimmed_content TEXT;
  banned_words TEXT[];
  word TEXT;
  pastel_colors TEXT[];
  random_pastel TEXT;
BEGIN
  -- 1) 입력 내용 트리밍 및 공백 메시지 검사
  trimmed_content := trim(NEW.content);
  IF char_length(trimmed_content) = 0 THEN
    RAISE EXCEPTION '메시지 내용을 입력해 주세요.';
  END IF;
  
  -- 2) 글자수 검사 (100자 초과 방지)
  IF char_length(trimmed_content) > 100 THEN
    RAISE EXCEPTION '메시지는 최대 100자까지만 입력 가능합니다.';
  END IF;

  -- 3) XSS 방지 처리
  trimmed_content := public.escape_html(trimmed_content);

  -- 4) 비속어 필터링 (한국어 대표 비속어 치환)
  banned_words := ARRAY['바보', '멍청이', '쓰레기', '나쁜놈', '광고'];
  FOREACH word IN ARRAY banned_words LOOP
    trimmed_content := regexp_replace(trimmed_content, word, repeat('♥', char_length(word)), 'gi');
  END LOOP;
  NEW.content := trimmed_content;

  -- 5) 색상 값 검증 및 정규화
  pastel_colors := ARRAY['#FFB7B2', '#FFDAC1', '#B5EAD7', '#C7CEEA', '#D5AAFF'];
  NEW.color := upper(NEW.color);
  IF NOT (NEW.color = ANY(pastel_colors)) THEN
    -- 유효하지 않은 색상인 경우 정의된 색상 목록 중 무작위 선택하여 할당
    random_pastel := pastel_colors[floor(random() * array_length(pastel_colors, 1) + 1)];
    NEW.color := random_pastel;
  END IF;

  -- 생성 시각을 DB 서버 시간으로 자동 설정
  NEW.created_at := now();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. 테이블과 트리거 함수 연결
CREATE OR REPLACE TRIGGER messages_before_insert
BEFORE INSERT ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.before_insert_message();

-- 5. Row Level Security (RLS) 활성화
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- 6. RLS 정책 설정: 누구나 조회(SELECT)는 가능하도록 설정
CREATE POLICY "Allow public read access" 
ON public.messages 
FOR SELECT 
TO public 
USING (true);

-- 7. RLS 정책 설정: 누구나 메시지 전송(INSERT)은 가능하도록 설정
-- 데이터 추가는 허용하되, 3번의 before_insert_message 트리거가 실시간으로 데이터를 검증 및 필터링하여 안전합니다.
CREATE POLICY "Allow public insert access" 
ON public.messages 
FOR INSERT 
TO public 
WITH CHECK (true);

-- 8. 실시간(Realtime) 구독 활성화
-- messages 테이블에 실시간 변경 이벤트를 발행하도록 Supabase Realtime Publication에 추가합니다.
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
