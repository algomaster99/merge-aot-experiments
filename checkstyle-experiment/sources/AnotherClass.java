package com.example;

import java.util.Collections;
import java.util.List;
import java.util.Optional;

/**
 * A second sample class with full Javadoc for contrast with SampleClass.
 */
public class AnotherClass {

    /** Default name used when no name is provided. */
    public static final String DEFAULT_NAME = "default";

    /** Maximum allowed name length. */
    public static final int MAX_NAME_LENGTH = 255;

    private final String name;
    private final int priority;

    /**
     * Constructs a new AnotherClass.
     *
     * @param name     the name, must not be null
     * @param priority the priority level (higher is more important)
     */
    public AnotherClass(String name, int priority) {
        if (name == null || name.length() > MAX_NAME_LENGTH) {
            throw new IllegalArgumentException("Invalid name");
        }
        this.name = name;
        this.priority = priority;
    }

    /**
     * Returns the name.
     *
     * @return the name
     */
    public String getName() {
        return name;
    }

    /**
     * Returns the priority.
     *
     * @return the priority level
     */
    public int getPriority() {
        return priority;
    }

    /**
     * Compares priority with another instance.
     *
     * @param other the other instance to compare
     * @return true if this instance has higher priority
     */
    public boolean isHigherPriorityThan(AnotherClass other) {
        return this.priority > other.priority;
    }

    /**
     * Returns an optional wrapping this instance if name is non-empty.
     *
     * @return optional containing this, or empty
     */
    public Optional<AnotherClass> asOptional() {
        return name.isEmpty() ? Optional.empty() : Optional.of(this);
    }

    /**
     * Returns a singleton list containing only this instance.
     *
     * @return immutable singleton list
     */
    public List<AnotherClass> asSingletonList() {
        return Collections.singletonList(this);
    }

    /**
     * Immutable value type for name/priority pairs.
     */
    public static final class Entry {

        private final String key;
        private final int value;

        /**
         * Constructs an Entry.
         *
         * @param key   the key
         * @param value the value
         */
        public Entry(String key, int value) {
            this.key = key;
            this.value = value;
        }

        /**
         * Returns the key.
         *
         * @return the key
         */
        public String getKey() {
            return key;
        }

        /**
         * Returns the value.
         *
         * @return the value
         */
        public int getValue() {
            return value;
        }
    }
}
