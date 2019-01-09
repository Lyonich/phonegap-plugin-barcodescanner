/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 *
 * Copyright 2011 Matt Kane. All rights reserved.
 * Copyright (c) 2011, IBM Corporation
 */

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <Cordova/CDVPlugin.h>

#define MASK_CAMERA_WIDTH    295.0f
#define MASK_CAMERA_HEIGHT    185.0f
#define MASK_CAMERA_THICKNESS    3.0f
#define MASK_CAMERA_INSET    50.0f
#define MASK_CAMERA_VERTICAL_INSET    30.0f

//------------------------------------------------------------------------------
// Delegate to handle orientation functions
//------------------------------------------------------------------------------
@protocol CDVBarcodeScannerOrientationDelegate <NSObject>

- (NSUInteger)supportedInterfaceOrientations;
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (BOOL)shouldAutorotate;

@end

//------------------------------------------------------------------------------
// Adds a shutter button to the UI, and changes the scan from continuous to
// only performing a scan when you click the shutter button.  For testing.
//------------------------------------------------------------------------------
#define USE_SHUTTER 0

//------------------------------------------------------------------------------
@class CDVbcsProcessor;
@class CDVbcsViewController;

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@interface CDVBarcodeScanner : CDVPlugin {}
- (NSString*)isScanNotPossible;
- (void)scan:(CDVInvokedUrlCommand*)command;
- (void)encode:(CDVInvokedUrlCommand*)command;
- (void)returnImage:(NSString*)filePath format:(NSString*)format callback:(NSString*)callback;
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback isBackButton:(BOOL)isBackButton;
- (void)returnError:(NSString*)message callback:(NSString*)callback;
@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@interface CDVbcsProcessor : NSObject <AVCaptureMetadataOutputObjectsDelegate> {}
@property (nonatomic, retain) CDVBarcodeScanner*           plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) UIViewController*           parentViewController;
@property (nonatomic, retain) CDVbcsViewController*        viewController;
@property (nonatomic, retain) AVCaptureSession*           captureSession;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, retain) NSString*                   alternateXib;
@property (nonatomic, retain) NSMutableArray*             results;
@property (nonatomic, retain) NSString*                   formats;
@property (nonatomic)         BOOL                        is1D;
@property (nonatomic)         BOOL                        is2D;
@property (nonatomic)         BOOL                        capturing;
@property (nonatomic)         BOOL                        isFrontCamera;
@property (nonatomic)         BOOL                        isShowFlipCameraButton;
@property (nonatomic)         BOOL                        isShowTorchButton;
@property (nonatomic)         BOOL                        isFlipped;
@property (nonatomic)         BOOL                        isTransitionAnimated;
@property (nonatomic)         BOOL                        isSuccessBeepEnabled;

@property (nonatomic, strong) NSString*    localizedScanCode;
@property (nonatomic, strong) NSString*    localizedPositionTheFrame;
@property (nonatomic, strong) NSString*    localizedAvoidGlares;
@property (nonatomic, strong) NSString*    localizedEnterCode;


- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback parentViewController:(UIViewController*)parentViewController alterateOverlayXib:(NSString *)alternateXib;
- (void)scanBarcode;
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format;
- (void)barcodeScanFailed:(NSString*)message;
- (void)barcodeScanCancelled;
- (void)openDialog;
- (NSString*)setUpCaptureSession;
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection;
@end

#pragma mark -  Qr encoder processor

@interface CDVqrProcessor: NSObject
@property (nonatomic, retain) CDVBarcodeScanner*          plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) NSString*                   stringToEncode;
@property                     NSInteger                   size;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback stringToEncode:(NSString*)stringToEncode;
- (void)generateImage;
@end

#pragma mark -  view controller for the ui

@interface CDVbcsViewController : UIViewController <CDVBarcodeScannerOrientationDelegate> {}
@property (nonatomic, retain) CDVbcsProcessor*  processor;
@property (nonatomic, retain) NSString*        alternateXib;
@property (nonatomic)         BOOL             shutterPressed;
@property (nonatomic, retain) IBOutlet UIView* overlayView;
//@property (nonatomic, retain) UIToolbar * toolbar;
@property (nonatomic, retain) UIImageView * reticleView;
// unsafe_unretained is equivalent to assign - used to prevent retain cycles in the property below
@property (nonatomic, unsafe_unretained) id orientationDelegate;

- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib;
- (void)startCapturing;
- (UIView*)buildOverlayView;
- (UIImage*)buildReticleImage;
- (void)shutterButtonPressed;
- (IBAction)cancelButtonPressed:(id)sender;
- (IBAction)flipCameraButtonPressed:(id)sender;
- (IBAction)torchButtonPressed:(id)sender;

@end

#pragma mark -  plugin class

@implementation CDVBarcodeScanner

//--------------------------------------------------------------------------
- (NSString*)isScanNotPossible {
    NSString* result = nil;

    Class aClass = NSClassFromString(@"AVCaptureSession");
    if (aClass == nil) {
        return @"AVFoundation Framework not available";
    }

    return result;
}

