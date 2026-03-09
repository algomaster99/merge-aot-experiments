package com.example;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Assertions;

public class BTest {
    @Test
    public void testGreet() {
        B b = new B();
        Assertions.assertEquals("Hello from B", b.greet());
    }
}
