package com.example;

public class Subtractor {

    public int subtract(int a, int b) {
        return a - b;
    }

    public long subtract(long a, long b) {
        return a - b;
    }

    public static void main(String[] args) {
        Subtractor s = new Subtractor();

        // Warm up so the JIT compiles these methods
        long result = 0;
        for (int i = 0; i < 500_000; i++) {
            result += s.subtract(i, i / 2);
        }
        System.out.println("Subtractor warmup complete. Result: " + result);
    }
}
