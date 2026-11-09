#include "ppredictor.h"
#include "common.h"
#include <fstream>

namespace ppredictor {
PPredictor::PPredictor(int use_opencl, int thread_num, int net_flag,
                       CpuPowerMode mode)
    : _use_opencl(use_opencl), _thread_num(thread_num), _net_flag(net_flag),
      _mode(mode), _env(ORT_LOGGING_LEVEL_WARNING, "flutter_paddle_ocr") {}

int PPredictor::init_nb(const std::string &model_content) {
  return _init_session(model_content.data(), model_content.size(), nullptr);
}

int PPredictor::init_from_file(const std::string &model_path) {
  return _init_session(nullptr, 0, model_path.c_str());
}

int PPredictor::_init_session(const void *model_data, size_t model_data_length,
                              const char *model_path) {
  _session_options.SetIntraOpNumThreads(_thread_num);
  _session_options.SetGraphOptimizationLevel(
      GraphOptimizationLevel::ORT_ENABLE_EXTENDED);
  if (_use_opencl != 0) {
    LOGW("ONNX Runtime Android backend currently ignores use_opencl.");
  }

  try {
    if (model_path != nullptr) {
      _session.reset(new Ort::Session(_env, model_path, _session_options));
    } else {
      _session.reset(new Ort::Session(_env, model_data, model_data_length,
                                      _session_options));
    }

    Ort::AllocatorWithDefaultOptions allocator;
    size_t input_count = _session->GetInputCount();
    size_t output_count = _session->GetOutputCount();

    _input_names_storage.clear();
    _output_names_storage.clear();
    _input_names.clear();
    _output_names.clear();

    for (size_t i = 0; i < input_count; i++) {
      auto name = _session->GetInputNameAllocated(i, allocator);
      _input_names_storage.emplace_back(name.get());
    }
    for (size_t i = 0; i < output_count; i++) {
      auto name = _session->GetOutputNameAllocated(i, allocator);
      _output_names_storage.emplace_back(name.get());
    }
    for (const auto &name : _input_names_storage) {
      _input_names.push_back(name.c_str());
    }
    for (const auto &name : _output_names_storage) {
      _output_names.push_back(name.c_str());
    }
    LOGI("ocr cpp onnx session created inputs=%zu outputs=%zu", input_count,
         output_count);
    return RETURN_OK;
  } catch (const Ort::Exception &e) {
    LOGE("ONNX Runtime init failed: %s", e.what());
    return -1;
  }
}

PredictorInput PPredictor::get_input(int index) {
  PredictorInput input{&_input_data, &_input_shape, index, _net_flag};
  _is_input_get = true;
  return input;
}

std::vector<PredictorInput> PPredictor::get_inputs(int num) {
  std::vector<PredictorInput> results;
  for (int i = 0; i < num; i++) {
    results.emplace_back(get_input(i));
  }
  return results;
}

PredictorInput PPredictor::get_first_input() { return get_input(0); }

std::vector<PredictorOutput> PPredictor::infer() {
  LOGI("ocr cpp infer Run start %d", _net_flag);
  std::vector<PredictorOutput> results;
  if (!_is_input_get || !_session) {
    return results;
  }

  try {
    Ort::MemoryInfo memory_info =
        Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
        memory_info, _input_data.data(), _input_data.size(), _input_shape.data(),
        _input_shape.size());

    std::vector<Ort::Value> output_tensors = _session->Run(
        Ort::RunOptions{nullptr}, _input_names.data(), &input_tensor, 1,
        _output_names.data(), _output_names.size());
    LOGI("ocr cpp infer Run end");

    for (int i = 0; i < output_tensors.size(); i++) {
      auto shape_info = output_tensors[i].GetTensorTypeAndShapeInfo();
      std::vector<int64_t> shape = shape_info.GetShape();
      size_t element_count = shape_info.GetElementCount();
      const float *raw_output = output_tensors[i].GetTensorData<float>();
      std::vector<float> output_data(raw_output, raw_output + element_count);
      LOGI("ocr cpp output tensor[%d] size %zu", i, element_count);
      PredictorOutput result{std::move(output_data), std::move(shape), i,
                             _net_flag};
      results.emplace_back(std::move(result));
    }
  } catch (const Ort::Exception &e) {
    LOGE("ONNX Runtime infer failed: %s", e.what());
  }
  return results;
}

NET_TYPE PPredictor::get_net_flag() const { return (NET_TYPE)_net_flag; }
} // namespace ppredictor
