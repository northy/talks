#include "stats.hpp"

#include <algorithm>
#include <array>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

std::vector<int> loadReadings(const std::string& path) // Fix: return by value
{
    std::vector<int> readings;
    std::ifstream in(path);
    int value = 0;
    while (in >> value)
    {
        readings.push_back(value);
    }
    return readings;
}

std::array<int, 10> histogram(const std::vector<int>& readings)
{
    std::array<int, 10> buckets{};
    for (int r : readings)
    {
        if (r < 0 || r > 100)
        {
            continue; // Fix: outside the documented range, garbage: skip it
        }
        ++buckets[std::min(r / 10, 9)]; // Fix: 100 belongs to the top bucket
    }
    return buckets;
}

void printReport(const Stats& stats)
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

    const std::vector<int> readings = loadReadings(argv[1]);

    if (readings.empty())
    {
        std::cout << "warning: no readings loaded\n";
        return 0; // Fix: bail out before computing on nothing
    }

    printReport(computeStats(readings));
    std::cout << "distinct " << countDistinct(readings) << '\n';

    for (int count : histogram(readings))
    {
        std::cout << count << ' ';
    }
    std::cout << '\n';
}
