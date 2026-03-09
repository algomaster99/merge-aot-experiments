package com.example;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Assertions;

public class ATest {
    @Test
    public void testGreet() {
        A a = new A();
        Assertions.assertEquals("Hello from A", a.greet());
    }
}
