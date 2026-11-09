#pragma once

#include "common.h"
#include <vector>

namespace ppredictor {
class PredictorInput {
public:
  PredictorInput(std::vector<float> *data, std::vector<int64_t> *shape, int index,
                 int net_flag)
      : _data(data), _shape(shape), _index(index), _net_flag(net_flag) {}

  void set_dims(std::vector<int64_t> dims);

  float *get_mutable_float_data();

  void set_data(const float *input_data, int input_float_len);

private:
  std::vector<float> *_data;
  std::vector<int64_t> *_shape;
  bool _is_dims_set = false;
  int _index;
  int _net_flag;
};
} // namespace ppredictor
