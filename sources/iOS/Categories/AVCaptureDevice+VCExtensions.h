//
//  AVCaptureDevice+VCExtensions.h
//  Pods
//
//  Created by Oleksa 'trimm' Korin on 9/6/16.
//
//

#import <AVFoundation/AVFoundation.h>

typedef void(^AVCaptureDeviceConfigurationBlock)(AVCaptureDevice *device);

@interface AVCaptureDevice (VCExtensions)

- (BOOL)configureWithBlock:(AVCaptureDeviceConfigurationBlock)block;

@end