-(BOOL)notHasPermission {
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    return (authStatus == AVAuthorizationStatusDenied ||
            authStatus == AVAuthorizationStatusRestricted);
}

-(BOOL)isUsageDescriptionSet {
    NSDictionary * plist = [[NSBundle mainBundle] infoDictionary];
    if ([plist objectForKey:@"NSCameraUsageDescription" ]) {
        return YES;
    }
    return NO;
}

- (void)scan:(CDVInvokedUrlCommand*)command {
    CDVbcsProcessor* processor;
    NSString*       callback;
    NSString*       capabilityError;

    callback = command.callbackId;

    NSDictionary* options;
    if (command.arguments.count == 0) {
        options = [NSDictionary dictionary];
    } else {
        options = command.arguments[0];
    }

    processor.localizedScanCode = [options[@"ScanCode"] stringValue];
    processor.localizedPositionTheFrame = [options[@"PositionTheFrame"] stringValue];
    processor.localizedEnterCode = [options[@"EnterCode"] stringValue];
    processor.localizedAvoidGlares = [options[@"AvoidGlares"] stringValue];

    BOOL preferFrontCamera = [options[@"preferFrontCamera"] boolValue];
    BOOL showFlipCameraButton = [options[@"showFlipCameraButton"] boolValue];
    BOOL showTorchButton = [options[@"showTorchButton"] boolValue];
    BOOL disableAnimations = [options[@"disableAnimations"] boolValue];
    BOOL disableSuccessBeep = [options[@"disableSuccessBeep"] boolValue];

    // We allow the user to define an alternate xib file for loading the overlay.
    NSString *overlayXib = options[@"overlayXib"];

    capabilityError = [self isScanNotPossible];
    if (capabilityError) {
        [self returnError:capabilityError callback:callback];
        return;
    } else if ([self notHasPermission]) {
        NSString * error = NSLocalizedString(@"Access to the camera has been prohibited; please enable it in the Settings app to continue.",nil);
        [self returnError:error callback:callback];
        return;
    } else if (![self isUsageDescriptionSet]) {
        NSString * error = NSLocalizedString(@"NSCameraUsageDescription is not set in the info.plist", nil);
        [self returnError:error callback:callback];
        return;
    }

    processor = [[CDVbcsProcessor alloc]
                 initWithPlugin:self
                 callback:callback
                 parentViewController:self.viewController
                 alterateOverlayXib:overlayXib
                 ];
    // queue [processor scanBarcode] to run on the event loop

    if (preferFrontCamera) {
        processor.isFrontCamera = true;
    }

    if (showFlipCameraButton) {
        processor.isShowFlipCameraButton = true;
    }

    if (showTorchButton) {
        processor.isShowTorchButton = true;
    }

    processor.isSuccessBeepEnabled = !disableSuccessBeep;
    processor.isTransitionAnimated = !disableAnimations;
    processor.formats = options[@"formats"];

    [processor performSelector:@selector(scanBarcode) withObject:nil afterDelay:0];
}

- (void)encode:(CDVInvokedUrlCommand*)command {
    if([command.arguments count] < 1)
        [self returnError:@"Too few arguments!" callback:command.callbackId];

    CDVqrProcessor* processor;
    NSString*       callback;
    callback = command.callbackId;

    processor = [[CDVqrProcessor alloc]
                 initWithPlugin:self
                 callback:callback
                 stringToEncode: command.arguments[0][@"data"]
                 ];
    // queue [processor generateImage] to run on the event loop
    [processor performSelector:@selector(generateImage) withObject:nil afterDelay:0];
}

- (void)returnImage:(NSString*)filePath format:(NSString*)format callback:(NSString*)callback{
    NSMutableDictionary* resultDict = [[NSMutableDictionary alloc] init];
    resultDict[@"format"] = format;
    resultDict[@"file"] = filePath;

    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary:resultDict
                               ];

    [[self commandDelegate] sendPluginResult:result callbackId:callback];
}

- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback isBackButton:(BOOL)isBackButton {
    NSNumber* cancelledNumber = @(cancelled ? 1 : 0);
    NSNumber* isBackButtonNumber = @(isBackButton ? 1 : 0);

    NSMutableDictionary* resultDict = [NSMutableDictionary new];
    resultDict[@"text"] = scannedText;
    resultDict[@"format"] = format;
    resultDict[@"cancelled"] = cancelledNumber;
    resultDict[@"isBackButton"] = isBackButtonNumber;


    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary: resultDict
                               ];
    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

- (void)returnError:(NSString*)message callback:(NSString*)callback {
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_ERROR
                               messageAsString: message
                               ];

    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

@end

#pragma mark -  class that does the grunt work

@implementation CDVbcsProcessor

@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize parentViewController = _parentViewController;
@synthesize viewController       = _viewController;
@synthesize captureSession       = _captureSession;
@synthesize previewLayer         = _previewLayer;
@synthesize alternateXib         = _alternateXib;
@synthesize is1D                 = _is1D;
@synthesize is2D                 = _is2D;
@synthesize capturing            = _capturing;
@synthesize results              = _results;

SystemSoundID _soundFileObject;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin
            callback:(NSString*)callback
