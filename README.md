# wotjdCam

라이브 스트리밍 테스트용 iOS 어플리케이션

## 빌드하기

아래 명시된 대로 라이브러리를 추가한 뒤 빌드한다.

### 사용된 라이브러리

- Alamofire : HTTP 통신용 라이브러리
- HaishinKit : LiveStreaming 용 라이브러리 (H264/AAC 인코딩, TS Muxing, HLS 스트리밍 등)
- 라이브러리는 Carthage 로 관리중임

### Carthage 사용법 (라이브러리 관리 툴)

Carthage 패키지를 설치해야한다.

1. Cartfile 파일이 존재하는 폴더에서 터미널을 열어 `carthage update --platform iOS` 명령어 입력
   - Cartfile에 명시된 라이브러리들을 iOS 용으로만 빌드 명령어
2. xcodeproj 에 **Linked Frameworks and Libraries** 와 **Build Phases** 의 **Run Script** 추가

- Carthage Repo : https://github.com/Carthage/Carthage#quick-start

- 사용법 (한글) : https://letsean.app/2016/02/22/Carthage.html



## 그 외 

### 추가설정

xcodeproj 의 provisioning 정보, bundle identifier 를 추가 설정해야할 수 있음

### 실행

탭 별 구현사항이 다름

1. Authorize 탭 : 권한 관련 기능 확인용 탭 *(AuthorizationViewController)*
2. Camera 탭 : 개발 중인 탭

   - FrameExtractor : Camera, Mic 로 부터 Raw 스트림을 받고, Callback 호출 처리하는 코드가 존재
   - CameraViewController : View 관리 및 FrameExtractor, A/V 인코더의 대리자 역할을 하여 인코딩된 결과물을 처리하는 코드가 존재
   - VideoEncoder : Video Raw 데이터를 인코딩 (yuv to H264)
   - AudioEncoder : Audio Raw 데이터를 인코딩 (pcm to aac)
     - 초기화 코드가 없음
   - AVWriter : H.264/AAC 혹은 yuv/pcm 데이터를 로컬 재생 가능한 mp4 형태로 저장
     - 현재는 Audio 없이 Video 만 저장시킬 수 있음
3. Live 탭 : HaishinKit 라이브러리를 이용하여 실시간 HLS 스트리밍 하는 코드가 존재

### Known issue

#### 진행중

1. Init 후 홈화면에 갔다와서 다시 녹화 시 오디오 인코딩 실패, 녹화 종료 시 Crash 발생

   - 원인
     - AudioEncoder 를 초기화 하지 않아 생기는 현상으로 추정

   - 해결방법
     - 초기화 코드 추가 

2. 

#### 해결완료

1. Camera 탭 진입 시 CPU 로드율이 지나치게 높음
   - CPU를 150%까지 로드 (Live 탭의 경우 20% 내외)
   - 원인
     - FrameExtractor 내 에서 카메라 화면을 업데이트 하기 위해 사용 하는 updateView 가 원인
     - updateView의 경우 CMSampleBuffer 데이터를 CMImage로 변환 후 view에 업데이트
     - 1초에 수십번씩 yuv -> image 로 컨버팅하면서 생기는 현상으로 추정 (updateView 비활성화 시 정상적임)
   - 해결방법
     - view 에 직접 업데이트 하는 코드를 지우고, AVCaptureVideoPreviewLayer 를 사용
2. AAC 데이터 AVAssetWriter 에 Input 으로 지정할 경우 파일 저장 안됨
   - 원인
     - 인코딩 후 만든 샘플버퍼에 샘플 사이즈가 없음 (kCMSampleBufferError_BufferHasNoSampleSizes)
     - First input buffer must have an appropriate 에러 발생
   - 해결방법
     - AudioEncoding 후 CMSampleBufferCreate 대신 CMAudioSampleBufferCreateWithPacketDescriptions 호출)
     - kCMSampleBufferAttachmentKey_TrimDurationAtStart 설정
     - 자세한 사항은 참고링크 참고

### TODO

1. addAudioInput, addVideoInput 호출 위치 수정
2. A/V Encoder, AVAssetWriter 초기화 코드 추가

### 참고 링크

1. Video Encoding 관련

   - YUV -> H.264 로 직접 인코딩하는 Flow를 이미지로 설명한 사이트 : https://www.slideshare.net/instinctools_EE_Labs/videostream-compression-in-ios
   - https://gist.github.com/kazz12211/3c8b7aa4c05260298130ba89dde2b22a

2. Audio Encoding 관련

   - "First input buffer must have an appropriate" 에러: https://stackoverflow.com/questions/35425951/cmsamplebufferref-kcmsamplebufferattachmentkey-trimdurationatstart-crash

   - "kCMSampleBufferError_BufferHasNoSampleSizes" 에러 (해결방법은 아래링크) : https://stackoverflow.com/questions/50142384/muxing-aac-audio-and-h-264-video-streams-to-mp4-with-avfoundation 

   - PCM -> AAC 인코딩 -> AVAssetWriter (to save file) 시 주의점, 필수 코딩 사항 :  https://stackoverflow.com/questions/36351327/aac-encoding-using-audioconverter-and-writing-to-avassetwriter
   - AudioConverting 관련 Apple 공식 문서 : https://developer.apple.com/documentation/audiotoolbox/audio_converter_services

3. 그 외 참고자료

   - https://github.com/WowzaMediaSystems/gocoder-sdk-samples-ios/blob/master/SDKSampleApp/MP4Writer.m

   - https://github.com/krad/kubrick/blob/41b1abcb79d58c9e70379bb314187c20ebabcf0f/Sources/kubrick/Encoders/AACEncoder.swift

   - https://ko.wikipedia.org/wiki/비트레이트




---



# DummyUploadServer 

wotjdCam 에서 encoding 된 데이터를 업로드하기 위해 만든 더미 서버

## 빌드 및 실행

NodeJS, Babel 이 설치되어 있어야 함

0. `npm install` 명령어 실행

1. `npm run build` 명령어 실행
   - babel 로 빌드되면서 build 폴더에 컴파일 결과물 생성됨
2. `npm run start` 명령어 실행
   - ip:3000 으로 서버가 실행됨

## 그 외

- 포트 정보는 server/TestServer/index.js 내에 상수로 존재 (`let port = 3000;`)
- 업로드 제한은 5MB
- 업로드 경로 : http://[sip]:3000/upload?type=[video / audio]&pts=[pts value]
- 업로드 시 [서버 경로]/output/[video / audio]/[*.h264 / *.aac] 형태로 저장됨