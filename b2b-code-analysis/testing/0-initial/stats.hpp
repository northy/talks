#pragma once

#include <string>
#include <vector>

struct Stats
{
    int minimum;
    int maximum;
    int mean;
};

Stats computeStats(const std::vector<int>& readings);
int countDistinct(const std::vector<int>& readings);