parentViewController:(UIViewController*)parentViewController
  alterateOverlayXib:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;

    self.plugin               = plugin;
    self.callback             = callback;
    self.parentViewController = parentViewController;
    self.alternateXib         = alternateXib;

    self.is1D      = YES;
    self.is2D      = YES;
    self.capturing = NO;
    self.results = [NSMutableArray new];

    CFURLRef soundFileURLRef  = CFBundleCopyResourceURL(CFBundleGetMainBundle(), CFSTR("CDVBarcodeScanner.bundle/beep"), CFSTR ("caf"), NULL);
    AudioServicesCreateSystemSoundID(soundFileURLRef, &_soundFileObject);

    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.parentViewController = nil;
    self.viewController = nil;
    self.captureSession = nil;
    self.previewLayer = nil;
    self.alternateXib = nil;
    self.results = nil;

    self.capturing = NO;

    AudioServicesRemoveSystemSoundCompletion(_soundFileObject);
    AudioServicesDisposeSystemSoundID(_soundFileObject);
}

//--------------------------------------------------------------------------
- (void)scanBarcode {

    //    self.captureSession = nil;
    //    self.previewLayer = nil;
    NSString* errorMessage = [self setUpCaptureSession];
    if (errorMessage) {
        [self barcodeScanFailed:errorMessage];
        return;
    }

    self.viewController = [[CDVbcsViewController alloc] initWithProcessor: self alternateOverlay:self.alternateXib];
    // here we set the orientation delegate to the MainViewController of the app (orientation controlled in the Project Settings)
    self.viewController.orientationDelegate = self.plugin.viewController;

    // delayed [self openDialog];
    [self performSelector:@selector(openDialog) withObject:nil afterDelay:1];
}

//--------------------------------------------------------------------------
- (void)openDialog {
    [self.parentViewController
     presentViewController:self.viewController
     animated:self.isTransitionAnimated completion:nil
     ];
}

- (void)barcodeScanDone:(void (^)(void))callbackBlock {
    self.capturing = NO;
    [self.captureSession stopRunning];
    [self.parentViewController dismissViewControllerAnimated:self.isTransitionAnimated completion:callbackBlock];

    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [device lockForConfiguration:nil];
    if([device isAutoFocusRangeRestrictionSupported]) {
        [device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNone];
    }
    [device unlockForConfiguration];

    // viewcontroller holding onto a reference to us, release them so they
    // will release us
    self.viewController = nil;
}

//--------------------------------------------------------------------------
- (BOOL)checkResult:(NSString *)result {
    [self.results addObject:result];

    NSInteger treshold = 7;

    if (self.results.count > treshold) {
        [self.results removeObjectAtIndex:0];
    }

    if (self.results.count < treshold) {
        return NO;
    }

    BOOL allEqual = YES;
    NSString *compareString = self.results[0];

    for (NSString *aResult in self.results) {
        if (![compareString isEqualToString:aResult]) {
            allEqual = NO;
            //NSLog(@"Did not fit: %@",self.results);
            break;
        }
    }

    return allEqual;
}

//--------------------------------------------------------------------------
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format {
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (self.isSuccessBeepEnabled) {
            AudioServicesPlaySystemSound(_soundFileObject);
        }
        [self barcodeScanDone:^{
            [self.plugin returnSuccess:text format:format cancelled:FALSE flipped:FALSE callback:self.callback isBackButton:FALSE];
        }];
    });
}

//--------------------------------------------------------------------------
- (void)barcodeScanFailed:(NSString*)message {
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self barcodeScanDone:^{
            [self.plugin returnError:message callback:self.callback];
        }];
    });
}

//--------------------------------------------------------------------------
- (void)barcodeScanCancelled {
    [self barcodeScanDone:^{
        [self.plugin returnSuccess:@"" format:@"" cancelled:TRUE flipped:self.isFlipped callback:self.callback isBackButton:FALSE];
    }];
    if (self.isFlipped) {
        self.isFlipped = NO;
    }
}

- (void)flipCamera {
    self.isFlipped = YES;
    self.isFrontCamera = !self.isFrontCamera;
    [self barcodeScanDone:^{
        if (self.isFlipped) {
            self.isFlipped = NO;
        }
        [self performSelector:@selector(scanBarcode) withObject:nil afterDelay:0.1];
    }];
}

- (void)toggleTorch {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [device lockForConfiguration:nil];
    if (device.flashActive) {
        [device setTorchMode:AVCaptureTorchModeOff];
        [device setFlashMode:AVCaptureFlashModeOff];
    } else {
        [device setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:nil];
        [device setFlashMode:AVCaptureFlashModeOn];
    }
    [device unlockForConfiguration];
}

