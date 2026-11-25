// PanoramaStitcher.h
// Swift 에서 사용하는 합성 클래스 (내부는 OpenCV C++).
// 이 헤더에는 C++ 가 없어야 합니다 (Swift 브리징 헤더에서 import 하기 때문).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 투영 방식
typedef NS_ENUM(NSInteger, SSProjection) {
    SSProjectionCylindrical = 0,   ///< 원통 (기본, 건물 세로선이 곧게 유지)
    SSProjectionSpherical = 1,     ///< 구면
};

/// 결과 사진 형태
typedef NS_ENUM(NSInteger, SSOutputMode) {
    SSOutputModeFill43 = 0,        ///< 4:3 꽉 채우기 (넓은 사진은 양옆이 잘림)
    SSOutputModeFit43 = 1,         ///< 4:3 여백 (전체 유지, 흰 여백 추가)
    SSOutputModeOriginal = 2,      ///< 원본 비율 (빈 곳만 잘라냄)
};

FOUNDATION_EXPORT NSString * const SSStitchErrorDomain;

@interface PanoramaStitcher : NSObject

/// 마지막 합성에 실제로 사용된 사진 수
@property (nonatomic, readonly) NSInteger usedCount;
/// 마지막 합성에 입력된 사진 수
@property (nonatomic, readonly) NSInteger inputCount;

/// 사진 원본 데이터(HEIC/JPEG 등)를 받아 합성합니다. 결과는 객체 안에 보관됩니다.
/// @param maxPixelSize 각 사진을 이 크기(긴 변, px) 이하로 줄여서 합성 (메모리 절약)
- (BOOL)stitchImageData:(NSArray<NSData *> *)imageData
           maxPixelSize:(NSInteger)maxPixelSize
             projection:(SSProjection)projection
                  error:(NSError **)error
    NS_SWIFT_NAME(stitch(imageData:maxPixelSize:projection:));

/// 보관된 합성 결과를 지정한 형태로 잘라 JPEG 로 만듭니다. 다시 합성하지 않으므로 빠릅니다.
/// @param maxOutputSide 결과 사진 긴 변 최대 px
- (nullable NSData *)jpegForOutputMode:(SSOutputMode)mode
                         maxOutputSide:(NSInteger)maxOutputSide
                               quality:(NSInteger)quality
                                 error:(NSError **)error
    NS_SWIFT_NAME(jpeg(mode:maxOutputSide:quality:));

@end

NS_ASSUME_NONNULL_END
