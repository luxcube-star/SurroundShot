// 리눅스용 검증 프로그램: StitchCore.hpp 를 그대로 사용합니다.
// 사용법: stitch_test <out.jpg> <cyl|sph> img1 img2 ...
//        stitch_test --grid <source.jpg> <outdir>   (2줄 x 4장 가상 촬영 사진 생성)
#include "../Shared/StitchCore.hpp"
#include <opencv2/imgcodecs.hpp>
#include <cstdio>
#include <string>

static cv::Mat rotY(double a){ return (cv::Mat_<double>(3,3) << cos(a),0,sin(a), 0,1,0, -sin(a),0,cos(a)); }
static cv::Mat rotX(double a){ return (cv::Mat_<double>(3,3) << 1,0,0, 0,cos(a),-sin(a), 0,sin(a),cos(a)); }

int main(int argc, char** argv) {
    if (argc >= 4 && std::string(argv[1]) == "--grid") {
        // 큰 사진을 '벽'으로 두고, 제자리에서 카메라를 돌려 찍은 2x4 사진을 만듭니다.
        cv::Mat src = cv::imread(argv[2]);
        if (src.empty()) { std::printf("read fail\n"); return 1; }
        const int W = 800, H = 600;                       // 출력 사진 크기 (4:3)
        const double f = W / (2 * tan(35.0 * CV_PI / 180)); // 가로 화각 70도 (아이폰 1x 근사)
        cv::Mat K = (cv::Mat_<double>(3,3) << f,0,W/2.0, 0,f,H/2.0, 0,0,1);
        // 원본 이미지를 카메라 정면 거리 fs 의 평면으로 간주
        const double fs = src.cols / (2 * tan(80.0 * CV_PI / 180)); // 원본이 가로 160도를 덮도록
        cv::Mat Ks = (cv::Mat_<double>(3,3) << fs,0,src.cols/2.0, 0,fs,src.rows/2.0, 0,0,1);
        int idx = 1;
        for (int row = 0; row < 2; ++row) {
            for (int col = 0; col < 4; ++col) {
                double yaw = (-1.5 + col) * 45.0 * CV_PI / 180;   // 45도 간격 => 약 35% 겹침
                double pitch = (row == 0 ? 15.0 : -15.0) * CV_PI / 180;
                cv::Mat R = rotY(yaw) * rotX(pitch);
                // 출력 픽셀 -> 광선 -> 원본 평면 픽셀
                cv::Mat Hm = Ks * R * K.inv();
                cv::Mat view;
                cv::warpPerspective(src, view, Hm, cv::Size(W, H), cv::INTER_LINEAR | cv::WARP_INVERSE_MAP);
                char name[512]; std::snprintf(name, sizeof name, "%s/g%d.jpg", argv[3], idx++);
                cv::imwrite(name, view);
            }
        }
        std::printf("grid written\n");
        return 0;
    }
    if (argc < 5) { std::printf("usage\n"); return 1; }
    std::vector<cv::Mat> imgs;
    for (int i = 3; i < argc; ++i) { cv::Mat m = cv::imread(argv[i]); if (m.empty()) { std::printf("read fail %s\n", argv[i]); return 1; } imgs.push_back(m); }
    const std::string pa = argv[2];
    auto proj = pa == "sph" ? stitchcore::Projection::Spherical : pa == "pla" ? stitchcore::Projection::Plane : stitchcore::Projection::Cylindrical;
    int64 t0 = cv::getTickCount();
    auto r = stitchcore::stitchWithRetry(imgs, proj);
    double sec = (cv::getTickCount() - t0) / cv::getTickFrequency();
    std::printf("status=%d used=%d/%zu pano=%dx%d time=%.1fs maxAngle=%.1f usedProjection=%d planeFellBack=%d\n", (int)r.status, r.usedCount, imgs.size(), r.pano.cols, r.pano.rows, sec, r.maxAngleDeg, (int)r.usedProjection, (int)r.planeFellBack);
    if (r.status != cv::Stitcher::OK) return 2;
    cv::Rect c = stitchcore::largestAspectRect(r.mask, 4.0 / 3.0);
    std::printf("crop=%d,%d %dx%d ratio=%.4f\n", c.x, c.y, c.width, c.height, c.height ? (double)c.width / c.height : 0);
    if (c.area() == 0) return 3;
    int holes = c.area() - cv::countNonZero(r.mask(c));
    cv::Rect lr = stitchcore::largestRect(r.mask);
    int holes2 = lr.area() - cv::countNonZero(r.mask(lr));
    std::printf("empty pixels inside 4:3 crop=%d, inside largestRect(%dx%d)=%d\n", holes, lr.width, lr.height, holes2);
    const char* names[3] = {"fill43", "fit43", "original"};
    for (int m = 0; m < 3; ++m) {
        cv::Mat o = stitchcore::renderOutput(r.pano, r.mask, (stitchcore::OutputMode)m, 4000);
        std::printf("  mode %-8s -> %dx%d ratio=%.4f\n", names[m], o.cols, o.rows, o.rows ? (double)o.cols / o.rows : 0);
        cv::imwrite(std::string(argv[1]) + "." + names[m] + ".jpg", o);
        if (o.empty()) holes = -1;
    }
    cv::Mat vis = r.pano.clone(); cv::rectangle(vis, c, cv::Scalar(0,0,255), 4); cv::rectangle(vis, lr, cv::Scalar(0,255,0), 4);
    cv::imwrite(std::string(argv[1]) + ".full.jpg", vis);
    holes += holes2;
    return holes == 0 ? 0 : 4;
}