//--------------------------------------------------------------------------
- (NSString*)setUpCaptureSession {
    NSError* error = nil;

    AVCaptureSession* captureSession = [[AVCaptureSession alloc] init];
    self.captureSession = captureSession;

    AVCaptureDevice* __block device = nil;
    if (self.isFrontCamera) {

        NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        [devices enumerateObjectsUsingBlock:^(AVCaptureDevice *obj, NSUInteger idx, BOOL *stop) {
            if (obj.position == AVCaptureDevicePositionFront) {
                device = obj;
            }
        }];
    } else {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (!device) return @"unable to obtain video capture device";

    }

    // set focus params if available to improve focusing
    [device lockForConfiguration:&error];
    if (error == nil) {
        if([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        }
        if([device isAutoFocusRangeRestrictionSupported]) {
            [device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNear];
        }
    }
    [device unlockForConfiguration];

    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) return @"unable to obtain video capture device input";

    AVCaptureMetadataOutput* output = [[AVCaptureMetadataOutput alloc] init];
    if (!output) return @"unable to obtain video capture output";

    [output setMetadataObjectsDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)];

    if ([captureSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
        captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    } else if ([captureSession canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    } else {
        return @"unable to preset high nor medium quality video capture";
    }

    if ([captureSession canAddInput:input]) {
        [captureSession addInput:input];
    }
    else {
        return @"unable to add video capture device input to session";
    }

    if ([captureSession canAddOutput:output]) {
        [captureSession addOutput:output];
    }
    else {
        return @"unable to add video capture output to session";
    }

    [output setMetadataObjectTypes:[self formatObjectTypes]];

    // setup capture preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    // run on next event loop pass [captureSession startRunning]
    [captureSession performSelector:@selector(startRunning) withObject:nil afterDelay:0];

    return nil;
}

//--------------------------------------------------------------------------
// this method gets sent the captured frames
//--------------------------------------------------------------------------
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection*)connection {

    if (!self.capturing) return;

#if USE_SHUTTER
    if (!self.viewController.shutterPressed) return;
    self.viewController.shutterPressed = NO;

    UIView* flashView = [[UIView alloc] initWithFrame:self.viewController.view.frame];
    [flashView setBackgroundColor:[UIColor whiteColor]];
    [self.viewController.view.window addSubview:flashView];

    [UIView
     animateWithDuration:.4f
     animations:^{
         [flashView setAlpha:0.f];
     }
     completion:^(BOOL finished){
         [flashView removeFromSuperview];
     }
     ];
#endif


    try {
        // This will bring in multiple entities if there are multiple 2D codes in frame.
        for (AVMetadataObject *metaData in metadataObjects) {
            AVMetadataMachineReadableCodeObject* code = (AVMetadataMachineReadableCodeObject*)[self.previewLayer transformedMetadataObjectForMetadataObject:(AVMetadataMachineReadableCodeObject*)metaData];

            if ([self checkResult:code.stringValue]) {
                [self barcodeScanSucceeded:code.stringValue format:[self formatStringFromMetadata:code]];
            }
        }
    }
    catch (...) {
        //            NSLog(@"decoding: unknown exception");
        //            [self barcodeScanFailed:@"unknown exception decoding barcode"];
    }

    //        NSTimeInterval timeElapsed  = [NSDate timeIntervalSinceReferenceDate] - timeStart;
    //        NSLog(@"decoding completed in %dms", (int) (timeElapsed * 1000));

}

//--------------------------------------------------------------------------
// convert metadata object information to barcode format string
//--------------------------------------------------------------------------
- (NSString*)formatStringFromMetadata:(AVMetadataMachineReadableCodeObject*)format {
    if (format.type == AVMetadataObjectTypeQRCode)          return @"QR_CODE";
    if (format.type == AVMetadataObjectTypeAztecCode)       return @"AZTEC";
    if (format.type == AVMetadataObjectTypeDataMatrixCode)  return @"DATA_MATRIX";
    if (format.type == AVMetadataObjectTypeUPCECode)        return @"UPC_E";
    // According to Apple documentation, UPC_A is EAN13 with a leading 0.
    if (format.type == AVMetadataObjectTypeEAN13Code && [format.stringValue characterAtIndex:0] == '0') return @"UPC_A";
    if (format.type == AVMetadataObjectTypeEAN8Code)        return @"EAN_8";
    if (format.type == AVMetadataObjectTypeEAN13Code)       return @"EAN_13";
    if (format.type == AVMetadataObjectTypeCode128Code)     return @"CODE_128";
    if (format.type == AVMetadataObjectTypeCode93Code)      return @"CODE_93";
    if (format.type == AVMetadataObjectTypeCode39Code)      return @"CODE_39";
    if (format.type == AVMetadataObjectTypeInterleaved2of5Code) return @"ITF";
    if (format.type == AVMetadataObjectTypeITF14Code)          return @"ITF_14";

    if (format.type == AVMetadataObjectTypePDF417Code)      return @"PDF_417";
    return @"???";
}

