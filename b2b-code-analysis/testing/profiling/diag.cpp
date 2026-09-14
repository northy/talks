#include "stats.hpp"
#include <chrono>
#include <cstdio>
#include <fstream>
#include <array>
#include <string>
using clk=std::chrono::steady_clock;
static double ms(clk::time_point a,clk::time_point b){return std::chrono::duration<double,std::milli>(b-a).count();}
std::vector<int> load(const std::string&p){std::vector<int>r;std::ifstream in(p);int v;while(in>>v)r.push_back(v);return r;}
int main(int argc,char**argv){
  auto t0=clk::now();
  auto r=load(argv[1]);
  auto t1=clk::now();
  auto s=computeStats(r);
  auto t2=clk::now();
  int d=countDistinct(r);
  auto t3=clk::now();
  std::array<int,10>b{};for(int x:r){std::size_t k=(std::size_t)x/10;if(k>9)k=9;++b[k];}
  auto t4=clk::now();
  std::printf("n=%zu distinct=%d mean=%d\n",r.size(),d,s.mean);
  std::printf("load       %8.1f ms\n",ms(t0,t1));
  std::printf("computeStat%8.1f ms\n",ms(t1,t2));
  std::printf("countDist  %8.1f ms\n",ms(t2,t3));
  std::printf("histogram  %8.1f ms\n",ms(t3,t4));
  volatile int z=b[0];(void)z;
}
