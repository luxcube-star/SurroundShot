# Surround Shot (주위환경 합성)

감정평가 **주위환경 사진**용 아이폰 앱입니다.
본건에서 멀리 떨어지지 않아도, 기본 카메라로 여러 장(예: 2줄 × 4장)을 나눠 찍은 뒤
한 장의 넓은 사진으로 이어 붙입니다.

## 쓰는 방법

1. **기본 카메라**로 제자리에서 몸만 돌리며 찍습니다.
   ```
   윗줄:  [1] [2] [3] [4]   ← 폰을 약간 위로
   아랫줄: [5] [6] [7] [8]   ← 폰을 약간 아래로
   ```
   - 옆 사진·위아래 사진과 **30% 이상 겹치게**
   - 모든 사진을 **같은 배율(1x)**로
   - 첫 장 전에 화면을 길게 눌러 **노출·초점 고정(AE/AF 잠금)**
2. **사진 앱**에서 그 사진들을 선택 → **공유** → **주위환경 합성**
   (또는 이 앱을 열고 '사진 선택')
3. 결과 형태를 고르고 **사진 앱에 저장**을 누릅니다.

| 결과 형태 | 설명 |
|---|---|
| 4:3 여백 (기본) | 전체를 그대로 두고 위아래(또는 양옆)에 흰 여백을 붙여 4:3 |
| 4:3 꽉 채우기 | 4:3으로 꽉 채움. 넓게 찍으면 양옆이 잘림 |
| 원본 비율 | 빈 가장자리만 잘라냄 |

- 투영 방식: **원통**(기본, 건물 세로선이 곧게) / 구면
- 결과 사진에는 첫 번째 사진의 촬영 날짜·위치가 복사됩니다.
- 공유 메뉴는 메모리 제한 때문에 작게(사진당 긴 변 1200px) 합성합니다.
  앱에서 합성하면 더 크게(2400px) 합성합니다.

## 설치 (AltStore / AltServer)

맥에 Xcode가 없어도 됩니다 (모아+ 와 같은 방식).

1. 이 저장소에 push 하면 GitHub Actions 가 **서명 없는 .ipa** 를 만듭니다.
   (Actions → 최근 실행 → 아래 Artifacts → `SurroundShot-ipa`)
2. 내려받은 zip 을 풀어 나온 `SurroundShot.ipa` 를 AltServer / AltStore 로 설치합니다.
   AltStore 가 설치할 때 본인 Apple 계정으로 다시 서명합니다.

## 구조

```
App/                 앱 본체 (사진 선택 화면, 촬영 요령)
ShareExtension/      공유 확장 (사진 앱 → 공유 → 주위환경 합성)
Shared/              두 타깃 공용
  StitchCore.hpp       합성·자르기 로직 (순수 C++ / OpenCV) ← 리눅스 테스트와 같은 코드
  PanoramaStitcher.*   Swift ↔ C++ 연결 (Objective-C++)
  StitchSession.swift  백그라운드 합성, 메타데이터 복사, 사진 앱 저장
  StitchViewModel.swift / StitchPanel.swift  화면
tests/stitch_test.cpp  리눅스용 합성 검사 (CI 에서 실제 샘플 사진으로 실행)
scripts/gen_xcodeproj.py  Xcode 프로젝트 파일 생성기
```

- OpenCV 4.13.0 ([yeatse/opencv-spm](https://github.com/yeatse/opencv-spm), Swift Package)
- 최소 iOS 18.0, 아이폰 전용
- 동기화 폴더라 파일을 추가·삭제해도 프로젝트 파일을 고칠 필요가 없습니다.
  타깃·빌드 설정을 바꿀 때만 `python3 scripts/gen_xcodeproj.py` 를 다시 실행합니다.

## 리눅스에서 합성 로직 검사

```bash
sudo apt-get install -y libopencv-dev
g++ -std=c++17 -O2 tests/stitch_test.cpp -o stitch_test $(pkg-config --cflags --libs opencv4)
./stitch_test out.jpg cyl 1.jpg 2.jpg 3.jpg 4.jpg
```
`out.jpg.fill43.jpg` / `.fit43.jpg` / `.original.jpg` 세 가지 결과와
자른 영역을 표시한 `out.jpg.full.jpg` 가 만들어집니다.
