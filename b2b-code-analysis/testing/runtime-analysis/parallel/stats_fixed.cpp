#include "stats.hpp"

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <limits>
#include <thread>

// FIXED parallel variant: the shared accumulator is atomic, so the
// read-modify-write is synchronized and TSan reports no race.
Stats computeStats(const std::vector<int>& readings)
{
    int minimum = std::numeric_limits<int>::max();
    int maximum = std::numeric_limits<int>::min();
    for (int r : readings)
    {
        minimum = std::min(minimum, r);
        maximum = std::max(maximum, r);
    }

    std::atomic<int> sum = 0;
    const std::size_t mid = readings.size() / 2;
    auto worker = [&](std::size_t lo, std::size_t hi)
    {
        for (std::size_t i = lo; i < hi; ++i)
        {
            sum += readings[i];   // atomic read-modify-write: no race
        }
    };
    std::thread t1(worker, 0, mid);
    std::thread t2(worker, mid, readings.size());
    t1.join();
    t2.join();

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
