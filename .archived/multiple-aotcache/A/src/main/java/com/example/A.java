package com.example;

public class A {
    public String greet() {
        return "Hello from A";
    }

    public static void main(String[] args) {
        System.out.println(new A().greet());
    }
}
