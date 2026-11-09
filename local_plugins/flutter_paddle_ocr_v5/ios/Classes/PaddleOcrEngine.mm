#import "PaddleOcrEngine.h"

// Don't include <opencv2/opencv.hpp> — it transitively pulls opencv2/stitching
// headers that define an enum value named `NO`, which collides with Obj-C's
// NO macro. Include only the modules we actually use.
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>
#import <opencv2/imgcodecs.hpp>

#include <algorithm>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#include "ppocr/cls_process.h"
#include "ppocr/det_process.h"
#include "ppocr/rec_process.h"

static std::vector<std::string> ReadDict(const std::string &path) {
  std::vector<std::string> out;
  std::ifstream in(path);
  std::string line;
  while (std::getline(in, line)) out.push_back(line);
  return out;
}

// Ported from Paddle-Lite-Demo's pipeline.cc (not vendored in this plugin).
// Perspective-warps a detected polygon into an axis-aligned rectangle so the
// recognizer sees upright text.
static cv::Mat GetRotateCropImage(const cv::Mat &srcimage,
                                  std::vector<std::vector<int>> box) {
  int x_collect[4] = {box[0][0], box[1][0], box[2][0], box[3][0]};
  int y_collect[4] = {box[0][1], box[1][1], box[2][1], box[3][1]};
  int left = *std::min_element(x_collect, x_collect + 4);
  int right = *std::max_element(x_collect, x_collect + 4);
  int top = *std::min_element(y_collect, y_collect + 4);
  int bottom = *std::max_element(y_collect, y_collect + 4);
  cv::Mat img_crop;
  srcimage(cv::Rect(left, top, right - left, bottom - top)).copyTo(img_crop);
  for (int i = 0; i < 4; i++) {
    box[i][0] -= left;
    box[i][1] -= top;
  }
  int w = static_cast<int>(std::sqrt(std::pow(box[0][0] - box[1][0], 2) +
                                     std::pow(box[0][1] - box[1][1], 2)));
  int h = static_cast<int>(std::sqrt(std::pow(box[0][0] - box[3][0], 2) +
                                     std::pow(box[0][1] - box[3][1], 2)));
  cv::Point2f pts_std[4] = {{0, 0}, {(float)w, 0}, {(float)w, (float)h}, {0, (float)h}};
  cv::Point2f pointsf[4] = {
      {(float)box[0][0], (float)box[0][1]},
      {(float)box[1][0], (float)box[1][1]},
      {(float)box[2][0], (float)box[2][1]},
      {(float)box[3][0], (float)box[3][1]},
  };
  cv::Mat M = cv::getPerspectiveTransform(pointsf, pts_std);
  cv::Mat dst;
  cv::warpPerspective(img_crop, dst, M, cv::Size(w, h), cv::BORDER_REPLICATE);
  if ((float)dst.rows >= (float)dst.cols * 1.5f) {
    cv::Mat rot(dst.rows, dst.cols, dst.depth());
    cv::transpose(dst, rot);
    cv::flip(rot, rot, 0);
    return rot;
  }
  return dst;
}

@implementation PaddleOcrEngine {
  std::unique_ptr<DetPredictor> _det;
  std::unique_ptr<RecPredictor> _rec;
  std::unique_ptr<ClsPredictor> _cls;
  std::vector<std::string> _dict;
  BOOL _useDilation;
  double _detDbThresh;
  double _detDbBoxThresh;
  double _detDbUnclipRatio;
}

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
                         detDbUnclipRatio:(double)detDbUnclipRatio {
  if (!(self = [super init])) return nil;
  const std::string mode = powerMode.UTF8String;
  _useDilation = useDilation;
  _detDbThresh = detDbThresh;
  _detDbBoxThresh = detDbBoxThresh;
  _detDbUnclipRatio = detDbUnclipRatio;
  try {
    _det = std::make_unique<DetPredictor>(detPath.UTF8String, threads, mode);
    _rec = std::make_unique<RecPredictor>(recPath.UTF8String, threads, mode);
    if (clsPath.length > 0) {
      _cls = std::make_unique<ClsPredictor>(clsPath.UTF8String, threads, mode);
    }
  } catch (const std::exception &e) {
    NSLog(@"PaddleOcrEngine init failed: %s", e.what());
    return nil;
  }
  _dict = ReadDict(dictPath.UTF8String);
  // CTC blank token: the recognizer emits index 0 for "no character", so the
  // dictionary list is shifted by one. The optional trailing space matches
  // PaddleOCR's use_space_char behavior.
  _dict.insert(_dict.begin(), "#");
  if (useSpaceChar) {
    _dict.push_back(" ");
  }
  return self;
}

