#pragma once

#include "common.h"
#include <vector>

namespace ppredictor {
class PredictorOutput {
public:
  PredictorOutput() {}
  PredictorOutput(std::vector<float> data, std::vector<int64_t> shape, int index,
                  int net_flag)
      : data(std::move(data)), shape(std::move(shape)), _index(index),
        _net_flag(net_flag) {}

  const float *get_float_data() const;
  const int *get_int_data() const;
  int64_t get_size() const;
  const std::vector<std::vector<uint64_t>> get_lod() const;
  const std::vector<int64_t> get_shape() const;

  std::vector<float> data;    // return float, or use data_int
  std::vector<int> data_int;  // several layers return int ，or use data
  std::vector<int64_t> shape;
  std::vector<std::vector<uint64_t>> lod;

private:
  int _index;
  int _net_flag;
};
} // namespace ppredictor
