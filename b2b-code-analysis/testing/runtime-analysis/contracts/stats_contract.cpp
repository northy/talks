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
    std::vector<int> readings;       // nothing loaded -> violates the precondition
    std::cout << "mean " << meanOf(readings) << '\n';
}
