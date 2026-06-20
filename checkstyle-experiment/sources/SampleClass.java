package com.example;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class SampleClass {

    private static final int MAX_VALUE = 100;
    private static final String DEFAULT_PREFIX = "item";

    private int counter;
    private String label;

    public SampleClass(int counter, String label) {
        this.counter = counter;
        this.label = label;
    }

    public int getCounter() {
        return counter;
    }

    public String getLabel() {
        return label;
    }

    public int computeResult(int inputParam, int anotherParam) {
        int localVar = inputParam + anotherParam;
        if (localVar > MAX_VALUE) {
            return MAX_VALUE;
        }
        return localVar;
    }

    public List<String> buildItems(String prefix, int count, boolean includeEmpty, String suffix, int limit) {
        List<String> result = new ArrayList<>();
        for (int i = 0; i < count && i < limit; i++) {
            String item = prefix + i + suffix;
            if (includeEmpty || !item.isEmpty()) {
                result.add(item);
            }
        }
        return result;
    }

    public void processEntries(Map<String, List<Integer>> data) {
        for (Map.Entry<String, List<Integer>> entry : data.entrySet()) {
            String key = entry.getKey();
            List<Integer> values = entry.getValue();
            for (int val : values) {
                if (val > 0) {
                    if (val > 50) {
                        System.out.println(key + ": " + val);
                    }
                }
            }
        }
    }

    public static class Builder {

        private int counter = 0;
        private String label = DEFAULT_PREFIX;

        public Builder counter(int counter) {
            this.counter = counter;
            return this;
        }

        public Builder label(String label) {
            this.label = label;
            return this;
        }

        public SampleClass build() {
            return new SampleClass(counter, label);
        }
    }
}
