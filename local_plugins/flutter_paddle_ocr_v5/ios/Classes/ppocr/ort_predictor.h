// Copyright (c) 2026.
//
// Small ONNX Runtime wrapper used by the iOS ppocr predictors.

#pragma once

#include <onnxruntime-c/onnxruntime_cxx_api.h>
#include <string>
#include <vector>

struct OrtOutput {
  std::vector<float> data;
  std::vector<int64_t> shape;
};

class OrtPredictor {
public:
  explicit OrtPredictor(const std::string &modelPath, int threadNum);

  float *PrepareInput(const std::vector<int64_t> &shape);
  std::vector<OrtOutput> Run();

private:
  Ort::Env env_;
  Ort::SessionOptions session_options_;
  Ort::Session session_{nullptr};
  std::vector<std::string> input_names_storage_;
  std::vector<std::string> output_names_storage_;
  std::vector<const char *> input_names_;
  std::vector<const char *> output_names_;
  std::vector<float> input_data_;
  std::vector<int64_t> input_shape_;
};
