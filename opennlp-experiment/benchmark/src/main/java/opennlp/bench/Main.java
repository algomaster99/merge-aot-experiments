package opennlp.bench;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

import morfologik.stemming.Dictionary;
import morfologik.stemming.DictionaryMetadata;

import opennlp.morfologik.builder.MorfologikDictionaryBuilder;
import opennlp.morfologik.lemmatizer.MorfologikLemmatizer;
import opennlp.morfologik.tagdict.MorfologikTagDictionary;

public class Main {

    private static final int LEMMATIZE_ITERS = 10_000;
    private static final int TAG_ITERS = 10_000;

    private static final String[] TOKENS = {"casa", "foi", "carro", "menino"};
    private static final String[] TAGS   = {"NOUN", "V",   "NOUN",  "NOUN"};
    private static final String[] WORDS  = {"casa", "carro", "foi", "menino", "casar", "ser"};

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: Main <op> <workdir>");
            System.exit(1);
        }
        String op = args[0];
        Path workDir = Path.of(args[1]);
        Files.createDirectories(workDir);

        switch (op) {
            case "prepare"    -> prepare(workDir);
            case "lemmatize"  -> lemmatize(workDir);
            case "build-dict" -> buildDict(workDir);
            case "tag"        -> tag(workDir);
            default -> {
                System.err.println("Unknown op: " + op);
                System.exit(1);
            }
        }
    }

    private static void prepare(Path workDir) throws IOException {
        copyResource("/dictionaryWithLemma.txt",  workDir.resolve("dictionaryWithLemma.txt"));
        copyResource("/dictionaryWithLemma.info", workDir.resolve("dictionaryWithLemma.info"));
        copyResource("/dictionaryWithLemma.dict", workDir.resolve("dictionaryWithLemma.dict"));
    }

    private static void lemmatize(Path workDir) throws IOException {
        Path dictPath = workDir.resolve("dictionaryWithLemma.dict");
        MorfologikLemmatizer lemmatizer = new MorfologikLemmatizer(dictPath);
        for (int i = 0; i < LEMMATIZE_ITERS; i++) {
            lemmatizer.lemmatize(TOKENS, TAGS);
        }
    }

    private static void buildDict(Path workDir) throws Exception {
        // Unique basename per process to avoid cross-run collisions
        String baseName = "dict_" + ProcessHandle.current().pid();
        Path tabFile  = workDir.resolve(baseName + ".txt");
        Path infoFile = DictionaryMetadata.getExpectedMetadataLocation(tabFile);
        copyResource("/dictionaryWithLemma.txt",  tabFile);
        copyResource("/dictionaryWithLemma.info", infoFile);
        Path output = new MorfologikDictionaryBuilder().build(tabFile);
        Files.deleteIfExists(output);
        Files.deleteIfExists(tabFile);
        Files.deleteIfExists(infoFile);
    }

    private static void tag(Path workDir) throws IOException {
        Path dictPath = workDir.resolve("dictionaryWithLemma.dict");
        Dictionary dic = Dictionary.read(dictPath);
        MorfologikTagDictionary tagDict = new MorfologikTagDictionary(dic, false);
        for (int i = 0; i < TAG_ITERS; i++) {
            for (String word : WORDS) {
                tagDict.getTags(word);
            }
        }
    }

    private static void copyResource(String resource, Path dest) throws IOException {
        try (InputStream in = Main.class.getResourceAsStream(resource)) {
            if (in == null) throw new IOException("Resource not found: " + resource);
            Files.copy(in, dest, StandardCopyOption.REPLACE_EXISTING);
        }
    }
}
