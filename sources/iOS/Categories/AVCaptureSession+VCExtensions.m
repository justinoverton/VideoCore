//
//  AVCaptureSession+VCExtensions.m
//  Pods
//
//  Created by Oleksa 'trimm' Korin on 9/6/16.
//
//

#import <videocore/sources/iOS/Categories/AVCaptureSession+VCExtensions.h>

@implementation AVCaptureSession (VCExtensions)

- (void)configureWithBlock:(AVCaptureSessionConfigurationBlock)block {
    if (!block) {
        return;
    }
    
    [self beginConfiguration];
    block(self);
    [self commitConfiguration];
}

@end
