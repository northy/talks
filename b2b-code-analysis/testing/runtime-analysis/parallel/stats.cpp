#include "stats.hpp"

#include <algorithm>
#include <cstddef>
#include <limits>
#include <thread>

// PARALLEL VARIANT (chapter 3, TSan demo) of 1-post-static-analysis.
// A well-meaning "speedup": the sum loop is split across two threads,
// but they accumulate into ONE shared `sum` with no synchronization.
Stats computeStats(const std::vector<int>& readings)
{
    int minimum = std::numeric_limits<int>::max();
    int maximum = std::numeric_limits<int>::min();
    for (int r : readings)
    {
        minimum = std::min(minimum, r);
        maximum = std::max(maximum, r);
    }

    int sum = 0;
    const std::size_t mid = readings.size() / 2;
    auto worker = [&](std::size_t lo, std::size_t hi)
    {
        for (std::size_t i = lo; i < hi; ++i)
        {
            sum += readings[i];   // data race: shared accumulator, no lock
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
