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
   - VideoEncoder, AudioEncoder : A/V Raw 데이터를 인코딩 (yuv to H264, pcm to aac)

3. Live 탭 : HaishinKit 라이브러리를 이용하여 실시간 HLS 스트리밍 하는 코드가 존재

