/*
 
 Video Core
 Copyright (c) 2014 James G. Hurley
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
 */

#include <videocore/sources/iOS/CameraSource.h>
#include <videocore/mixers/IVideoMixer.hpp>
#include <videocore/system/pixelBuffer/Apple/PixelBuffer.h>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

#import <videocore/sources/iOS/Categories/AVCaptureSession+VCExtensions.h>

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

@interface sbCallback: NSObject<AVCaptureVideoDataOutputSampleBufferDelegate> {
    std::weak_ptr<videocore::iOS::CameraSource> m_source;
}

- (void) setSource:(std::weak_ptr<videocore::iOS::CameraSource>) source;

@end

@implementation sbCallback

- (void)setSource:(std::weak_ptr<videocore::iOS::CameraSource>)source {
    m_source = source;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    auto source = m_source.lock();
    if (source) {
        source->bufferCaptured(sampleBuffer);
    }
}

- (void) captureOutput:(AVCaptureOutput *)captureOutput
   didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
        fromConnection:(AVCaptureConnection *)connection
{
}

- (void) orientationChanged: (NSNotification*) notification
{
    auto source = m_source.lock();
    if (source && !source->orientationLocked()) {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            source->reorientCamera();
        });
    }
}

@end

namespace videocore { namespace iOS {
    
    CameraSource::CameraSource()
    :
    m_matrix(glm::mat4(1.f)),
    m_orientationLocked(false),
    m_torchOn(false),
    m_isFront(false),
    m_useInterfaceOrientation(false)
    {}
    
    CameraSource::~CameraSource() {

    }
    
    void CameraSource::setup(int fps, bool useFront, bool useInterfaceOrientation) {
        m_fps = fps;
        m_useInterfaceOrientation = useInterfaceOrientation;
        m_isFront = useFront;
        
        CaptureSessionSource::setup();
        
        reorientCamera();
    }

    void CameraSource::setupCaptureDevice() {
        AVCaptureDevice *device = cameraWithPosition(captureDevicePosition());
        if ([device lockForConfiguration:NULL]) {
            if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
                CMTime duration = frameDuration();
                device.activeVideoMinFrameDuration = duration;
                device.activeVideoMaxFrameDuration = duration;
            }
        }
        
        setCaptureDevice(device);
    }
    
    void CameraSource::setupCaptureInput() {
        AVCaptureSession *session = m_captureSession;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:m_captureDevice error:NULL];
        if ([session canAddInput:input]) {
            [session addInput:input];
        }
        
