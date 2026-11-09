//
// Created by fujiayi on 2020/7/2.
//
#pragma once
#include <opencv2/opencv.hpp>
#include <vector>

std::vector<std::vector<std::vector<int>>>
boxes_from_bitmap(const cv::Mat &pred, const cv::Mat &bitmap,
                  float box_thresh = 0.6f, float unclip_ratio = 1.5f);

std::vector<std::vector<std::vector<int>>>
filter_tag_det_res(const std::vector<std::vector<std::vector<int>>> &o_boxes,
                   float ratio_h, float ratio_w, const cv::Mat &srcimg);