//--------------------------------------------------------------------------
// convert string formats to metadata objects
//--------------------------------------------------------------------------
- (NSArray*) formatObjectTypes {
    NSArray *supportedFormats = nil;
    if (self.formats != nil) {
        supportedFormats = [self.formats componentsSeparatedByString:@","];
    }

    NSMutableArray * formatObjectTypes = [NSMutableArray array];

    if (self.formats == nil || [supportedFormats containsObject:@"QR_CODE"]) [formatObjectTypes addObject:AVMetadataObjectTypeQRCode];
    if (self.formats == nil || [supportedFormats containsObject:@"AZTEC"]) [formatObjectTypes addObject:AVMetadataObjectTypeAztecCode];
    if (self.formats == nil || [supportedFormats containsObject:@"DATA_MATRIX"]) [formatObjectTypes addObject:AVMetadataObjectTypeDataMatrixCode];
    if (self.formats == nil || [supportedFormats containsObject:@"UPC_E"]) [formatObjectTypes addObject:AVMetadataObjectTypeUPCECode];
    if (self.formats == nil || [supportedFormats containsObject:@"EAN_8"]) [formatObjectTypes addObject:AVMetadataObjectTypeEAN8Code];
    if (self.formats == nil || [supportedFormats containsObject:@"EAN_13"]) [formatObjectTypes addObject:AVMetadataObjectTypeEAN13Code];
    if (self.formats == nil || [supportedFormats containsObject:@"CODE_128"]) [formatObjectTypes addObject:AVMetadataObjectTypeCode128Code];
    if (self.formats == nil || [supportedFormats containsObject:@"CODE_93"]) [formatObjectTypes addObject:AVMetadataObjectTypeCode93Code];
    if (self.formats == nil || [supportedFormats containsObject:@"CODE_39"]) [formatObjectTypes addObject:AVMetadataObjectTypeCode39Code];
    if (self.formats == nil || [supportedFormats containsObject:@"ITF"]) [formatObjectTypes addObject:AVMetadataObjectTypeInterleaved2of5Code];
    if (self.formats == nil || [supportedFormats containsObject:@"ITF_14"]) [formatObjectTypes addObject:AVMetadataObjectTypeITF14Code];
    if (self.formats == nil || [supportedFormats containsObject:@"PDF_417"]) [formatObjectTypes addObject:AVMetadataObjectTypePDF417Code];

    return formatObjectTypes;
}

@end

//------------------------------------------------------------------------------
// qr encoder processor
//------------------------------------------------------------------------------
@implementation CDVqrProcessor
@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize stringToEncode       = _stringToEncode;
@synthesize size                 = _size;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback stringToEncode:(NSString*)stringToEncode{
    self = [super init];
    if (!self) return self;

    self.plugin          = plugin;
    self.callback        = callback;
    self.stringToEncode  = stringToEncode;
    self.size            = 300;

    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.stringToEncode = nil;
}
//--------------------------------------------------------------------------
- (void)generateImage{
    /* setup qr filter */
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];

    /* set filter's input message
     * the encoding string has to be convert to a UTF-8 encoded NSData object */
    [filter setValue:[self.stringToEncode dataUsingEncoding:NSUTF8StringEncoding]
              forKey:@"inputMessage"];

    /* on ios >= 7.0  set low image error correction level */
    if (floor(NSFoundationVersionNumber) >= NSFoundationVersionNumber_iOS_7_0)
        [filter setValue:@"L" forKey:@"inputCorrectionLevel"];

    /* prepare cgImage */
    CIImage *outputImage = [filter outputImage];
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:outputImage
                                       fromRect:[outputImage extent]];

    /* returned qr code image */
    UIImage *qrImage = [UIImage imageWithCGImage:cgImage
                                           scale:1.
                                     orientation:UIImageOrientationUp];
    /* resize generated image */
    CGFloat width = _size;
    CGFloat height = _size;

    UIGraphicsBeginImageContext(CGSizeMake(width, height));

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    [qrImage drawInRect:CGRectMake(0, 0, width, height)];
    qrImage = UIGraphicsGetImageFromCurrentImageContext();

    /* clean up */
    UIGraphicsEndImageContext();
    CGImageRelease(cgImage);

    /* save image to file */
    NSString* fileName = [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingString:@".jpg"];
    NSString* filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    [UIImageJPEGRepresentation(qrImage, 1.0) writeToFile:filePath atomically:YES];

    /* return file path back to cordova */
    [self.plugin returnImage:filePath format:@"QR_CODE" callback: self.callback];
}
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@implementation CDVbcsViewController
@synthesize processor      = _processor;
@synthesize shutterPressed = _shutterPressed;
@synthesize alternateXib   = _alternateXib;
@synthesize overlayView    = _overlayView;

// CHANGE CAMERA OFFSET HERE
CGFloat scanOffset = 40;

//--------------------------------------------------------------------------
- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;

    self.processor = processor;
    self.shutterPressed = NO;
    self.alternateXib = alternateXib;
    self.overlayView = nil;
    return self;
}

- (void)dealloc {
    self.view = nil;
    self.processor = nil;
    self.shutterPressed = NO;
    self.alternateXib = nil;
    self.overlayView = nil;
}

//--------------------------------------------------------------------------
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame: self.processor.parentViewController.view.frame];
}

//--------------------------------------------------------------------------
- (void)viewWillAppear:(BOOL)animated {
    // set video orientation to what the camera sees
    self.processor.previewLayer.connection.videoOrientation = (AVCaptureVideoOrientation) [[UIApplication sharedApplication] statusBarOrientation];

    // this fixes the bug when the statusbar is landscape, and the preview layer
    // starts up in portrait (not filling the whole view)
    self.processor.previewLayer.frame = self.view.bounds;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(avCaptureInputPortFormatDescriptionDidChangeNotification:) name:AVCaptureInputPortFormatDescriptionDidChangeNotification object:nil];
}