        setCaptureInput(input);
    }
    
    void CameraSource::setupCaptureOutput() {
        AVCaptureSession *session = m_captureSession;
        AVCaptureVideoDataOutput *output = [[[AVCaptureVideoDataOutput alloc] init] autorelease];
        output.videoSettings = @{(NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA) };
        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
            AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
            CMTime duration = frameDuration();
            if ([connection isVideoMinFrameDurationSupported]) {
                connection.videoMinFrameDuration = duration;
            }
            
            if ([connection isVideoMaxFrameDurationSupported]) {
                connection.videoMaxFrameDuration = duration;
            }
        }
        
        if ([session canAddOutput:output]) {
            [session addOutput:output];
        }
        
        setCaptureOutput(output);
    }
    
    void CameraSource::setupCaptureOutputDelegate() {
        sbCallback *delegate = [[[sbCallback alloc] init] autorelease];
        
        setCaptureOutputDelegate(delegate);
    }
    
    NSString *CameraSource::mediaType() {
        return AVMediaTypeVideo;
    }

    AVCaptureDevice *CameraSource::cameraWithPosition(int position) {
        for (AVCaptureDevice *device in getCaptureDevices()) {
            if (device.position == position) {
                return device;
            }
        }
        
        return nil;
    }
    
    bool CameraSource::orientationLocked() {
        return m_orientationLocked;
    }
    
    void CameraSource::setOrientationLocked(bool orientationLocked) {
        if (orientationLocked != m_orientationLocked) {
            m_orientationLocked = orientationLocked;
            if (orientationLocked) {
                stopListeningToOrientationChange();
            } else {
                startListeningToOrientationChange();
            }
        }
    }
    
    bool CameraSource::setTorch(bool torchOn) {
        bool result = false;
        AVCaptureSession *session = m_captureSession;
        
        if (!session) {
            return result;
        }
        
        [session beginConfiguration];
        
        AVCaptureDeviceInput *currentCameraInput = m_captureInput;
        if (currentCameraInput) {
            if (currentCameraInput.device.torchAvailable) {
                NSError *error = nil;
                if ([currentCameraInput.device lockForConfiguration:&error]) {
                    [currentCameraInput.device setTorchMode:( torchOn ? AVCaptureTorchModeOn : AVCaptureTorchModeOff ) ];
                    [currentCameraInput.device unlockForConfiguration];
                    result = (currentCameraInput.device.torchMode == AVCaptureTorchModeOn);
                } else {
                    NSLog(@"Error while locking device for torch: %@", error);
                    result = false;
                }
            } else {
                NSLog(@"Torch not available in current camera input");
            }
        }
        
        [session commitConfiguration];
        m_torchOn = result;
        
        return result;
    }
    
    void CameraSource::toggleCamera() {
        AVCaptureSession *session = m_captureSession;
        AVCaptureDevice *captureDevice = m_captureDevice;
        
        if (!session) {
            return;
        }
        
        [session beginConfiguration];
        
        AVCaptureDeviceInput *currentCameraInput = m_captureInput;
        if ([captureDevice lockForConfiguration:NULL] && currentCameraInput) {
            [session removeInput:currentCameraInput];
            [captureDevice unlockForConfiguration];
            
            m_isFront = !m_isFront;
            AVCaptureDevice *newCamera = cameraWithPosition(captureDevicePosition());
            
            setCaptureDevice(newCamera);
            
            AVCaptureDeviceInput *newVideoInput = [[[AVCaptureDeviceInput alloc] initWithDevice:newCamera error:nil] autorelease];
            [newCamera lockForConfiguration:NULL];
            if ([session canAddInput:newVideoInput]) {
                [session addInput:newVideoInput];
            }
            
            [newCamera unlockForConfiguration];
            
            setCaptureInput(newVideoInput);
        }
        
        [session commitConfiguration];
        
        reorientCamera();
    }
    
    void CameraSource::reorientCamera() {
        AVCaptureSession *session = m_captureSession;
        if (!session) {
            return;
        }
        
        auto orientation = m_useInterfaceOrientation ? [[UIApplication sharedApplication] statusBarOrientation] : [[UIDevice currentDevice] orientation];
        
        // use interface orientation as fallback if device orientation is facedown, faceup or unknown
        if (orientation == UIDeviceOrientationFaceDown
            || orientation == UIDeviceOrientationFaceUp
            || orientation == UIDeviceOrientationUnknown)
        {
            orientation = [[UIApplication sharedApplication] statusBarOrientation];
        }
        
        AVCaptureVideoOrientation videoOrientation = videoOrientationForInterfaceOrientation(orientation);
        
        // [session beginConfiguration];
        
        for (AVCaptureVideoDataOutput *output in session.outputs) {
            for (AVCaptureConnection *connection in output.connections) {
                connection.videoOrientation = videoOrientation;
            }
        }

        //[session commitConfiguration];
        if (m_torchOn) {
            setTorch(m_torchOn);
        }
    }
    
    AVCaptureVideoOrientation CameraSource::videoOrientationForInterfaceOrientation(long orientation) {
        switch (orientation) {
                // UIInterfaceOrientationPortraitUpsideDown, UIDeviceOrientationPortraitUpsideDown
            case UIInterfaceOrientationPortraitUpsideDown:
                return AVCaptureVideoOrientationPortraitUpsideDown;
                
                // UIInterfaceOrientationLandscapeRight, UIDeviceOrientationLandscapeLeft
            case UIInterfaceOrientationLandscapeRight:
                return AVCaptureVideoOrientationLandscapeRight;
                
                // UIInterfaceOrientationLandscapeLeft, UIDeviceOrientationLandscapeRight
            case UIInterfaceOrientationLandscapeLeft:
                return AVCaptureVideoOrientationLandscapeLeft;
                
                // UIInterfaceOrientationPortrait, UIDeviceOrientationPortrait
            case UIInterfaceOrientationPortrait:
                return AVCaptureVideoOrientationPortrait;
                
            default:
                return AVCaptureVideoOrientationPortrait;
        }
    }

    void CameraSource::bufferCaptured(CMSampleBufferRef sampleBuffer) {
        auto output = m_output.lock();
        if (output) {
            
            VideoBufferMetadata md(1.f / float(m_fps));
            
            md.setData(1, m_matrix, false, shared_from_this());
            
            auto pixelBuffer = std::make_shared<Apple::PixelBuffer>(CMSampleBufferGetImageBuffer(sampleBuffer) , true);
            
            pixelBuffer->setState(kVCPixelBufferStateEnqueued);
            output->pushBuffer((uint8_t*)&pixelBuffer, sizeof(pixelBuffer), md);
        }
    }
    
    bool CameraSource::setContinuousAutofocus(bool wantsContinuous) {
        AVCaptureDevice *device = (AVCaptureDevice *)m_captureDevice;
        AVCaptureFocusMode newMode = wantsContinuous ?  AVCaptureFocusModeContinuousAutoFocus : AVCaptureFocusModeAutoFocus;
        bool result = [device isFocusModeSupported:newMode];

        if (result) {
            NSError *error = nil;
            if ([device lockForConfiguration:&error]) {
                device.focusMode = newMode;
                [device unlockForConfiguration];
            } else {
                NSLog(@"Error while locking device for autofocus: %@", error);
                result = false;
            }
        } else {
            NSLog(@"Focus mode not supported: %@", wantsContinuous ? @"AVCaptureFocusModeContinuousAutoFocus" : @"AVCaptureFocusModeAutoFocus");
        }

        return result;
    }

    bool CameraSource::setContinuousExposure(bool wantsContinuous) {
        AVCaptureDevice *device = (AVCaptureDevice *)m_captureDevice;
        AVCaptureExposureMode newMode = wantsContinuous ? AVCaptureExposureModeContinuousAutoExposure : AVCaptureExposureModeAutoExpose;
        bool result = [device isExposureModeSupported:newMode];

        if (result) {
            NSError *error = nil;
            if ([device lockForConfiguration:&error]) {
                device.exposureMode = newMode;
                [device unlockForConfiguration];
            } else {
                NSLog(@"Error while locking device for exposure: %@", error);
                result = false;
            }
        } else {
            NSLog(@"Exposure mode not supported: %@", wantsContinuous ? @"AVCaptureExposureModeContinuousAutoExposure" : @"AVCaptureExposureModeAutoExpose");
        }

        return result;
    }
    
    bool CameraSource::setFocusPointOfInterest(float x, float y) {
        AVCaptureDevice* device = (AVCaptureDevice*)m_captureDevice;
        bool result = device.focusPointOfInterestSupported;
        
        if (result) {
            NSError* error = nil;
            if ([device lockForConfiguration:&error]) {
                [device setFocusPointOfInterest:CGPointMake(x, y)];
                if (device.focusMode == AVCaptureFocusModeLocked) {
                    [device setFocusMode:AVCaptureFocusModeAutoFocus];
                }
                device.focusMode = device.focusMode;
                [device unlockForConfiguration];
            } else {
                NSLog(@"Error while locking device for focus POI: %@", error);
                result = false;
            }
        } else {
            NSLog(@"Focus POI not supported");
        }
        
        return result;
    }
    
    bool CameraSource::setExposurePointOfInterest(float x, float y) {
        AVCaptureDevice* device = (AVCaptureDevice *)m_captureDevice;
        bool result = device.exposurePointOfInterestSupported;
        
        if (result) {
            NSError* error = nil;
            if ([device lockForConfiguration:&error]) {
                [device setExposurePointOfInterest:CGPointMake(x, y)];
                device.exposureMode = device.exposureMode;
                [device unlockForConfiguration];
            } else {
                NSLog(@"Error while locking device for exposure POI: %@", error);
                result = false;
            }
        } else {
            NSLog(@"Exposure POI not supported");
        }
        
        return result;
    }
    
    void CameraSource::setCaptureOutputDelegate(id value) {
        if (value != m_captureOutputDelegate) {
            [m_captureOutputDelegate setSource:std::weak_ptr<CameraSource>()];
            stopListeningToOrientationChange();
            
            CaptureSessionSource::setCaptureOutputDelegate(value);
            
            [value setSource:std::static_pointer_cast<CameraSource>(shared_from_this())];
            startListeningToOrientationChange();
            
            [m_captureOutput setSampleBufferDelegate:value queue:dispatchQueue()];
        }
    }
    
    void CameraSource::startListeningToOrientationChange() {
        if (m_orientationLocked) {
            return;
        }

        bool useInterfaceOrientation = m_useInterfaceOrientation;
        NSString *notificationName = useInterfaceOrientation
            ? UIApplicationDidChangeStatusBarOrientationNotification
            : UIDeviceOrientationDidChangeNotification;
        
        if (!useInterfaceOrientation) {
            [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        }
        
        id delegate = m_captureOutputDelegate;
        if (delegate) {
            [[NSNotificationCenter defaultCenter] addObserver:delegate
                                                     selector:@selector(orientationChanged:)
                                                         name:notificationName
                                                       object:nil];
        }
    }
    
    void CameraSource::stopListeningToOrientationChange() {
        if (!m_orientationLocked) {
            return;
        }
        
        bool useInterfaceOrientation = m_useInterfaceOrientation;
        NSString *notificationName = useInterfaceOrientation
            ? UIApplicationDidChangeStatusBarOrientationNotification
            : UIDeviceOrientationDidChangeNotification;
        
        if (!useInterfaceOrientation) {
            [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
        }
        
        id delegate = m_captureOutputDelegate;
        if (delegate) {
            [[NSNotificationCenter defaultCenter] removeObserver:delegate name:notificationName object:nil];
        }
    }
    
    AVCaptureDevicePosition CameraSource::captureDevicePosition() {
        return m_isFront ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    }
    
    CMTime CameraSource::frameDuration() {
        return CMTimeMake(1, m_fps);
    }
    
}
}
