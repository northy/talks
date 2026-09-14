#include "stats.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <unordered_set>

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
    // Fix: one hash-set pass -- O(n), and no copy of the input
    const std::unordered_set<int> seen(readings.begin(), readings.end());
    return seen.size();
}