- (IBAction)avCaptureInputPortFormatDescriptionDidChangeNotification:(id)sender {
    AVCaptureMetadataOutput* output = self.processor.previewLayer.session.outputs[0];
    //VERY IMPORTANT!!! scan area is changed only here
    output.rectOfInterest = [self.processor.previewLayer metadataOutputRectOfInterestForRect:CGRectMake(10, self.reticleView.center.y - MASK_CAMERA_HEIGHT / 2 - MASK_CAMERA_VERTICAL_INSET, self.reticleView.frame.size.width - 20, MASK_CAMERA_HEIGHT + MASK_CAMERA_VERTICAL_INSET * 2)];
}

//--------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL)animated {
    // setup capture preview layer
    AVCaptureVideoPreviewLayer* previewLayer = self.processor.previewLayer;
    previewLayer.frame = UIScreen.mainScreen.bounds;
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    //VERY IMPORTANT!!! Dont delete this row! This do calling Notification: avCaptureInputPortFormatDescriptionDidChangeNotification
    AVCaptureMetadataOutput* output = previewLayer.session.outputs[0];
    output.rectOfInterest = CGRectMake(0, 0.5, 1, 1);

    if ([previewLayer.connection isVideoOrientationSupported]) {
        [previewLayer.connection setVideoOrientation:[[UIApplication sharedApplication] statusBarOrientation]];
    }

    [self.view.layer insertSublayer:previewLayer below:[[self.view.layer sublayers] objectAtIndex:0]];

    UIView* overlayView = [self buildOverlayView];
    [self.view addSubview:overlayView];

    [self.reticleView setImage:[self buildReticleImage]];

    [self createBackgroundArea];
    [self startCapturing];
    [self addBackButton];
    [self addTitleLabel];
    [self addTextLabels];
    [self addEnterManualButton];

    [super viewDidAppear:animated];
}

- (void)createBackgroundArea {
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurredView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurredView.backgroundColor = [UIColor colorWithRed:15 / 255.f green:26 / 255.f blue:37 / 255.f alpha:0.6];

    UIBezierPath *cutPath = [UIBezierPath bezierPathWithRect: CGRectMake(10, self.reticleView.center.y - MASK_CAMERA_HEIGHT / 2 - MASK_CAMERA_VERTICAL_INSET, self.reticleView.frame.size.width - 20, MASK_CAMERA_HEIGHT + MASK_CAMERA_VERTICAL_INSET * 2)];

    UIBezierPath *path =  [UIBezierPath bezierPathWithRect:self.view.bounds];
    [path appendPath:cutPath];

    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.path = path.CGPath;
    maskLayer.fillRule = kCAFillRuleEvenOdd;

    blurredView.layer.mask  = maskLayer;
    [blurredView setFrame:self.view.bounds];

    [self.view addSubview:blurredView];
}

- (void)addEnterManualButton {
    CGFloat widthButton = 204;
    UIButton* button = [[UIButton alloc] initWithFrame:CGRectMake((UIScreen.mainScreen.bounds.size.width - widthButton) / 2, UIScreen.mainScreen.bounds.size.height - 30 - 55, widthButton, 30)];
    if (self.processor.localizedEnterCode == nil) {
        [button setTitle:@"Enter Code Manually" forState:UIControlStateNormal];
    } else {
        [button setTitle:self.processor.localizedEnterCode forState:UIControlStateNormal];
    }


    button.titleLabel.textColor = [UIColor whiteColor];
    button.titleLabel.font = [UIFont fontWithName:[NSString stringWithFormat:@"%@-Medium", button.titleLabel.font.fontName] size:13];

    [button layer].cornerRadius = 15;
    [button layer].borderColor = [UIColor whiteColor].CGColor;
    [button layer].borderWidth = 1.0;

    [button addTarget:self action:@selector(cancelButtonPressed:) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:button];
}

- (void)addTextLabels {
    UILabel* headerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, UIScreen.mainScreen.bounds.size.width, 20)];
    headerLabel.textColor = [UIColor whiteColor];
    if (self.processor.localizedPositionTheFrame == nil) {
        headerLabel.text = @"Position the the frame over the code.";
    } else {
        headerLabel.text = self.processor.localizedPositionTheFrame;
    }

    headerLabel.font = [UIFont fontWithName:[NSString stringWithFormat:@"%@-Bold", headerLabel.font.fontName] size:17];
    headerLabel.textAlignment = NSTextAlignmentCenter;

    [self.view addSubview:headerLabel];

    UILabel* subHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 130, UIScreen.mainScreen.bounds.size.width, 20)];
    subHeaderLabel.textColor = [UIColor whiteColor];

    if (self.processor.localizedAvoidGlares == nil) {
        subHeaderLabel.text = @"Avoid glares and low light for better result.";
    } else {
        subHeaderLabel.text = self.processor.localizedAvoidGlares;
    }

    subHeaderLabel.font =  [UIFont fontWithName:[NSString stringWithFormat:@"%@-Regular", subHeaderLabel.font.fontName] size:15];
    subHeaderLabel.textAlignment = NSTextAlignmentCenter;

    [self.view addSubview:subHeaderLabel];
}

