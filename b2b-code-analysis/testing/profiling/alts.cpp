#include <algorithm>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <unordered_set>
#include <vector>
#include <ranges>
using clk = std::chrono::steady_clock;
static double ms(clk::time_point a, clk::time_point b){return std::chrono::duration<double,std::milli>(b-a).count();}
int main(int argc, char** argv){
  std::vector<int> r; { std::ifstream in(argv[1]); int v; while (in >> v) r.push_back(v); }
  { auto t0=clk::now(); std::vector<int> s(r); std::sort(s.begin(),s.end());
    auto last=std::unique(s.begin(),s.end()); int d=(int)(last-s.begin());
    std::printf("sort+unique          %7.1f ms  (d=%d)\n", ms(t0,clk::now()), d); }
  { auto t0=clk::now(); std::vector<int> s(r); std::ranges::sort(s);
    auto sub=std::ranges::unique(s); int d=(int)(sub.begin()-s.begin());
    std::printf("ranges::sort+unique  %7.1f ms  (d=%d)\n", ms(t0,clk::now()), d); }
  { auto t0=clk::now(); std::unordered_set<int> s(r.begin(),r.end()); int d=(int)s.size();
    std::printf("unordered_set        %7.1f ms  (d=%d)\n", ms(t0,clk::now()), d); }
}
