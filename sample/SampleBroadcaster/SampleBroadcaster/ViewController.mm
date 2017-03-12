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

#import "ViewController.h"
#import "VCSimpleSession.h"

static NSString * const kRTMPSessionURL = @"rtmp://192.168.0.154:1935/videocore";

@interface ViewController () <VCSessionDelegate> {

}
@property (nonatomic, retain) VCSimpleSession* session;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    CGRect rect = [[UIScreen mainScreen] bounds];
    NSLog(@"Screen rect:%@", NSStringFromCGRect(rect));
    [[NSUserDefaults standardUserDefaults] setValue:@"name_preference" forKey:@"test"];


    _session = [[VCSimpleSession alloc] initWithVideoSize:CGSizeMake(720, 1280) frameRate:30 bitrate:2200000 useInterfaceOrientation:YES];
//    _session.orientationLocked = YES;
    [self.previewView addSubview:_session.previewView];
    _session.previewView.frame = self.previewView.bounds;
    _session.delegate = self;
}

- (void)didReceiveMemoryWarning

{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc {
    [_btnConnect release];
    [_previewView release];
    [_session release];
    
    [super dealloc];
}

- (IBAction)onPause:(id)sender {
    [_session pauseRtmpSession];
}

- (IBAction)flipCamera:(id)sender {
    VCCameraState cameraState = _session.cameraState;
    _session.cameraState = (VCCameraState)((cameraState + 1) % (VCCameraStateBack + 1));
}

- (IBAction)btnConnectTouch:(id)sender {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = [paths.firstObject stringByAppendingPathComponent:@"video3.mp4"];
    
    switch(_session.rtmpSessionState) {
        case VCSessionStateNone:
        case VCSessionStatePreviewStarted:
        case VCSessionStateEnded:
        case VCSessionStateError:
            [_session startRtmpSessionWithURL:kRTMPSessionURL
                                 andStreamKey:@"stream"
                                     filePath:path];
            break;
        case VCSessionStatePaused:
            [_session continueRtmpSessionWithURL:kRTMPSessionURL
                                    andStreamKey:@"stream"];
            break;
        default:
            [_session endRtmpSessionWithCompletionHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [_session.previewView removeFromSuperview];
                    [_session release];
                    
                    _session = [[VCSimpleSession alloc] initWithVideoSize:CGSizeMake(720, 1280) frameRate:30 bitrate:2200000 useInterfaceOrientation:YES];
                    //    _session.orientationLocked = YES;
                    [self.previewView addSubview:_session.previewView];
                    _session.previewView.frame = self.previewView.bounds;
                    _session.delegate = self;
                });
            }];
            break;
    }
}

//Switch with the availables filters
- (IBAction)btnFilterTouch:(id)sender {
    switch (_session.filter) {
        case VCFilterNormal:
            [_session setFilter:VCFilterGray];
            break;
        case VCFilterGray:
            [_session setFilter:VCFilterInvertColors];
            break;
        case VCFilterInvertColors:
            [_session setFilter:VCFilterSepia];
            break;
        case VCFilterSepia:
            [_session setFilter:VCFilterFisheye];
            break;
        case VCFilterFisheye:
            [_session setFilter:VCFilterGlow];
            break;
        case VCFilterGlow:
            [_session setFilter:VCFilterNormal];
            break;
        default:
            break;
    }
}

- (void) connectionStatusChanged:(VCSessionState) state
{
    switch(state) {
        case VCSessionStateStarting:
            [self.btnConnect setTitle:@"Connecting" forState:UIControlStateNormal];
            break;
        case VCSessionStateStarted:
            [self.btnConnect setTitle:@"Disconnect" forState:UIControlStateNormal];
            break;
        case VCSessionStatePaused:
            [self.btnConnect setTitle:@"Continue" forState:UIControlStateNormal];
            break;
        default:
            [self.btnConnect setTitle:@"Connect" forState:UIControlStateNormal];
            break;
    }
}

@end
