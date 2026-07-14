#include "mathutils.hpp"

#include <iostream>
#include <vector>

int main() {
    std::cout << "== Emacs C++ demo ==\n";

    const std::vector<int> numbers = {5, 3, 8, 1, 9, 2, 7};

    // Good place for a breakpoint (C-c d b), then C-c d d to launch and
    // C-c d i to inspect `numbers`, `total`, etc.
    const long total = demo::sum(numbers);
    std::cout << "sum   = " << total << '\n';
    std::cout << "max   = " << demo::max_element(numbers) << '\n';

    for (int n = 1; n <= 6; ++n) {
        std::cout << n << "! = " << demo::factorial(n) << "   fib(" << n
                  << ") = " << demo::fibonacci(n) << '\n';
    }

    std::cout << "primes <= 20:";
    for (int n = 2; n <= 20; ++n) {
        if (demo::is_prime(n)) {
            std::cout << ' ' << n;
        }
    }
    std::cout << '\n';

    return 0;
}
