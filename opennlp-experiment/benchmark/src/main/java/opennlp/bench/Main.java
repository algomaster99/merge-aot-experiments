package opennlp.bench;

import java.io.BufferedInputStream;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.BufferedReader;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

import morfologik.fsa.FSA;
import morfologik.stemming.Dictionary;
import morfologik.stemming.DictionaryLookup;
import morfologik.stemming.DictionaryMetadata;

import opennlp.morfologik.builder.MorfologikDictionaryBuilder;
import opennlp.tools.postag.POSModel;
import opennlp.tools.postag.POSSample;
import opennlp.tools.postag.POSTaggerFactory;
import opennlp.tools.postag.POSTaggerME;
import opennlp.tools.postag.WordTagSampleStream;
import opennlp.tools.sentdetect.SentenceDetectorFactory;
import opennlp.tools.sentdetect.SentenceDetectorME;
import opennlp.tools.sentdetect.SentenceModel;
import opennlp.tools.sentdetect.SentenceSample;
import opennlp.tools.sentdetect.SentenceSampleStream;
import opennlp.tools.util.MarkableFileInputStreamFactory;
import opennlp.tools.util.ObjectStream;
import opennlp.tools.util.PlainTextByLineStream;
import opennlp.tools.util.TrainingParameters;

public class Main {

    private static final String[] SENTENCE_FILES = {
        "/Sentences.txt",
        "/Sentences_DE.txt", "/Sentences_ES.txt", "/Sentences_FR.txt",
        "/Sentences_IT.txt", "/Sentences_NL.txt", "/Sentences_PL.txt",
        "/Sentences_PT.txt"
    };

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: Main <op> <workdir>");
            System.exit(1);
        }
        String op = args[0];
        Path workDir = Path.of(args[1]);
        Files.createDirectories(workDir);

        switch (op) {
            case "prepare"          -> prepare(workDir);
            case "train-sentdetect" -> trainSentdetect(workDir);
            case "train-postag"     -> trainPostag(workDir);
            case "load-and-lookup"  -> loadAndLookup(workDir);
            default -> {
                System.err.println("Unknown op: " + op);
                System.exit(1);
            }
        }
    }

    private static void prepare(Path workDir) throws Exception {
        // Concatenate all language sentence files into one training corpus.
        Path allSentences = workDir.resolve("all-sentences.txt");
        try (BufferedWriter w = Files.newBufferedWriter(allSentences, StandardCharsets.UTF_8)) {
            for (String res : SENTENCE_FILES) {
                try (InputStream in = Main.class.getResourceAsStream(res);
                     BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
                    r.lines().forEach(line -> {
                        try { w.write(line); w.newLine(); }
                        catch (IOException e) { throw new UncheckedIOException(e); }
                    });
                    w.newLine();
                }
            }
        }

        copyResource("/AnnotatedSentences.txt", workDir.resolve("AnnotatedSentences.txt"));

        // Generate 50k-entry dictionary and build its FSA so load-and-lookup can
        // just load (not build) the automaton — making that workload startup-dominated.
        Path largeDict = workDir.resolve("large_dict.txt");
        try (BufferedWriter w = Files.newBufferedWriter(largeDict, StandardCharsets.UTF_8)) {
            for (int i = 0; i < 50_000; i++) {
                w.write(String.format("form%06d,lemma%05d,NOUN%n", i, i / 5));
            }
        }
        copyResource("/dictionaryWithLemma.info", workDir.resolve("large_dict.info"));
        // Build the FSA once here (not measured); load-and-lookup loads the result.
        new MorfologikDictionaryBuilder().build(largeDict);
    }

    // Trains a sentence boundary detector on 8 language corpora (~1100 sentences).
    // Exercises: SentenceDetectorME, SentenceSampleStream, SentenceDetectorFactory,
    //            MaxentTrainer, GIS, sentence feature generators, model serialization.
    private static void trainSentdetect(Path workDir) throws IOException {
        MarkableFileInputStreamFactory dataIn = new MarkableFileInputStreamFactory(
            workDir.resolve("all-sentences.txt").toFile());
        try (ObjectStream<String> lineStream = new PlainTextByLineStream(dataIn, StandardCharsets.UTF_8);
             ObjectStream<SentenceSample> sampleStream = new SentenceSampleStream(lineStream)) {
            SentenceDetectorFactory factory = new SentenceDetectorFactory("eng", true, null, null);
            SentenceModel model = SentenceDetectorME.train("eng", sampleStream, factory,
                TrainingParameters.defaultParams());
            try (OutputStream out = Files.newOutputStream(workDir.resolve("sentdetect.bin"))) {
                model.serialize(out);
            }
        }
    }

    // Trains a POS tagger (135 annotated sentences, ~100 iterations).
    // Exercises: POSTaggerME, WordTagSampleStream, POSTaggerFactory,
    //            MaxentTrainer, GIS, POS context generators, model serialization.
    // Shares the opennlp ML backend with train-sentdetect → cross-workload
    // caches transfer well between these two.
    private static void trainPostag(Path workDir) throws IOException {
        MarkableFileInputStreamFactory dataIn = new MarkableFileInputStreamFactory(
            workDir.resolve("AnnotatedSentences.txt").toFile());
        try (ObjectStream<String> lineStream = new PlainTextByLineStream(dataIn, StandardCharsets.UTF_8);
             ObjectStream<POSSample> sampleStream = new WordTagSampleStream(lineStream)) {
            POSModel model = POSTaggerME.train("eng", sampleStream,
                TrainingParameters.defaultParams(), new POSTaggerFactory());
            try (OutputStream out = Files.newOutputStream(workDir.resolve("postag.bin"))) {
                model.serialize(out);
            }
        }
    }

    // Loads a pre-built 50k-entry morfologik FSA from disk, then runs 100k lookups.
    // Exercises: FSA.read (deserialization), DictionaryLookup, morfologik-fsa classes —
    // completely different class tree from the opennlp training workloads.
    // Startup/class-loading is the dominant cost, making it responsive to AOT.
    private static void loadAndLookup(Path workDir) throws IOException {
        Path dictFile = workDir.resolve("large_dict.dict");
        Path infoFile = workDir.resolve("large_dict.info");
        DictionaryMetadata metadata;
        try (InputStream is = new BufferedInputStream(Files.newInputStream(infoFile))) {
            metadata = DictionaryMetadata.read(is);
        }
        FSA fsa;
        try (InputStream is = new BufferedInputStream(Files.newInputStream(dictFile))) {
            fsa = FSA.read(is);
        }
        DictionaryLookup lookup = new DictionaryLookup(new Dictionary(fsa, metadata));
        // Cycle through 1000 evenly-spaced forms to avoid branch prediction bias.
        String[] forms = new String[1000];
        for (int i = 0; i < forms.length; i++) {
            forms[i] = String.format("form%06d", i * 50);
        }
        for (int i = 0; i < 100_000; i++) {
            lookup.lookup(forms[i % forms.length]);
        }
    }

    private static void copyResource(String resource, Path dest) throws IOException {
        try (InputStream in = Main.class.getResourceAsStream(resource)) {
            if (in == null) throw new IOException("Resource not found: " + resource);
            Files.copy(in, dest, StandardCopyOption.REPLACE_EXISTING);
        }
    }
}
