#include "stats.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>

Stats computeStats(const std::vector<int>& readings)
{
    int minimum = std::numeric_limits<int>::max();
    int maximum = std::numeric_limits<int>::min();
    std::int64_t sum = 0; // Fix: wide accumulator, no signed overflow

    for (int r : readings)
    {
        minimum = std::min(minimum, r);
        maximum = std::max(maximum, r);
        sum += r;
    }

    int count = readings.size();
    int mean = sum / count;
    return {minimum, maximum, mean};
}

int countDistinct(const std::vector<int>& readings)
{
    int distinct = 0;
    for (std::size_t i = 0; i < readings.size(); ++i)
    {
        bool seen = false;
        for (std::size_t j = 0; j < i; ++j)
        {
            if (readings[j] == readings[i])
            {
                seen = true;
                break;
            }
        }
        if (!seen)
        {
            ++distinct;
        }
    }
    return distinct;
}
