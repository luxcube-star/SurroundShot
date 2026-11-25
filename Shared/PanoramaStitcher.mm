// PanoramaStitcher.mm
//
// ⚠️ 순서 중요: OpenCV 헤더(StitchCore.hpp)를 Apple 헤더보다 먼저 include 해야 합니다.
//    (OpenCV 의 'NO' 이름과 Objective-C 의 NO 매크로 충돌 방지)

#include "StitchCore.hpp"
#include <opencv2/imgcodecs.hpp>
#include <string>
#include <vector>

#import "PanoramaStitcher.h"
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

NSString * const SSStitchErrorDomain = @"SSStitchErrorDomain";

static void SSSetError(NSError **error, NSInteger code, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:SSStitchErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
}

/// CGImage -> BGR cv::Mat (sRGB 로 변환)
static cv::Mat SSMatFromCGImage(CGImageRef image) {
    const size_t w = CGImageGetWidth(image);
    const size_t h = CGImageGetHeight(image);
    cv::Mat rgba((int)h, (int)w, CV_8UC4);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(rgba.data, w, h, 8, rgba.step[0], cs,
                                             kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
    CGColorSpaceRelease(cs);
    if (!ctx) return cv::Mat();
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image);
    CGContextRelease(ctx);
    cv::Mat bgr;
    cv::cvtColor(rgba, bgr, cv::COLOR_RGBA2BGR);
    return bgr;
}

/// 사진 데이터를 회전 정보(EXIF)를 반영하고 maxPixelSize 이하로 줄여서 읽습니다.
static cv::Mat SSDecodeDownsampled(NSData *data, NSInteger maxPixelSize) {
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return cv::Mat();
    NSDictionary *opts = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES,
    };
    CGImageRef img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!img) return cv::Mat();
    cv::Mat bgr = SSMatFromCGImage(img);
    CGImageRelease(img);
    return bgr;
}

static NSString *SSMessageForStatus(cv::Stitcher::Status status) {
    switch (status) {
        case cv::Stitcher::ERR_NEED_MORE_IMGS:
            return @"사진끼리 겹치는 부분을 충분히 찾지 못했습니다.\n옆·위아래 사진과 30% 이상 겹치게 다시 찍어 주세요.";
        case cv::Stitcher::ERR_HOMOGRAPHY_EST_FAIL:
            return @"사진 사이의 위치 관계를 계산하지 못했습니다.\n제자리에서 몸만 돌려 찍었는지 확인해 주세요.";
        case cv::Stitcher::ERR_CAMERA_PARAMS_ADJUST_FAIL:
            return @"카메라 각도 보정에 실패했습니다.\n다른 투영 방식으로 다시 합성하거나 다시 찍어 주세요.";
        default:
            return @"알 수 없는 이유로 합성에 실패했습니다.";
    }
}

@implementation PanoramaStitcher {
    cv::Mat _pano;
    cv::Mat _mask;
}

- (BOOL)stitchImageData:(NSArray<NSData *> *)imageData
           maxPixelSize:(NSInteger)maxPixelSize
             projection:(SSProjection)projection
                  error:(NSError **)error {
    _pano.release();
    _mask.release();
    _usedCount = 0;
    _planeFellBack = NO;
    _maxAngleDegrees = 0;
    _inputCount = (NSInteger)imageData.count;

    if (imageData.count < 2) {
        SSSetError(error, 1, @"사진을 2장 이상 선택해 주세요.");
        return NO;
    }
    try {
        std::vector<cv::Mat> images;
        images.reserve(imageData.count);
        for (NSData *d in imageData) {
            @autoreleasepool {
                cv::Mat m = SSDecodeDownsampled(d, maxPixelSize);
                if (m.empty()) {
                    SSSetError(error, 2, @"사진을 읽을 수 없습니다.");
                    return NO;
                }
                images.push_back(m);
            }
        }
        auto proj = stitchcore::Projection::Plane;
        if (projection == SSProjectionCylindrical) proj = stitchcore::Projection::Cylindrical;
        else if (projection == SSProjectionSpherical) proj = stitchcore::Projection::Spherical;
        stitchcore::StitchResult r = stitchcore::stitchWithRetry(images, proj);
        images.clear();
        images.shrink_to_fit();
        if (r.status != cv::Stitcher::OK) {
            SSSetError(error, 10 + (NSInteger)r.status, SSMessageForStatus(r.status));
            return NO;
        }
        _pano = r.pano;
        _mask = r.mask;
        _usedCount = r.usedCount;
        _planeFellBack = r.planeFellBack;
        _maxAngleDegrees = r.maxAngleDeg;
        return YES;
    } catch (const cv::Exception &e) {
        SSSetError(error, 90, [NSString stringWithFormat:@"합성 중 오류가 발생했습니다.\n(%s)", e.what()]);
    } catch (const std::exception &e) {
        SSSetError(error, 91, [NSString stringWithFormat:@"합성 중 오류가 발생했습니다.\n(%s)", e.what()]);
    }
    return NO;
}

- (nullable NSData *)jpegForOutputMode:(SSOutputMode)mode
                         maxOutputSide:(NSInteger)maxOutputSide
                               quality:(NSInteger)quality
                                 error:(NSError **)error {
    if (_pano.empty()) {
        SSSetError(error, 20, @"합성된 사진이 없습니다.");
        return nil;
    }
    try {
        stitchcore::OutputMode m = stitchcore::OutputMode::Fill43;
        if (mode == SSOutputModeFit43) m = stitchcore::OutputMode::Fit43;
        else if (mode == SSOutputModeOriginal) m = stitchcore::OutputMode::Original;

        cv::Mat out = stitchcore::renderOutput(_pano, _mask, m, (int)maxOutputSide);
        if (out.empty()) {
            SSSetError(error, 21, @"자를 수 있는 영역을 찾지 못했습니다.");
            return nil;
        }
        std::vector<uchar> buf;
        std::vector<int> params = {cv::IMWRITE_JPEG_QUALITY, (int)quality};
        if (!cv::imencode(".jpg", out, buf, params)) {
            SSSetError(error, 22, @"JPEG 저장에 실패했습니다.");
            return nil;
        }
        return [NSData dataWithBytes:buf.data() length:buf.size()];
    } catch (const cv::Exception &e) {
        SSSetError(error, 92, [NSString stringWithFormat:@"사진 생성 중 오류가 발생했습니다.\n(%s)", e.what()]);
    }
    return nil;
}

@end