- (NSArray<NSDictionary *> *)recognize:(NSData *)imageData
                            maxSideLen:(int)maxSideLen
                                runDet:(BOOL)runDet
                                runCls:(BOOL)runCls
                                runRec:(BOOL)runRec {
  // Decode straight from the byte buffer into a BGR cv::Mat — skips the
  // UIImage + UIImageToMat double-decode and the EXIF rotation we don't honor.
  cv::Mat buf(1, (int)imageData.length, CV_8UC1, (void *)imageData.bytes);
  cv::Mat rgb = cv::imdecode(buf, cv::IMREAD_COLOR);
  if (rgb.empty()) return @[];

  std::map<std::string, double> cfg = {
      {"max_side_len", (double)maxSideLen},
      {"det_db_thresh", _detDbThresh},
      {"det_db_box_thresh", _detDbBoxThresh},
      {"det_db_unclip_ratio", _detDbUnclipRatio},
      {"det_db_use_dilate", _useDilation ? 1.0 : 0.0},
      {"det_use_polygon_score", 0},
      {"use_direction_classify", runCls ? 1.0 : 0.0},
  };

  std::vector<std::vector<std::vector<int>>> boxes;
  if (runDet) {
    boxes = _det->Predict(rgb, cfg, nullptr, nullptr, nullptr);
  } else {
    // No detection requested: feed the whole image to recognition as one box.
    int w = rgb.cols, h = rgb.rows;
    boxes.push_back({{0, 0}, {w, 0}, {w, h}, {0, h}});
  }

  NSMutableArray<NSDictionary *> *out =
      [NSMutableArray arrayWithCapacity:boxes.size()];
  // Iterate bottom-to-top so box order matches the Android output.
  for (int i = (int)boxes.size() - 1; i >= 0; i--) {
    cv::Mat crop = GetRotateCropImage(rgb, boxes[i]);
    const BOOL didCls = runCls && _cls != nullptr;
    if (didCls) {
      crop = _cls->Predict(crop, nullptr, nullptr, nullptr, 0.9);
    }
    NSString *text = @"";
    float score = 0.0f;
    if (runRec) {
      auto pair = _rec->Predict(crop, nullptr, nullptr, nullptr, _dict);
      text = [NSString stringWithUTF8String:pair.first.c_str()];
      score = pair.second;
    }
    NSMutableArray *points = [NSMutableArray arrayWithCapacity:4];
    for (const auto &p : boxes[i]) {
      [points addObject:@[@(p[0]), @(p[1])]];
    }
    NSMutableDictionary *dict = [@{
      @"text" : text,
      @"confidence" : @(score),
      @"points" : points,
    } mutableCopy];
    // ClsPredictor doesn't expose the applied rotation, so we can't populate
    // isUpsideDown reliably on iOS — leave null. Android gets it from the
    // JNI predictor's cls_idx field.
    if (didCls) {
      dict[@"isUpsideDown"] = [NSNull null];
      dict[@"angleConfidence"] = [NSNull null];
    }
    [out addObject:dict];
  }
  return out;
}

- (void)dispose {
  _det.reset();
  _rec.reset();
  _cls.reset();
  _dict.clear();
}

@end
