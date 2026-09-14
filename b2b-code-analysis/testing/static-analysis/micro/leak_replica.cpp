#include <vector>
std::vector<int>* load()
{
    return new std::vector<int>{1, 2, 3};
}
int main()
{
    const std::vector<int>& v = *load();   // pointer laundered through reference
    return v.size();
}
