//
//  AVCaptureSession+VCExtensions.h
//  Pods
//
//  Created by Oleksa 'trimm' Korin on 9/6/16.
//
//

#import <AVFoundation/AVFoundation.h>

typedef void(^AVCaptureSessionConfigurationBlock)(AVCaptureSession *session);

@interface AVCaptureSession (VCExtensions)

- (void)configureWithBlock:(AVCaptureSessionConfigurationBlock)block;

@end