- (void)addTitleLabel {
    UILabel* titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 56, UIScreen.mainScreen.bounds.size.width - 80, 20)];
    titleLabel.textColor = [UIColor whiteColor];

    if (self.processor.localizedScanCode == nil) {
        titleLabel.text = @"Scan Code";
    } else {
        titleLabel.text = self.processor.localizedScanCode;
    }

    titleLabel.font =  [UIFont fontWithName:[NSString stringWithFormat:@"%@-Bold", titleLabel.font.fontName] size:17];
    titleLabel.textAlignment = NSTextAlignmentCenter;

    [self.view addSubview:titleLabel];
}

- (void)addBackButton {
    UIButton* backButton = [[UIButton alloc] initWithFrame:CGRectMake(10, 53, 28, 28)];

    [backButton addTarget:self action:@selector(backButtonPressed:) forControlEvents:UIControlEventTouchUpInside];

    NSString* imageString = @"iVBORw0KGgoAAAANSUhEUgAAAFQAAABUCAYAAAAcaxDBAAAAAXNSR0IArs4c6QAAAq1JREFUeAHt2zFoFEEUgOG7oKAWaiPRRuxSWAq2FtY2WlvYaKeoqYOFgmBnIVpbqGAhBGItaiUWAQtBK0EIQgpjoZCQ8x8QEo43t8zcQjzmH3jk7u3M29uPPXYzOzcY2BRQQAEFFFBAAQUUUEABBRRQQAEFFFBAAQUUUEABBRRQoF2B0Wh0hHhJbBCviMPtakx55OAdJN4Su9v9Kcu2ORzB/cTKbsl/r5fbFJniqIGbI54FmCl1c4rSbQ4F7VEGc5n8vjZVKo8asHsZzDfkD1SWbXMYYLczmB/Je3UvOS0Au0JsB6CfyR0rqdV8X8AuElsB5jdyJ5sHKgEA7DzxJ8D8QW6hpFbzfQE7S/wKMH+SO9M8UAkAYKeJ9QDzN7lzJbWa7wvYKeJ7gLlJ7kLzQCUAgB0nvgaY6Qp/uaRW830BO0qsBpgpdb15oBIAwA4R75Nc0O6U1Gq+L4Bp5uh1AJlSD5sHKgEALM0cvUhyQXtKblhSbxb79nqAgD0B4WoAsU5uidgKtu1lapudrw6Hww97+SHCfYO5GJyVs5K6ER5URbK3MxS5NfY/X/EZ/ocha5ylJ/r4IHN9FLHGjkCfoA92ys7cq94eBvb2lU+EfO0f8+dawOlFKUDpTAGabpueE1Fr4rapE6m0A5Le2JeidfUH1X89u5BKt4Pq5EgpWld/UOeJL8R4c/quCy+3HUknmHM4tXlQfQRSi5cbB6oP6XI4tXlQfYxci5cbB6oLHXI4tXlQXYpTi5cbB+otImouFsuhdeXRvBuJknM5Yxdebjt4LrjN4dTkAXVJeA3cpDGgphmqFWK8zdyPFvqcsZ9kNnEbz3M26XCJeDfW8dPYe9+WCHB6+sOvEjD7KqCAAgoooIACCiiggAIKKKCAAgoooIACCiiggAIKKKDAYPAXDTPWW9ph07oAAAAASUVORK5CYII=";

    NSData* imageData = [[NSData alloc] initWithBase64EncodedString:imageString options:NSDataBase64DecodingIgnoreUnknownCharacters];
    UIImage* finalImage = [UIImage imageWithData:imageData];
    [backButton setImage:finalImage forState:UIControlStateNormal];
    [self.view addSubview:backButton];
}

- (IBAction)backButtonPressed:(id)sender {
    [self.processor.plugin returnSuccess:@"" format:@"" cancelled:FALSE flipped:FALSE callback:self.processor.callback isBackButton:TRUE];
}

//--------------------------------------------------------------------------
- (void)startCapturing {
    self.processor.capturing = YES;
}

//--------------------------------------------------------------------------
- (IBAction)shutterButtonPressed {
    self.shutterPressed = YES;
}

