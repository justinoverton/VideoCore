/*
 
 Video Core
 Copyright (c) 2014 Oleksa Korin
 
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

#include "CaptureSessionSource.h"

#import <UIKit/UIKit.h>

#import <AVCaptureSession+VCExtensions.h>

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

namespace videocore { namespace iOS {
    dispatch_queue_t CaptureSessionSource::dispatchQueue() {
        static dispatch_queue_t queue = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            queue = dispatch_queue_create("com.videocore.session", 0);
        });
        
        return queue;
    }
    
    AVCaptureSession *CaptureSessionSource::captureSession() {
        static AVCaptureSession *session = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            session = [[AVCaptureSession alloc] init];
        });
        
        return session;
    }
    
        /*! Constructor */
    CaptureSessionSource::CaptureSessionSource()
    :
    m_captureSession(nil),
    m_captureInput(nil),
    m_captureOutput(nil),
    m_captureDevice(nil),
    m_captureOutputDelegate(nil)
    {}
        
        /*! Destructor */
    CaptureSessionSource::~CaptureSessionSource() {
        setCaptureSession(nil);
        setCaptureInput(nil);
        setCaptureOutput(nil);
        setCaptureDevice(nil);
        setCaptureOutputDelegate(nil);
    }
        
        /*! ISource::setOutput */
    void CaptureSessionSource::setOutput(std::shared_ptr<IOutput> output) {
        m_output = output;
    }
        
    void CaptureSessionSource::setup() {
        setCaptureSession(captureSession());
        
        setupCaptureDevice();
        setupCaptureInput();
        setupCaptureOutput();
        setupCaptureOutputDelegate();
        
        [m_captureSession startRunning];
    }
    
    NSArray *CaptureSessionSource::getCaptureDevices() {
        NSMutableArray *devices = [NSMutableArray array];
        
        for(AVCaptureDevice *device in [AVCaptureDevice devices]) {
            if([device hasMediaType:this->mediaType()]) {
                [devices addObject:device];
            }
        }
        
        if (!devices.count) {
            return nil;
        }
        
        return [[devices copy] autorelease];
    }
    
    void CaptureSessionSource::setValueForField(id *field, id value) {
        id currentValue = *field;
        if (currentValue != value) {
            [currentValue release];
            *field = [value retain];
        }
    }

    void CaptureSessionSource::setCaptureInput(id value) {
        setValueForField(&m_captureInput, value);
    }
    
    void CaptureSessionSource::setCaptureOutput(id value) {
        setValueForField(&m_captureOutput, value);
    }
    
    void CaptureSessionSource::setCaptureDevice(id value) {
        setValueForField(&m_captureDevice, value);
    }
    
    void CaptureSessionSource::setCaptureOutputDelegate(id value) {
        setValueForField(&m_captureOutputDelegate, value);
    }
    
    void CaptureSessionSource::setCaptureSession(AVCaptureSession *session) {
        if (m_captureSession != session) {
            [m_captureSession stopRunning];
            removeSessionConnections();
            setValueForField(&m_captureSession, session);
        }
    }
    
    bool CaptureSessionSource::addCaptureInput(AVCaptureInput *input) {
        __block bool result = NO;
        [m_captureSession configureWithBlock:^(AVCaptureSession *session) {
            result = [session canAddInput:input];
            if (result) {
                [session addInput:input];
            }
        }];
        
        return result;
    }
    
    void CaptureSessionSource::removeCaptureInput(AVCaptureInput *input) {
        [m_captureSession configureWithBlock:^(AVCaptureSession *session) {
            [session removeInput:input];
        }];
    }
    
    bool CaptureSessionSource::addCaptureOutput(AVCaptureOutput *output) {
        __block bool result = NO;
        [m_captureSession configureWithBlock:^(AVCaptureSession *session) {
            result = [session canAddOutput:output];
            if (result) {
                [session addOutput:output];
            }
        }];
        
        return result;
    }
    
    void CaptureSessionSource::removeCaptureOutput(AVCaptureOutput *output) {
        [m_captureSession configureWithBlock:^(AVCaptureSession *session) {
            [session removeOutput:output];
        }];
    }
    
    void CaptureSessionSource::removeSessionConnections() {
        removeCaptureInput(m_captureInput);
        removeCaptureOutput(m_captureOutput);
    }
}
}

