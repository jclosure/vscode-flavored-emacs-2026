#include "mathutils.hpp"

namespace demo {

long sum(const std::vector<int>& values) {
    long total = 0;
    for (int v : values) {
        total += v;
    }
    return total;
}

int max_element(const std::vector<int>& values) {
    int best = values.front();
    for (int v : values) {
        if (v > best) {
            best = v;
        }
    }
    return best;
}

long factorial(int n) {
    if (n <= 1) {
        return 1;
    }
    return n * factorial(n - 1); // recursion -> step in here with the debugger
}

long fibonacci(int n) {
    long a = 0;
    long b = 1;
    for (int i = 0; i < n; ++i) {
        const long next = a + b;
        a = b;
        b = next;
    }
    return a;
}

bool is_prime(int n) {
    if (n < 2) {
        return false;
    }
    for (int d = 2; d * d <= n; ++d) {
        if (n % d == 0) {
            return false;
        }
    }
    return true;
}

} // namespace demo
