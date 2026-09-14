#include <vector>

// This narrowing predates our clang-tidy policy.
int legacyCount(const std::vector<int>& readings)
{
    int n = readings.size();
    return n;
}

// Added in today's pull request.
int newCount(const std::vector<int>& readings)
{
    int n = readings.size();
    return n;
}
