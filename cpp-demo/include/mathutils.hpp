#pragma once

#include <vector>

// A tiny library so you can test cross-file navigation in Emacs:
// put the cursor on `demo::factorial` in main.cpp and press M-. to jump
// here, then M-, to jump back.
namespace demo {

// Sum of all elements.
long sum(const std::vector<int>& values);

// Largest element (assumes a non-empty vector).
int max_element(const std::vector<int>& values);

// n! computed recursively -- gives you a nice call stack in the debugger.
long factorial(int n);

// nth Fibonacci number (iterative).
long fibonacci(int n);

// Trial-division primality test.
bool is_prime(int n);

} // namespace demo
