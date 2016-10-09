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

#import <videocore/sources/iOS/VCWriter.h>

#import <AVFoundation/AVFoundation.h>

static NSString * const kVCWriterDispatchQueue  = @"kVCWriterDispatchQueue";

@interface VCWriter ()
@property (nonatomic, copy)     NSString            *filePath;
@property (nonatomic, copy)     NSDictionary        *videoSettings;
@property (nonatomic, copy)     NSDictionary        *audioSettings;

@property (nonatomic, strong)   AVAssetWriter       *assetWriter;
@property (nonatomic, strong)   AVAssetWriterInput  *audioInput;
@property (nonatomic, strong)   AVAssetWriterInput  *videoInput;

@property (nonatomic, assign)   dispatch_queue_t    *processingQueue;
@property (nonatomic, assign)   CMTime              videoStartTime;
@property (nonatomic, assign)   CMTime              audioStartTime;

@property (nonatomic, assign)   CMTime              videoLastTime;
@property (nonatomic, assign)   CMTime              audioLastTime;

@property (nonatomic, assign, getter=isAudioContinued)    BOOL    audioContinued;
@property (nonatomic, assign, getter=isVideoContinued)    BOOL    videoContinued;

- (void)encodeAndReleaseSampleBuffer:(CMSampleBufferRef)sampleBuffer withWriterInput:(AVAssetWriterInput *)input;

- (void)dispatchBlock:(void(^)(void))block;
- (void)disposeOfWriter;

- (AVAssetWriterInput *)inputWithType:(NSString *)type settings:(NSDictionary *)settings;

- (void)setValue:(AVAssetWriterInput *)value inInputField:(AVAssetWriterInput **)input;

- (void)deletePreviousFile;

- (CMSampleBufferRef)copySampleBuffer:(CMSampleBufferRef)sampleBuffer withStartTime:(CMTime)startTime;

@end

@implementation VCWriter

@dynamic writing;

#pragma mark -
#pragma mark Class Methods

+ (instancetype)writerWithFilePath:(NSString *)filePath
                     videoSettings:(NSDictionary *)videoSettings
                     audioSettings:(NSDictionary *)audioSettings
{
    id writer = [[self alloc] initWithFilePath:filePath videoSettings:videoSettings audioSettings:audioSettings];
    
    return [writer autorelease];
}

#pragma mark -
#pragma mark Initializations and Deallocations

- (void)dealloc {
    self.filePath = nil;
    
    self.videoSettings = nil;
    self.audioSettings = nil;
    
    [self disposeOfWriter];
    
    self.processingQueue = nil;
    
    [super dealloc];
}


- (instancetype)initWithFilePath:(NSString *)filePath
                   videoSettings:(NSDictionary *)videoSettings
                   audioSettings:(NSDictionary *)audioSettings
{
    self = [super init];
    self.filePath = filePath;
    
    self.videoSettings = videoSettings;
    self.audioSettings = audioSettings;
    
    dispatch_queue_t queue = dispatch_queue_create([kVCWriterDispatchQueue UTF8String], DISPATCH_QUEUE_SERIAL);
    self.processingQueue = queue;
    dispatch_release(queue);
    
    return self;
}

#pragma mark -
#pragma mark Accessors

- (void)setProcessingQueue:(dispatch_queue_t *)processingQueue {
    if (_processingQueue != processingQueue) {
        if (_processingQueue) {
            dispatch_release(_processingQueue);
        }
        
        _processingQueue = processingQueue;
        
        if (_processingQueue) {
            dispatch_retain(_processingQueue);
        }
    }
}

- (BOOL)isWriting {
    return nil != self.assetWriter;
}

- (void)setPaused:(BOOL)paused {
    if (!paused && _paused != paused) {
        self.audioContinued = YES;
        self.videoContinued = YES;
    }
    
    _paused = paused;
}

- (void)setAssetWriter:(AVAssetWriter *)assetWriter {
    if (assetWriter != _assetWriter) {
        [_assetWriter cancelWriting];
        [_assetWriter release];
        _assetWriter = [assetWriter retain];
    }
}

- (void)setAudioInput:(AVAssetWriterInput *)audioInput {
    [self setValue:audioInput inInputField:&_audioInput];
}

- (void)setVideoInput:(AVAssetWriterInput *)videoInput {
    [self setValue:videoInput inInputField:&_videoInput];
}

#pragma mark -
#pragma mark Public

- (void)startWriting {
    if (self.writing) {
        return;
    }
    
    [self dispatchBlock:^{
        self.videoStartTime = kCMTimeInvalid;
        self.audioStartTime = kCMTimeInvalid;
        
        self.videoLastTime = kCMTimeInvalid;
        self.audioLastTime = kCMTimeInvalid;
        
        [self deletePreviousFile];
        
        NSURL *url = [NSURL fileURLWithPath:self.filePath];
        AVAssetWriter *assetWriter = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:nil];
        self.assetWriter = assetWriter;
        self.audioInput = [self inputWithType:AVMediaTypeAudio settings:self.audioSettings];
        self.videoInput = [self inputWithType:AVMediaTypeVideo settings:self.videoSettings];
        
        if ([assetWriter startWriting]) {
            [assetWriter startSessionAtSourceTime:kCMTimeZero];
        }
    }];
}

