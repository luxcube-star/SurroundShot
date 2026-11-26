// StitchCore.hpp
// 순수 C++ (OpenCV) 합성·4:3 자르기 로직.
// iOS 앱(PanoramaStitcher.mm)과 리눅스 테스트(tests/)가 같은 코드를 사용합니다.
//
// 주의: 이 파일은 Apple 헤더(Foundation, UIKit 등)보다 먼저 include 되어야 합니다.
// (OpenCV stitching 헤더의 'NO' 이름이 Objective-C의 NO 매크로와 충돌하기 때문)

#pragma once

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/stitching.hpp>
#include <opencv2/calib3d.hpp>
#include <opencv2/features2d.hpp>

#include <algorithm>
#include <climits>
#include <cmath>
#include <vector>

namespace stitchcore {

enum class Projection { Cylindrical = 0, Spherical = 1, Plane = 2 };

// 평면 투영을 허용하는 최대 각도 (화면 가운데 방향에서 사진 모서리까지).
// 평면은 각도 θ 에서 가장자리가 약 1/cos²θ 배로 늘어납니다 (60° = 4배).
// 이보다 넓게 찍힌 사진은 가장자리가 지나치게 늘어나고 메모리도 크게 쓰므로 원통으로 바꿉니다.
constexpr double kPlaneMaxAngleDeg = 60.0;

struct StitchResult {
    cv::Stitcher::Status status = cv::Stitcher::ERR_NEED_MORE_IMGS;
    cv::Mat pano;              // CV_8UC3
    cv::Mat mask;              // CV_8U, 255 = 사진이 채워진 영역
    int usedCount = 0;         // 실제로 합성에 쓰인 사진 수
    Projection usedProjection = Projection::Plane;  // 실제로 쓴 투영 방식
    bool planeFellBack = false;  // 평면을 요청했지만 너무 넓어서 원통으로 바꿨는지
    double maxAngleDeg = 0;      // 가운데 방향에서 가장 먼 사진 모서리까지의 각도
};

// 카메라 추정 결과에서, 합성 기준 방향(z축)과 각 사진 네 모서리 광선 사이의 최대 각도(도).
// 평면 투영기와 같은 식(광선 = R · K⁻¹ · 픽셀)을 씁니다.
inline double maxAngleFromCenterDeg(const std::vector<cv::detail::CameraParams>& cameras) {
    double maxDeg = 0;
    for (const auto& c : cameras) {
        cv::Mat K, R;
        c.K().convertTo(K, CV_64F);
        c.R.convertTo(R, CV_64F);
        const cv::Mat RK = R * K.inv();
        const double w = c.ppx * 2, h = c.ppy * 2;
        const double corners[4][2] = {{0, 0}, {w, 0}, {0, h}, {w, h}};
        for (const auto& p : corners) {
            const cv::Mat d = RK * (cv::Mat_<double>(3, 1) << p[0], p[1], 1.0);
            const double z = d.at<double>(2);
            const double n = cv::norm(d);
            const double deg = (z <= 0 || n <= 0) ? 180.0 : std::acos(std::min(1.0, z / n)) * 180.0 / CV_PI;
            maxDeg = std::max(maxDeg, deg);
        }
    }
    return maxDeg;
}

inline cv::Ptr<cv::WarperCreator> makeWarper(Projection projection) {
    switch (projection) {
        case Projection::Spherical: return cv::makePtr<cv::SphericalWarper>();
        case Projection::Plane: return cv::makePtr<cv::PlaneWarper>();  // 직선이 곧게 (일반 사진처럼)
        case Projection::Cylindrical:
        default: return cv::makePtr<cv::CylindricalWarper>();  // 세로선이 곧게
    }
}

// 한 번 합성을 시도합니다.
inline StitchResult runStitch(const std::vector<cv::Mat>& images,
                              Projection projection,
                              double confidenceThresh) {
    StitchResult r;
    cv::Ptr<cv::Stitcher> st = cv::Stitcher::create(cv::Stitcher::PANORAMA);
    st->setPanoConfidenceThresh(confidenceThresh);
    r.usedProjection = projection;

    // 1) 사진 사이 위치·각도 계산
    r.status = st->estimateTransform(images);
    if (r.status != cv::Stitcher::OK) return r;

    // 2) 투영 방식 결정 — 평면은 너무 넓으면 원통으로 바꿉니다.
    r.maxAngleDeg = maxAngleFromCenterDeg(st->cameras());
    if (projection == Projection::Plane && r.maxAngleDeg > kPlaneMaxAngleDeg) {
        r.planeFellBack = true;
        r.usedProjection = Projection::Cylindrical;
    }
    st->setWarper(makeWarper(r.usedProjection));

    // 3) 펴서 이어 붙이기
    r.status = st->composePanorama(r.pano);
    if (r.status != cv::Stitcher::OK) return r;

    r.usedCount = static_cast<int>(st->component().size());

    cv::UMat um = st->resultMask();
    if (!um.empty()) um.copyTo(r.mask);
    if (r.mask.empty() || r.mask.size() != r.pano.size()) {
        cv::Mat gray;
        cv::cvtColor(r.pano, gray, cv::COLOR_BGR2GRAY);
        r.mask = gray > 0;
    }
    return r;
}

// 기본 기준으로 시도하고, 겹침 부족으로 실패하면 기준을 낮춰 한 번 더 시도합니다.
inline StitchResult stitchWithRetry(const std::vector<cv::Mat>& images, Projection projection) {
    StitchResult r = runStitch(images, projection, 1.0);
    if (r.status == cv::Stitcher::ERR_NEED_MORE_IMGS) {
        r = runStitch(images, projection, 0.6);
    }
    return r;
}

// mask 안에 완전히 들어가는, 가로:세로 = aspect 인 가장 큰 사각형을 찾습니다.
// 같은 크기 후보가 여러 개면 채워진 영역의 중심에 가장 가까운 것을 고릅니다.
// 찾지 못하면 빈 Rect 를 반환합니다.
inline cv::Rect largestAspectRect(const cv::Mat& mask, double aspect) {
    if (mask.empty() || aspect <= 0) return cv::Rect();

    // 계산량을 줄이기 위해 긴 변 600px 로 축소해서 탐색
    const double s = std::min(1.0, 600.0 / std::max(mask.cols, mask.rows));
    cv::Mat small;
    cv::resize(mask, small, cv::Size(), s, s, cv::INTER_AREA);
    cv::Mat bin = small >= 255;                       // 완전히 채워진 칸만 0/255
    cv::erode(bin, bin, cv::Mat(), cv::Point(-1, -1), 1);  // 가장자리 안전 여유

    cv::Mat ones = bin / 255;
    cv::Mat integ;
    cv::integral(ones, integ, CV_32S);

    const int W = bin.cols, H = bin.rows;
    cv::Rect bbox = cv::boundingRect(bin);
    if (bbox.area() == 0) return cv::Rect();
    const double cx = bbox.x + bbox.width / 2.0;
    const double cy = bbox.y + bbox.height / 2.0;

    auto findFit = [&](int h, cv::Rect& out) -> bool {
        const int w = static_cast<int>(std::floor(h * aspect));
        if (h < 1 || w < 1 || w > W || h > H) return false;
        const int need = w * h;
        bool found = false;
        double best = 1e300;
        for (int y = 0; y + h <= H; ++y) {
            const int* r0 = integ.ptr<int>(y);
            const int* r1 = integ.ptr<int>(y + h);
            for (int x = 0; x + w <= W; ++x) {
                const int sum = r1[x + w] - r1[x] - r0[x + w] + r0[x];
                if (sum == need) {
                    const double dx = x + w / 2.0 - cx;
                    const double dy = y + h / 2.0 - cy;
                    const double d = dx * dx + dy * dy;
                    if (d < best) { best = d; out = cv::Rect(x, y, w, h); found = true; }
                }
            }
        }
        return found;
    };

    int lo = 1;
    int hi = std::min(H, static_cast<int>(std::floor(W / aspect)));
    cv::Rect bestRect;
    while (lo <= hi) {
        const int mid = (lo + hi) / 2;
        cv::Rect r;
        if (findFit(mid, r)) { bestRect = r; lo = mid + 1; }
        else { hi = mid - 1; }
    }
    if (bestRect.area() == 0) return cv::Rect();

    // 원래 해상도로 되돌리고, 축소 오차만큼 안쪽으로 여유를 줍니다.
    const double inv = 1.0 / s;
    const int margin = static_cast<int>(std::ceil(inv)) + 2;
    int x0 = static_cast<int>(std::ceil(bestRect.x * inv)) + margin;
    int y0 = static_cast<int>(std::ceil(bestRect.y * inv)) + margin;
    int x1 = static_cast<int>(std::floor((bestRect.x + bestRect.width) * inv)) - margin;
    int y1 = static_cast<int>(std::floor((bestRect.y + bestRect.height) * inv)) - margin;
    x0 = std::max(0, x0); y0 = std::max(0, y0);
    x1 = std::min(mask.cols, x1); y1 = std::min(mask.rows, y1);
    int w = x1 - x0, h = y1 - y0;
    if (w <= 0 || h <= 0) return cv::Rect();

    // 정확히 aspect 비율로 맞추기 (가운데 기준)
    if (w > h * aspect) {
        const int nw = static_cast<int>(std::floor(h * aspect));
        x0 += (w - nw) / 2; w = nw;
    } else {
        const int nh = static_cast<int>(std::floor(w / aspect));
        y0 += (h - nh) / 2; h = nh;
    }
    if (w <= 0 || h <= 0) return cv::Rect();
    return cv::Rect(x0, y0, w, h);
}

// mask 안에 완전히 들어가는 '넓이가 가장 큰' 사각형 (비율 제한 없음).
// 히스토그램 방식 최대 사각형 알고리즘을 축소된 마스크에서 수행합니다.
inline cv::Rect largestRect(const cv::Mat& mask) {
    if (mask.empty()) return cv::Rect();
    const double s = std::min(1.0, 600.0 / std::max(mask.cols, mask.rows));
    cv::Mat small;
    cv::resize(mask, small, cv::Size(), s, s, cv::INTER_AREA);
    cv::Mat bin = small >= 255;
    cv::erode(bin, bin, cv::Mat(), cv::Point(-1, -1), 1);

    const int W = bin.cols, H = bin.rows;
    std::vector<int> heights(W + 1, 0);  // 마지막 0 은 스택 비우기용
    std::vector<int> stack;
    long bestArea = 0;
    cv::Rect best;
    for (int y = 0; y < H; ++y) {
        const uchar* row = bin.ptr<uchar>(y);
        for (int x = 0; x < W; ++x) heights[x] = row[x] ? heights[x] + 1 : 0;
        heights[W] = 0;
        stack.clear();
        for (int x = 0; x <= W; ++x) {
            while (!stack.empty() && heights[stack.back()] >= heights[x]) {
                const int h = heights[stack.back()];
                stack.pop_back();
                const int left = stack.empty() ? 0 : stack.back() + 1;
                const long area = static_cast<long>(h) * (x - left);
                if (area > bestArea) { bestArea = area; best = cv::Rect(left, y - h + 1, x - left, h); }
            }
            stack.push_back(x);
        }
    }
    if (bestArea == 0) return cv::Rect();

    const double inv = 1.0 / s;
    const int margin = static_cast<int>(std::ceil(inv)) + 2;
    int x0 = std::max(0, static_cast<int>(std::ceil(best.x * inv)) + margin);
    int y0 = std::max(0, static_cast<int>(std::ceil(best.y * inv)) + margin);
    int x1 = std::min(mask.cols, static_cast<int>(std::floor((best.x + best.width) * inv)) - margin);
    int y1 = std::min(mask.rows, static_cast<int>(std::floor((best.y + best.height) * inv)) - margin);
    if (x1 <= x0 || y1 <= y0) return cv::Rect();
    return cv::Rect(x0, y0, x1 - x0, y1 - y0);
}

// photo 가 pano 안의 어디에 있는지 특징점 매칭으로 찾아, photo 가운데 점의 pano 좌표를 돌려줍니다.
// 못 찾으면 false.
inline bool locatePhotoCenter(const cv::Mat& pano, const cv::Mat& photo, cv::Point2d& out) {
    if (pano.empty() || photo.empty()) return false;
    auto shrink = [](const cv::Mat& m, double maxSide, double& scale) {
        scale = std::min(1.0, maxSide / std::max(m.cols, m.rows));
        cv::Mat g, r;
        cv::cvtColor(m, g, cv::COLOR_BGR2GRAY);
        cv::resize(g, r, cv::Size(), scale, scale, cv::INTER_AREA);
        return r;
    };
    double sp = 1, sq = 1;
    const cv::Mat P = shrink(pano, 1600, sp);
    const cv::Mat Q = shrink(photo, 1000, sq);
    cv::Ptr<cv::ORB> orb = cv::ORB::create(5000);
    std::vector<cv::KeyPoint> kp, kq;
    cv::Mat dp, dq;
    orb->detectAndCompute(P, cv::noArray(), kp, dp);
    orb->detectAndCompute(Q, cv::noArray(), kq, dq);
    if (dp.empty() || dq.empty()) return false;
    cv::BFMatcher matcher(cv::NORM_HAMMING);
    std::vector<std::vector<cv::DMatch>> knn;
    matcher.knnMatch(dq, dp, knn, 2);
    std::vector<cv::Point2f> src, dst;
    for (const auto& m : knn) {
        if (m.size() == 2 && m[0].distance < 0.75f * m[1].distance) {
            src.push_back(kq[m[0].queryIdx].pt);
            dst.push_back(kp[m[0].trainIdx].pt);
        }
    }
    if (src.size() < 12) return false;
    std::vector<uchar> inliers;
    cv::Mat H = cv::findHomography(src, dst, cv::RANSAC, 4.0, inliers);
    if (H.empty() || cv::countNonZero(inliers) < 12) return false;
    std::vector<cv::Point2f> c = {cv::Point2f(Q.cols / 2.0f, Q.rows / 2.0f)}, mapped;
    cv::perspectiveTransform(c, mapped, H);
    out = cv::Point2d(mapped[0].x / sp, mapped[0].y / sp);
    return out.x >= 0 && out.y >= 0 && out.x < pano.cols && out.y < pano.rows;
}

// center 를 정확히 가운데로 하는, mask 안에 들어가는 가장 큰 4:3 사각형.
inline cv::Rect largestAspectRectCenteredAt(const cv::Mat& mask, double aspect, cv::Point2d center) {
    if (mask.empty()) return cv::Rect();
    const double s = std::min(1.0, 600.0 / std::max(mask.cols, mask.rows));
    cv::Mat small;
    cv::resize(mask, small, cv::Size(), s, s, cv::INTER_AREA);
    cv::Mat bin = small >= 255;
    cv::erode(bin, bin, cv::Mat(), cv::Point(-1, -1), 1);
    cv::Mat ones = bin / 255, integ;
    cv::integral(ones, integ, CV_32S);
    const double cx = center.x * s, cy = center.y * s;
    auto fits = [&](int h) {
        const int w = static_cast<int>(std::floor(h * aspect));
        const int x = static_cast<int>(std::round(cx - w / 2.0));
        const int y = static_cast<int>(std::round(cy - h / 2.0));
        if (x < 0 || y < 0 || x + w > bin.cols || y + h > bin.rows || w < 1) return false;
        const int sum = integ.at<int>(y + h, x + w) - integ.at<int>(y, x + w) - integ.at<int>(y + h, x) + integ.at<int>(y, x);
        return sum == w * h;
    };
    int lo = 1, hi = bin.rows, best = 0;
    while (lo <= hi) {
        const int mid = (lo + hi) / 2;
        if (fits(mid)) { best = mid; lo = mid + 1; } else { hi = mid - 1; }
    }
    if (best == 0) return cv::Rect();
    const double inv = 1.0 / s;
    const int margin = static_cast<int>(std::ceil(inv)) + 2;
    int h = static_cast<int>(std::floor(best * inv)) - 2 * margin;
    int w = static_cast<int>(std::floor(h * aspect));
    int x = static_cast<int>(std::round(center.x - w / 2.0));
    int y = static_cast<int>(std::round(center.y - h / 2.0));
    x = std::max(0, std::min(x, mask.cols - w));
    y = std::max(0, std::min(y, mask.rows - h));
    if (w <= 0 || h <= 0) return cv::Rect();
    return cv::Rect(x, y, w, h);
}

enum class OutputMode {
    Fill43 = 0,    // 4:3 꽉 채우기 (넓은 사진은 양옆이 잘림)
    Fit43 = 1,     // 빈 곳만 잘라낸 뒤 흰 여백을 붙여 4:3 (전체 유지)
    Original = 2,  // 빈 곳만 잘라냄 (원래 비율)
};

// 긴 변이 maxSide 를 넘으면 비율을 유지하며 줄입니다 (maxSide <= 0 이면 그대로).
inline cv::Mat limitSize(const cv::Mat& img, int maxSide) {
    const int longSide = std::max(img.cols, img.rows);
    if (maxSide <= 0 || longSide <= maxSide) return img.clone();
    const double f = static_cast<double>(maxSide) / longSide;
    cv::Mat out;
    cv::resize(img, out, cv::Size(), f, f, cv::INTER_AREA);
    return out;
}

// 합성 결과를 지정한 방식으로 잘라 반환합니다. 실패하면 빈 Mat.
// maxSide: 결과 사진의 긴 변 최대 픽셀 (메모리·용량 제한용)
inline cv::Mat renderOutput(const cv::Mat& pano, const cv::Mat& mask, OutputMode mode, int maxSide) {
    const double aspect = 4.0 / 3.0;
    if (mode == OutputMode::Fill43) {
        cv::Rect r = largestAspectRect(mask, aspect);
        return r.area() > 0 ? limitSize(pano(r), maxSide) : cv::Mat();
    }
    cv::Rect r = largestRect(mask);
    if (r.area() == 0) return cv::Mat();
    if (mode == OutputMode::Original) return limitSize(pano(r), maxSide);

    // 여백 포함 크기가 maxSide 이내가 되도록 내용을 먼저 줄입니다.
    const double longFit = std::max<double>(r.width, r.height * aspect);
    int contentMax = std::max(r.width, r.height);
    if (maxSide > 0 && longFit > maxSide) {
        contentMax = static_cast<int>(std::floor(contentMax * (maxSide / longFit)));
    }
    cv::Mat content = limitSize(pano(r), contentMax);

    // Fit43: 내용 전체를 유지하고 흰 여백으로 4:3 맞추기 (가운데 정렬)
    int outW = content.cols, outH = content.rows;
    if (outW > outH * aspect) outH = static_cast<int>(std::ceil(outW / aspect));
    else outW = static_cast<int>(std::ceil(outH * aspect));
    cv::Mat canvas(outH, outW, content.type(), cv::Scalar(255, 255, 255));
    content.copyTo(canvas(cv::Rect((outW - content.cols) / 2, (outH - content.rows) / 2,
                                   content.cols, content.rows)));
    return canvas;
}

}  // namespace stitchcore
