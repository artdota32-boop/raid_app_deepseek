#include "predictor_input.h"

namespace ppredictor {

void PredictorInput::set_dims(std::vector<int64_t> dims) {
  *_shape = std::move(dims);
  _data->resize(product(*_shape));
  _is_dims_set = true;
}

float *PredictorInput::get_mutable_float_data() {
  if (!_is_dims_set) {
    LOGE("PredictorInput::set_dims is not called");
  }
  return _data->data();
}

void PredictorInput::set_data(const float *input_data, int input_float_len) {
  float *input_raw_data = get_mutable_float_data();
  memcpy(input_raw_data, input_data, input_float_len * sizeof(float));
}
} // namespace ppredictor
