# PLAN v0.3.3 추가 (macOS) — T-332 오디오 모드 + 추천 일원화 + 추천 기본 활성화 (3분 초안)

> 범위 확정: 이미지=생성 유지 / NIM 미검증 포함(404 자동제외 위임) / 기본 활성화=추천 세트만

## 검증 원천 (2026-09-05)
- Magpie: build.nvidia.com `nvidia/magpie-tts-zeroshot` 실존. 클라우드 TTS는
  OpenAI 호환 `POST {base}/audio/speech` JSON {model,input,voice,response_format}
  → 오디오 바이트 (apis.io OpenAPI 예시 모델 `nvidia/magpie-tts`). 예시 voice
  `en-US.Female-1` — 한국어 voice ID 미확인이라 voice 생략(서버 기본값).
- Qwen3-Coder: docs.api.nvidia.com — `qwen/qwen3-coder-480b-a35b-instruct`,
  integrate `/chat/completions`, 네이티브 262144.

## 변경
1. `ChatModels`: `ChatMode.audio`(오디오/waveform) + `selectedAudioModelID`.
2. `ModelCatalog.audioModels` = [Magpie TTS (무료, .nvidia)].
   `defaultModels` += `qwen/qwen3-coder-480b-a35b-instruct` (.nvidia, 262144).
   `defaultEnabledIDs` (provider:id): MuseSpark(Zen)·North(OR)·Qwen3Coder(NVIDIA)·
   BigPickle(Zen)·Magpie(NVIDIA)·gpt-image-1·dall-e-3. `isEnabled` 무오버라이드 시
   이 세트만 기본 ON (Apple Intelligence 기존 유지, 저장된 false 존중).
3. `Providers/AudioClient.swift` 신규 (ImageClient踏襲): 키=AppSettings nvidia 키
   (없으면 AppError.missingKey=E-MAC-KEY-1001), `/audio/speech` multipart 아님 JSON,
   response_format mp3. HTTP 오류→AppError.serverError (404면 기존 자동제외 동작).
   진입 로그 `[INFO] [FEATURE] <오디오 TTS>`.
4. `ChatViewModel`: selectedAudioModel/setAudioModel + send() `.audio` 분기 →
   `sendAudio` (sendImage踏襲, mimeType audio/mpeg, tts-<ts>.mp3).
5. `ChatInputBarView`: 세그먼트 260→344 + `audioModeBar`/배지/팝오버(Menu 금지).
   코딩 팝오버 추천 섹션=문서 순위 4종 순서 고정.
6. `BubbleViews`: 첨부 `audio/` 분기 → 재생/정지 행 (AVAudioPlayer 메모리 재생).
7. 테스트 `AudioModeDefaultsTestsV34`: audioModels·기본ON·spec round-trip.

## 검증
- unit + `./build_and_run.sh debug macos` + AX 읽기전용(세그먼트 4개 X=204) +
  사용자 실기동 (Magpie 합성·Qwen3-Coder 호출).

## DoD
- 빌드·테스트 통과, TODO·CHANGELOG[0.3.3]·세션 로그. Magpie voice/ko 품질은 후속.
