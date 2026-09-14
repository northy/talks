#include <vector>

// This narrowing predates our clang-tidy policy: grandfathered with NOLINT.
int legacyCount(const std::vector<int>& readings)
{
    // NOLINTNEXTLINE(bugprone-narrowing-conversions)
    int n = readings.size();
    return n;
}

// Added in today's pull request: NOT grandfathered, still flagged.
int newCount(const std::vector<int>& readings)
{
    int n = readings.size();
    return n;
}
