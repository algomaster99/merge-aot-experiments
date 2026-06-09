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
import java.util.Arrays;

import morfologik.stemming.Dictionary;

import opennlp.morfologik.builder.MorfologikDictionaryBuilder;
import opennlp.morfologik.lemmatizer.MorfologikLemmatizer;
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

    // Fixed tokens for POS tagging (exercises MaxentBeamSearch + context generators).
    private static final String[] TAG_TOKENS = {
        "The", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog",
        "and", "ran", "across", "the", "green", "field", "very", "quickly"
    };

    // Fixed tokens for lemmatization — forms that exist in large_dict with tag NOUN.
    private static final String[] LEMMA_TOKENS = {
        "form000000", "form000050", "form000100", "form000500", "form001000",
        "form005000", "form010000", "form020000", "form030000", "form040000"
    };
    private static final String[] LEMMA_TAGS = new String[LEMMA_TOKENS.length];
    static { Arrays.fill(LEMMA_TAGS, "NOUN"); }

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: Main <op> <workdir>");
            System.exit(1);
        }
        String op = args[0];
        Path workDir = Path.of(args[1]);
        Files.createDirectories(workDir);

        switch (op) {
            case "prepare"           -> prepare(workDir);
            case "train-sentdetect"  -> trainSentdetect(workDir);
            case "train-postag"      -> trainPostag(workDir);
            case "tag-and-lemmatize" -> tagAndLemmatize(workDir);
            default -> {
                System.err.println("Unknown op: " + op);
                System.exit(1);
            }
        }
    }

    private static void prepare(Path workDir) throws Exception {
        // Sentence corpus for train-sentdetect.
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

        // POS training data for train-postag.
        copyResource("/AnnotatedSentences.txt", workDir.resolve("AnnotatedSentences.txt"));

        // 50k-entry dictionary for tag-and-lemmatize; build the FSA here (not measured).
        Path largeDict = workDir.resolve("large_dict.txt");
        try (BufferedWriter w = Files.newBufferedWriter(largeDict, StandardCharsets.UTF_8)) {
            for (int i = 0; i < 50_000; i++) {
                w.write(String.format("form%06d,lemma%05d,NOUN%n", i, i / 5));
            }
        }
        copyResource("/dictionaryWithLemma.info", workDir.resolve("large_dict.info"));
        new MorfologikDictionaryBuilder().build(largeDict);

        // Pre-train POS model so tag-and-lemmatize can load it at measurement time.
        trainPostagImpl(workDir);
    }

    // Trains a sentence boundary detector on 8 language corpora (~1100 sentences).
    // Exercises: SentenceDetectorME, SentenceSampleStream, MaxentTrainer, GIS,
    //            sentence feature generators, model serialization.
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
    // Exercises: POSTaggerME, WordTagSampleStream, MaxentTrainer, GIS,
    //            POS context generators, model serialization.
    private static void trainPostag(Path workDir) throws IOException {
        trainPostagImpl(workDir);
    }

    private static void trainPostagImpl(Path workDir) throws IOException {
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

    // Loads the pre-trained POS model and morfologik dictionary, then runs
    // 10k rounds of POS tagging + lemmatization.
    // Exercises: POSModel/POSTaggerME (opennlp-tools model loading + MaxentBeamSearch),
    //            Dictionary/MorfologikLemmatizer (morfologik-stemming + opennlp-morfologik-addon).
    // Uses both halves of tree.aot so bulk class loading is well-utilized.
    private static void tagAndLemmatize(Path workDir) throws IOException {
        POSModel posModel;
        try (InputStream is = new BufferedInputStream(Files.newInputStream(workDir.resolve("postag.bin")))) {
            posModel = new POSModel(is);
        }
        POSTaggerME tagger = new POSTaggerME(posModel);

        Dictionary dict = Dictionary.read(workDir.resolve("large_dict.dict"));
        MorfologikLemmatizer lemmatizer = new MorfologikLemmatizer(dict);

        for (int i = 0; i < 10_000; i++) {
            tagger.tag(TAG_TOKENS);
            lemmatizer.lemmatize(LEMMA_TOKENS, LEMMA_TAGS);
        }
    }

    private static void copyResource(String resource, Path dest) throws IOException {
        try (InputStream in = Main.class.getResourceAsStream(resource)) {
            if (in == null) throw new IOException("Resource not found: " + resource);
            Files.copy(in, dest, StandardCopyOption.REPLACE_EXISTING);
        }
    }
}
