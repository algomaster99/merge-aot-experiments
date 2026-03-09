package com.example;

public class B {
    public String greet() {
        return "Hello from B";
    }

    public static void main(String[] args) {
        System.out.println(new B().greet());
    }
}
