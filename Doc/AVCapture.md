## Audio / Video Capture

From Camera, Microphone

### AVCaptureSession (AVFoundation)

Input 으로부터 받을 수 있는 데이터를 캡쳐하여 Output 에 전달

#### Input (func : addInput)

Input Device 를 지정, AVCaptureDevice 를 획득 및 등록하여 사용

- ***AVCaptureDevice (func : default, ...)***

	Camera, Mic 디바이스 객체

- ***AVCaptureDeviceInput (func : init)***

	디바이스 객체를 세션에 등록하기 위한 객체

#### Output

Output 형태를 지정 (file, frame data, ...)

##### Video

Camera Stream to video raw data (format : yuv)

- ***AVCaptureVideoDataOutput (videoSetting, func : setDelegate)***

  Input 으로부터 넘어오는 Video Raw 데이터를 지정된 Delegate 로 전달 (Delegate.Callback 호출)

  - ***AVCaptureVideoDataOutputSampleBufferDelegate (func : captureOutput)***

    AVCaptureVideoDataOuptut 의 Delegate, captureOuptut 이 callback

##### Audio

Mic Stream to audio raw data (format : pcm)

- ***AVCaptureAudioDataOutput (audioSetting, func : setDelegate)***

  Input 으로부터 넘어오는 Audio Raw 데이터를 지정된 Delegate 로 전달 (Delegate.Callback 호출)

  - ***AVCaptureAudioDataOutputSampleBufferDelegate (func : captureOutput)***

    CaptureAudioDataOuptut 의 Delegate, captureOutput 이 callback

##### Audio, Video 공통

- *captureOutput(_:didOutput:from)*

  캡쳐된 데이터 (프레임, 시간정보, ...)가 CMSampleBuffer 객체로 넘어옴

- *captureOutput(_:didDrop:from)*

  버려진 데이터가 넘어옴

=> AVCaptureConnection 이 넘어오므로 Audio 인지 Video 인지 분별이 가능함

	*AVCaptureConnection : CaptureSesison 에 등록한 Device 정보*

=> Audio, Video 모두 동일한 callback 을 호출하기 때문에 captureOutput 내 에서 분기처리 해야함

### 그 외

#### Preview

- ***AVCaptureVideoPreviewLayer***

## Audio/Video Encoding

From Captured Data (frame)

### Hardware Accelerated Encoding

비디오만 하드웨어 가속 인코딩이 가능 (to h.264)

### Video Encoding

encode yuv to h.264 *(yuv, data from AVCaptureVideoDataOutput)*

#### VTCompressionSession (VideoToolBox)

- VTCompressionSessionCreate

- VTSessionSetProperties

- VTCompressionOutputCallback

- VTCompressionSessionEncodeFrame

### AudioEncoding

encode pcm to aac *(pcm, data from AVCaptureAudioDataOutput)*

#### AudioConverter (AudioToolBox)

- **CMFormatDescription**
  - CMAudioFormatDescriptionCreate

- AudioConverterNewSpecific
- AudioConverterComplexInputDataProc
- AudioConverterFillComplexBuffer

## Muxing

conbine **ecoded audio/video** and subtitle components to container format

### for Local Play

combine A/V data to MP4/MOV format

### for Network Transmission

combine A/V data to TS format



## Protocol

data from **muxed stream** to RTP, HLS, ...