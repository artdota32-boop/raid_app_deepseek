#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Obj-C++ wrapper around Paddle-Lite-Demo's ppocr DetPredictor / ClsPredictor /
/// RecPredictor stack. Returns box + text + confidence per region.
@interface PaddleOcrEngine : NSObject

- (nullable instancetype)initWithDetPath:(NSString *)detPath
                                 recPath:(NSString *)recPath
                                dictPath:(NSString *)dictPath
                                 clsPath:(nullable NSString *)clsPath
                                 threads:(int)threads
                                powerMode:(NSString *)powerMode
                             useSpaceChar:(BOOL)useSpaceChar
                              useDilation:(BOOL)useDilation
                               detDbThresh:(double)detDbThresh
                            detDbBoxThresh:(double)detDbBoxThresh
                         detDbUnclipRatio:(double)detDbUnclipRatio;

/// Runs OCR on [imageData] (PNG/JPEG bytes). Returns an array of dicts with
/// keys: text(String), confidence(NSNumber), points([[x,y]]), and — when
/// classification is requested — isUpsideDown(NSNumber|NSNull),
/// angleConfidence(NSNumber|NSNull).
- (NSArray<NSDictionary *> *)recognize:(NSData *)imageData
                            maxSideLen:(int)maxSideLen
                                runDet:(BOOL)runDet
                                runCls:(BOOL)runCls
                                runRec:(BOOL)runRec;

- (void)dispose;

@end

NS_ASSUME_NONNULL_END
