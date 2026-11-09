#pragma once

#include "predictor_input.h"
#include "predictor_output.h"
#include <memory>
#include <onnxruntime_cxx_api.h>
#include <string>

namespace ppredictor {

enum CpuPowerMode {
  LITE_POWER_HIGH = 0,
  LITE_POWER_LOW = 1,
  LITE_POWER_FULL = 2,
  LITE_POWER_NO_BIND = 3,
  LITE_POWER_RAND_HIGH = 4,
  LITE_POWER_RAND_LOW = 5,
};

/**
 * OCR predictor common interface.
 */
class PPredictor_Interface {
public:
  virtual ~PPredictor_Interface() {}

  virtual NET_TYPE get_net_flag() const = 0;
};

/**
 * Common Predictor
 */
class PPredictor : public PPredictor_Interface {
public:
  PPredictor(int use_opencl, int thread_num, int net_flag = 0,
             CpuPowerMode mode = LITE_POWER_HIGH);

  virtual ~PPredictor() {}

  /**
   * init ONNX model from memory or file.
   * @param model_content
   * @return 0
   */
  virtual int init_nb(const std::string &model_content);

  virtual int init_from_file(const std::string &model_content);

  std::vector<PredictorOutput> infer();

  virtual std::vector<PredictorInput> get_inputs(int num);

  virtual PredictorInput get_input(int index);

  virtual PredictorInput get_first_input();

  virtual NET_TYPE get_net_flag() const;

protected:
  int _init_session(const void *model_data, size_t model_data_length,
                    const char *model_path);

private:
  int _use_opencl;
  int _thread_num;
  CpuPowerMode _mode;
  Ort::Env _env;
  Ort::SessionOptions _session_options;
  std::unique_ptr<Ort::Session> _session;
  std::vector<std::string> _input_names_storage;
  std::vector<std::string> _output_names_storage;
  std::vector<const char *> _input_names;
  std::vector<const char *> _output_names;
  std::vector<float> _input_data;
  std::vector<int64_t> _input_shape;
  bool _is_input_get = false;
  int _net_flag;
};
} // namespace ppredictor
