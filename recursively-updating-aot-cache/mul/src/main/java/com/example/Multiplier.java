package com.example;

public class Multiplier {

    private final Adder adder = new Adder();
    private final Subtractor subtractor = new Subtractor();

    public int multiply(int a, int b) {
        if (b == 0) return 0;
        int absB = b < 0 ? subtractor.subtract(0, b) : b;
        int result = 0;
        for (int i = 0; i < absB; i++) {
            result = adder.add(result, a);
        }
        return b < 0 ? subtractor.subtract(0, result) : result;
    }

    public long multiply(long a, long b) {
        if (b == 0) return 0;
        long absB = b < 0 ? subtractor.subtract(0L, b) : b;
        long result = 0;
        for (long i = 0; i < absB; i++) {
            result = adder.add(result, a);
        }
        return b < 0 ? subtractor.subtract(0L, result) : result;
    }

    public static void main(String[] args) {
        Multiplier m = new Multiplier();

        // Warm up so the JIT compiles these methods (including Adder + Subtractor)
        long result = 0;
        for (int i = 0; i < 50_000; i++) {
            result += m.multiply(i, 3);
            result += m.multiply(i, -1);
        }
        System.out.println("Multiplier warmup complete. Result: " + result);
    }
}
