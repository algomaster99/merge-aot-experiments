package opennlp.bench;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

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
            case "build-dict"       -> buildDict(workDir);
            default -> {
                System.err.println("Unknown op: " + op);
                System.exit(1);
            }
        }
    }

    private static void prepare(Path workDir) throws IOException {
        copyResource("/Sentences.txt",            workDir.resolve("Sentences.txt"));
        copyResource("/AnnotatedSentences.txt",   workDir.resolve("AnnotatedSentences.txt"));
        copyResource("/dictionaryWithLemma.txt",  workDir.resolve("dictionaryWithLemma.txt"));
        copyResource("/dictionaryWithLemma.info", workDir.resolve("dictionaryWithLemma.info"));
    }

    // Trains a sentence boundary detector.
    // Exercises: SentenceDetectorME, SentenceSampleStream, SentenceDetectorFactory,
    //            MaxentTrainer, GIS, sentence feature generators, model serialization.
    private static void trainSentdetect(Path workDir) throws IOException {
        MarkableFileInputStreamFactory dataIn = new MarkableFileInputStreamFactory(
            workDir.resolve("Sentences.txt").toFile());
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

    // Trains a POS tagger.
    // Exercises: POSTaggerME, WordTagSampleStream, POSTaggerFactory,
    //            MaxentTrainer, GIS, POS context generators, model serialization.
    // Shares ~90% of class tree with train-sentdetect (same ML backend) — cross-workload
    // caches should transfer well between these two.
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

    // Builds a Morfologik FSA dictionary from tab-separated input.
    // Exercises: MorfologikDictionaryBuilder, DictCompile, morfologik-tools,
    //            morfologik-fsa-builders, HPPC — entirely different class tree from opennlp.
    private static void buildDict(Path workDir) throws Exception {
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

    private static void copyResource(String resource, Path dest) throws IOException {
        try (InputStream in = Main.class.getResourceAsStream(resource)) {
            if (in == null) throw new IOException("Resource not found: " + resource);
            Files.copy(in, dest, StandardCopyOption.REPLACE_EXISTING);
        }
    }
}
