#include "ort_predictor.h"

#include <numeric>

static int64_t Product(const std::vector<int64_t> &shape) {
  if (shape.empty()) return 0;
  return std::accumulate(shape.begin(), shape.end(), int64_t{1},
                         std::multiplies<int64_t>());
}

OrtPredictor::OrtPredictor(const std::string &modelPath, int threadNum)
    : env_(ORT_LOGGING_LEVEL_WARNING, "flutter_paddle_ocr") {
  session_options_.SetIntraOpNumThreads(threadNum);
  session_options_.SetGraphOptimizationLevel(
      GraphOptimizationLevel::ORT_ENABLE_EXTENDED);
  session_ = Ort::Session(env_, modelPath.c_str(), session_options_);

  Ort::AllocatorWithDefaultOptions allocator;
  for (size_t i = 0; i < session_.GetInputCount(); i++) {
    auto name = session_.GetInputNameAllocated(i, allocator);
    input_names_storage_.emplace_back(name.get());
  }
  for (size_t i = 0; i < session_.GetOutputCount(); i++) {
    auto name = session_.GetOutputNameAllocated(i, allocator);
    output_names_storage_.emplace_back(name.get());
  }
  for (const auto &name : input_names_storage_) {
    input_names_.push_back(name.c_str());
  }
  for (const auto &name : output_names_storage_) {
    output_names_.push_back(name.c_str());
  }
}

float *OrtPredictor::PrepareInput(const std::vector<int64_t> &shape) {
  input_shape_ = shape;
  input_data_.assign(Product(shape), 0.0f);
  return input_data_.data();
}

std::vector<OrtOutput> OrtPredictor::Run() {
  Ort::MemoryInfo memory_info =
      Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
  Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
      memory_info, input_data_.data(), input_data_.size(), input_shape_.data(),
      input_shape_.size());
  std::vector<Ort::Value> tensors =
      session_.Run(Ort::RunOptions{nullptr}, input_names_.data(), &input_tensor,
                   1, output_names_.data(), output_names_.size());

  std::vector<OrtOutput> outputs;
  outputs.reserve(tensors.size());
  for (auto &tensor : tensors) {
    auto shape_info = tensor.GetTensorTypeAndShapeInfo();
    std::vector<int64_t> shape = shape_info.GetShape();
    size_t count = shape_info.GetElementCount();
    const float *data = tensor.GetTensorData<float>();
    outputs.push_back({std::vector<float>(data, data + count), shape});
  }
  return outputs;
}
