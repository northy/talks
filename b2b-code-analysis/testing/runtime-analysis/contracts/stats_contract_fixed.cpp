#include <iostream>
#include <vector>

int meanOf(const std::vector<int>& readings)
    pre (!readings.empty())          // C++26 precondition (P2900)
{
    int sum = 0;
    for (int r : readings) sum += r;
    return sum / readings.size();
}

int main()
{
    std::vector<int> readings;       // nothing loaded
    if (readings.empty())            // the caller now honors the precondition
    {
        std::cout << "no readings\n";
        return 0;
    }
    std::cout << "mean " << meanOf(readings) << '\n';
}
