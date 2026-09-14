You are performing a blind static code review. IMPORTANT CONSTRAINTS: Do NOT
use any tools. Do NOT read any files, do NOT search any directories, do NOT
run any commands, do NOT execute or compile the code. Work ONLY from the code
pasted below, using pure reading/reasoning. Your entire output must be your
final text response.

Below is a small C++ program (three files) that reads integer sensor readings
from a file and prints statistics. Review it as an expert C++ reviewer. Find
ALL the problems you can — bugs, undefined behavior, memory issues, robustness
problems, performance problems, style/readability/convention issues, API
design issues — strictly by reading the code. For each problem give:
1. File and line (use the line numbers as given by counting from 1 at the top
   of each file).
2. Severity (bug / UB / leak / performance / robustness / style).
3. What exactly is wrong and under what input it manifests.
4. A concrete fix (short code snippet where useful).

Order findings from most to least severe. At the end, add a short "rewritten
highlights" section showing the key fixed code. Be exhaustive — include even
minor issues.

=== FILE: stats.hpp ===
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
=== FILE: stats.cpp ===
#include "stats.hpp"

#include <algorithm>
#include <limits>

Stats computeStats(const std::vector<int>& readings)
{
    int minimum = std::numeric_limits<int>::max();
    int maximum = std::numeric_limits<int>::min();
    int sum = 0;

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
=== FILE: main.cpp ===
#include "stats.hpp"

#include <array>
#include <fstream>
#include <iostream>

std::vector<int>* loadReadings(const std::string& path)
{
    auto* readings = new std::vector<int>;
    std::ifstream in(path);
    int value = 0;
    while (in >> value)
    {
        readings->push_back(value);
    }
    return readings;
}

std::array<int, 10> histogram(const std::vector<int>& readings)
{
    std::array<int, 10> buckets{};
    for (int r : readings)
    {
        ++buckets[r / 10];
    }
    return buckets;
}

void printReport(const Stats& stats, bool verbose)
{
    std::cout << "min " << stats.minimum
              << " max " << stats.maximum
              << " mean " << stats.mean << '\n';
}

int main(int argc, char* argv[])
{
    if (argc != 2)
    {
        std::cerr << "usage: humidity-stats <file>\n";
        return 1;
    }

    int checksum = 0;
    const std::vector<int>& readings = *loadReadings(argv[1]);

    if (readings.empty())
    {
        std::cout << "warning: no readings loaded\n";
    }

    printReport(computeStats(readings), false);
    std::cout << "distinct " << countDistinct(readings) << '\n';

    for (int count : histogram(readings))
    {
        std::cout << count << ' ';
    }
    std::cout << '\n';
}
