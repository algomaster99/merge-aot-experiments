package com.example;

public class MathApp {

    public static void main(String[] args) {
        Subtractor sub = new Subtractor();
        Adder add = new Adder();
        Multiplier mul = new Multiplier();

        int a = 10, b = 3;
        System.out.println(a + " + " + b + " = " + add.add(a, b));
        System.out.println(a + " - " + b + " = " + sub.subtract(a, b));
        System.out.println(a + " * " + b + " = " + mul.multiply(a, b));

        // A slightly heavier workload so the AOT cache has something to offer
        long result = 0;
        for (int i = 1; i <= 1_000; i++) {
            result += mul.multiply(add.add(i, 2), sub.subtract(i, 1));
        }
        System.out.println("Combined result: " + result);
    }
}
