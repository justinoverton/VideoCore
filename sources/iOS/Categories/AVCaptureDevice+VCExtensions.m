//
//  AVCaptureDevice+VCExtensions.m
//  Pods
//
//  Created by Oleksa 'trimm' Korin on 9/6/16.
//
//

#import <videocore/sources/iOS/Categories/AVCaptureDevice+VCExtensions.h>

@implementation AVCaptureDevice (VCExtensions)

- (BOOL)configureWithBlock:(AVCaptureDeviceConfigurationBlock)block {
    if (!block) {
        return YES;
    }
    
    BOOL result = [self lockForConfiguration:NULL];
    if (result) {
        block(self);
        [self unlockForConfiguration];
    }
    
    return result;
}

@end