- (void)finishWritingWithCompletionHandler:(void(^)(void))handler {
    if (!self.writing) {
        return;
    }
    
    [self dispatchBlock:^{
        [self.videoInput markAsFinished];
        [self.audioInput markAsFinished];
        [self.assetWriter finishWritingWithCompletionHandler:^{
            [self disposeOfWriter];
            
            if (handler) {
                handler();
            }
        }];
    }];
}

- (void)cancelWriting {
    if (!self.writing) {
        return;
    }
    
    [self dispatchBlock:^{
        [self.assetWriter cancelWriting];
        
        [self disposeOfWriter];
    }];
}

- (void)encodeVideoBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!self.writing) {
        return;
    }
    
    CMTime startTime = self.videoStartTime;
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);

    if (CMTIME_IS_INVALID(self.videoStartTime)) {
        startTime = timestamp;
        self.videoStartTime = startTime;
        [self printDescription:self.videoStartTime];
    }
    
    if ([self isVideoContinued]) {
        [self printDescription:self.videoStartTime];
        self.videoStartTime = CMTimeAdd(self.videoStartTime,
                                        CMTimeSubtract(timestamp, self.videoLastTime));
        self.videoContinued = NO;
        startTime = self.videoStartTime;
        [self printDescription:self.videoStartTime];
    }
    
    if (![self isPaused]) {
        [self printDescription:self.videoLastTime];
        self.videoLastTime = timestamp;
        [self printDescription:self.videoLastTime];
    }
    
    CMSampleBufferRef copiedBuffer = [self copySampleBuffer:sampleBuffer withStartTime:startTime];
    
    [self encodeAndReleaseSampleBuffer:copiedBuffer withWriterInput:self.videoInput];
}

- (void)printDescription:(CMTime)cmtime {
    NSUInteger dTotalSeconds = CMTimeGetSeconds(cmtime);
    
    NSUInteger dHours = floor(dTotalSeconds / 3600);
    NSUInteger dMinutes = floor(dTotalSeconds % 3600 / 60);
    NSUInteger dSeconds = floor(dTotalSeconds % 3600 % 60);
    
    NSString *videoDurationText = [NSString stringWithFormat:@"%i:%02i:%02i",dHours, dMinutes, dSeconds];
    NSLog(videoDurationText);
}

- (void)encodeAudioBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!self.writing) {
        return;
    }
    
    CMTime startTime = self.audioStartTime;
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    if (CMTIME_IS_INVALID(self.audioStartTime)) {
        [self printDescription:self.audioStartTime];
        startTime = timestamp;
        self.audioStartTime = startTime;
        [self printDescription:self.audioStartTime];
    }
    
    if ([self isAudioContinued]) {
        [self printDescription:self.audioStartTime];
        
        self.audioStartTime = CMTimeAdd(self.audioStartTime,
                                        CMTimeSubtract(timestamp, self.audioLastTime));
        self.audioContinued = NO;
        startTime = self.audioStartTime;
        
        [self printDescription:self.audioStartTime];
    }
    
    if (![self isPaused]) {
        [self printDescription:self.audioLastTime];
        self.audioLastTime = timestamp;
        [self printDescription:self.audioLastTime];
    }
    
    CMSampleBufferRef copiedBuffer = [self copySampleBuffer:sampleBuffer withStartTime:startTime];
    
    [self encodeAndReleaseSampleBuffer:copiedBuffer withWriterInput:self.audioInput];
}

#pragma mark -
#pragma mark Private

- (void)encodeAndReleaseSampleBuffer:(CMSampleBufferRef)sampleBuffer withWriterInput:(AVAssetWriterInput *)input {
        [self dispatchBlock:^{
            if (![self isPaused]) {
                if (CMSampleBufferDataIsReady(sampleBuffer) && input.readyForMoreMediaData) {
                    [input appendSampleBuffer:sampleBuffer];
                }
                
                CFRelease(sampleBuffer);
            } else {
                CFRelease(sampleBuffer);
            }
        }];
}

- (void)dispatchBlock:(void(^)(void))block {
    dispatch_async(self.processingQueue, block);
}

- (void)disposeOfWriter {
    self.assetWriter = nil;
    self.audioInput = nil;
    self.videoInput = nil;
}

- (AVAssetWriterInput *)inputWithType:(NSString *)type settings:(NSDictionary *)settings {
    AVAssetWriterInput *input = [[AVAssetWriterInput alloc] initWithMediaType:type outputSettings:settings];
    input.expectsMediaDataInRealTime = YES;
    
    return input;
}

- (void)setValue:(AVAssetWriterInput *)value inInputField:(AVAssetWriterInput **)input {
    AVAssetWriterInput *currentValue = *input;
    if (currentValue != value) {
        AVAssetWriter *assetWriter = self.assetWriter;
        [currentValue release];
        *input = [value retain];
        
        if ([assetWriter canAddInput:value]) {
            [assetWriter addInput:value];
        }
    }
}

- (void)deletePreviousFile {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *path = self.filePath;
    
    if ([manager fileExistsAtPath:path]) {
        [manager removeItemAtPath:path error:NULL];
    }
}

- (CMSampleBufferRef)copySampleBuffer:(CMSampleBufferRef)sampleBuffer withStartTime:(CMTime)startTime {
    CMSampleTimingInfo timingInfo;
    CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timingInfo);
    
    CMTime time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    timingInfo.presentationTimeStamp = CMTimeSubtract(time, startTime);
    
    CMSampleBufferRef result = NULL;
    CMSampleBufferCreateCopyWithNewTiming(NULL, sampleBuffer, 1, &timingInfo, &result);
    
    return result;
}

@end
