#include "predictor_output.h"
namespace ppredictor {
const float *PredictorOutput::get_float_data() const {
  return data.data();
}

const int *PredictorOutput::get_int_data() const {
  return data_int.data();
}

const std::vector<std::vector<uint64_t>> PredictorOutput::get_lod() const {
  return lod;
}

int64_t PredictorOutput::get_size() const {
  if (_net_flag == NET_OCR) {
    return shape.at(2) * shape.at(3);
  } else {
    return product(shape);
  }
}

const std::vector<int64_t> PredictorOutput::get_shape() const {
  return shape;
}
} // namespace ppredictor
