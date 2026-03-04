package com.example;

public class Adder {

    private final Subtractor subtractor = new Subtractor();

    public int add(int a, int b) {
        return a + b;
    }

    public long add(long a, long b) {
        return a + b;
    }

    // Demonstrates cross-module use: add two numbers then subtract an offset
    public int addWithOffset(int a, int b, int offset) {
        return subtractor.subtract(add(a, b), offset);
    }

    public static void main(String[] args) {
        Adder adder = new Adder();

        // Warm up so the JIT compiles these methods (including Subtractor)
        long result = 0;
        for (int i = 0; i < 500_000; i++) {
            result += adder.add(i, i + 1);
            result += adder.addWithOffset(i, i + 1, 1);
        }
        System.out.println("Adder warmup complete. Result: " + result);
    }
}
