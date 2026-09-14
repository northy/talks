#include <vector>

struct Stats { int minimum, maximum, mean; };

// Precondition is now program structure, not a comment:
Stats computeStats(const std::vector<int>& readings)
    pre (!readings.empty());

Stats computeStats(const std::vector<int>& readings)
{
    const int count = readings.size();
    return {readings.front(), readings.back(), readings.front() / count};
}

int main()
{
    std::vector<int> v{};        // empty -> violates the precondition
    return computeStats(v).mean;
}
