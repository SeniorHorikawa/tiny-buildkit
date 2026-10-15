#ifndef OMVLL_TOOLCHAIN_SHIM_H
#define OMVLL_TOOLCHAIN_SHIM_H

static unsigned long long omvll_rand_state_ = 0x9E3779B97F4A7C15ULL;

__attribute__((weak)) long lrand48(void) {
    omvll_rand_state_ = omvll_rand_state_ * 6364136223846793005ULL + 1442695040888963407ULL;
    return (long)((omvll_rand_state_ >> 33) & 0x7fffffffUL);
}

__attribute__((weak)) void srand48(long seed) {
    omvll_rand_state_ = (unsigned long long)seed * 6364136223846793005ULL + 1442695040888963407ULL;
}

__attribute__((weak)) int rand(void) {
    return (int)(lrand48() & 0x7fffffffL);
}

__attribute__((weak)) void srand(unsigned int seed) {
    srand48((long)seed);
}

#endif