//--------------------------------------------------------------------------
- (IBAction)cancelButtonPressed:(id)sender {
    [self.processor performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
}

- (IBAction)flipCameraButtonPressed:(id)sender {
    [self.processor performSelector:@selector(flipCamera) withObject:nil afterDelay:0];
}

- (IBAction)torchButtonPressed:(id)sender {
    [self.processor performSelector:@selector(toggleTorch) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (UIView *)buildOverlayViewFromXib {
    [[NSBundle mainBundle] loadNibNamed:self.alternateXib owner:self options:NULL];

    if ( self.overlayView == nil ) {
        NSLog(@"%@", @"An error occurred loading the overlay xib.  It appears that the overlayView outlet is not set.");
        return nil;
    }

    self.overlayView.autoresizesSubviews = YES;
    self.overlayView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.overlayView.opaque              = NO;

    CGRect bounds = self.view.bounds;
    bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);

    [self.overlayView setFrame:bounds];

    return self.overlayView;
}

//--------------------------------------------------------------------------
- (UIView*)buildOverlayView {

    if ( nil != self.alternateXib ) {
        return [self buildOverlayViewFromXib];
    }
    CGRect bounds = self.view.frame;
    bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);

    //Маска прямоугольников
    UIView* overlayView = [[UIView alloc] initWithFrame:bounds];
    overlayView.autoresizesSubviews = YES;
    overlayView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlayView.opaque              = NO;

    self.reticleView = [[UIImageView alloc] init];

    self.reticleView.opaque           = NO;
    self.reticleView.contentMode      = UIViewContentModeScaleAspectFit;
    self.reticleView.autoresizingMask = (UIViewAutoresizing) (0
                                                              | UIViewAutoresizingFlexibleLeftMargin
                                                              | UIViewAutoresizingFlexibleRightMargin
                                                              | UIViewAutoresizingFlexibleTopMargin
                                                              | UIViewAutoresizingFlexibleBottomMargin)
    ;

    [overlayView addSubview: self.reticleView];
    [self resizeElements];

    return overlayView;
}

//-------------------------------------------------------------------------
// builds the green box and red line
//-------------------------------------------------------------------------
- (UIImage*)buildReticleImage {
    UIImage* result;

    UIGraphicsBeginImageContext(self.reticleView.frame.size);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGFloat parentWidth = self.reticleView.frame.size.width;
    // DONT USE self.reticleView.center.y
    CGFloat centerY = self.reticleView.frame.size.height / 2;
    CGFloat sideInset = (parentWidth - MASK_CAMERA_WIDTH) / 2;

    CGContextSetLineWidth(context, MASK_CAMERA_THICKNESS);

    if (self.processor.is1D) {
        CGContextBeginPath(context);
        UIColor* color = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextMoveToPoint(context, sideInset, centerY);
        CGContextAddLineToPoint(context, parentWidth - sideInset , centerY);
        CGContextStrokePath(context);
    }

    if (self.processor.is2D) {
        UIColor* color = [UIColor colorWithWhite:1 alpha: 1];
        CGContextSetStrokeColorWithColor(context, color.CGColor);

        CGContextBeginPath(context);

        //TOP PART
        CGContextMoveToPoint(context, sideInset, centerY - MASK_CAMERA_INSET);
        CGContextAddLineToPoint(context, sideInset, centerY - MASK_CAMERA_HEIGHT / 2); // |
        CGContextAddLineToPoint(context, parentWidth - sideInset, centerY - MASK_CAMERA_HEIGHT / 2); // -
        CGContextAddLineToPoint(context, parentWidth - sideInset, centerY - MASK_CAMERA_INSET); // |

        //BOT PART
        CGContextMoveToPoint(context, sideInset, centerY + MASK_CAMERA_INSET);
        CGContextAddLineToPoint(context, sideInset, centerY + MASK_CAMERA_HEIGHT / 2); // |
        CGContextAddLineToPoint(context, parentWidth - sideInset, centerY + MASK_CAMERA_HEIGHT / 2); // -
        CGContextAddLineToPoint(context, parentWidth - sideInset, centerY + MASK_CAMERA_INSET); // |

        CGContextStrokePath(context);
    }

    result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

#pragma mark CDVBarcodeScannerOrientationDelegate

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [[UIApplication sharedApplication] statusBarOrientation];
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }

    return YES;
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration {
    [UIView setAnimationsEnabled:NO];
    AVCaptureVideoPreviewLayer* previewLayer = self.processor.previewLayer;
    previewLayer.frame = self.view.bounds;

    if (orientation == UIInterfaceOrientationLandscapeLeft) {
        [previewLayer setOrientation:AVCaptureVideoOrientationLandscapeLeft];
    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        [previewLayer setOrientation:AVCaptureVideoOrientationLandscapeRight];
    } else if (orientation == UIInterfaceOrientationPortrait) {
        [previewLayer setOrientation:AVCaptureVideoOrientationPortrait];
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        [previewLayer setOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
    }

    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    [self resizeElements];
    [UIView setAnimationsEnabled:YES];
}

-(void) resizeElements {
    CGRect bounds = self.view.bounds;
    if (@available(iOS 11.0, *)) {
        bounds = CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width, self.view.safeAreaLayoutGuide.layoutFrame.size.height+self.view.safeAreaLayoutGuide.layoutFrame.origin.y);
    }

    CGFloat rootViewHeight = CGRectGetHeight(bounds);
    CGFloat rootViewWidth  = CGRectGetWidth(bounds);
    CGRect  rectArea       = CGRectMake(0, rootViewHeight - MASK_CAMERA_HEIGHT, rootViewWidth, MASK_CAMERA_HEIGHT);

    [self.reticleView setFrame:rectArea];
    self.reticleView.center = CGPointMake(self.view.center.x, self.view.center.y + scanOffset);
}

@end
