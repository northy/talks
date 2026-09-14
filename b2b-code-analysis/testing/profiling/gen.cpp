// gen.cpp -- deterministic big-input generator for humidity-stats profiling demo.
// Emits N integer readings (one per line), uniform in [0, 100], mirroring the
// humidity-stats text input format (`while (in >> value)`).
//
//   g++ -std=c++20 -O2 gen.cpp -o gen
//   ./gen 20000000 big.txt         # 20M readings, range 0..100 (default)
//   ./gen 20000000 big.txt 1000    # optional: widen the value range
//
// The optional 3rd arg is the inclusive max value (default 100). Relative
// humidity is a percentage, so readings are 0..100 and no wider -- the same
// contract the histogram's 10 buckets and the range guard assume.
// Consequence for the profiling chapter: d <= 101 is a constant, so
// countDistinct's early `break` bounds it at O(n*d) = O(n) with a ~101x
// constant. It is ~45% of the run, not 92%; parsing is the other half.
// That is the honest shape of this program and the chapter measures it.
//
// Fixed seed => byte-identical file across runs (reproducible measurements).
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <string>

int main(int argc, char* argv[])
{
    if (argc < 3 || argc > 4)
    {
        std::fprintf(stderr, "usage: gen <count> <outfile> [maxval=100]\n");
        return 1;
    }

    const std::uint64_t count = std::strtoull(argv[1], nullptr, 10);
    const int maxval = (argc == 4) ? std::atoi(argv[3]) : 100;
    std::FILE* out = std::fopen(argv[2], "w");
    if (!out)
    {
        std::perror("fopen");
        return 1;
    }

    std::mt19937 rng(12345);                          // fixed seed
    std::uniform_int_distribution<int> dist(0, maxval); // inclusive 0..maxval

    // Buffered manual formatting: fast enough to generate 20M lines quickly.
    std::string buf;
    buf.reserve(1 << 20);
    char num[8];
    for (std::uint64_t i = 0; i < count; ++i)
    {
        const int v = dist(rng);
        const int len = std::snprintf(num, sizeof(num), "%d\n", v);
        buf.append(num, len);
        if (buf.size() > (1 << 20))
        {
            std::fwrite(buf.data(), 1, buf.size(), out);
            buf.clear();
        }
    }
    std::fwrite(buf.data(), 1, buf.size(), out);
    std::fclose(out);
    return 0;
}
