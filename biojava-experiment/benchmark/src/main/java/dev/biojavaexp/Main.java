package dev.biojavaexp;

import org.biojava.nbio.core.sequence.DNASequence;
import org.biojava.nbio.core.sequence.ProteinSequence;
import org.biojava.nbio.core.sequence.RNASequence;
import org.biojava.nbio.core.sequence.compound.AminoAcidCompound;
import org.biojava.nbio.core.sequence.io.FastaReaderHelper;
import org.biojava.nbio.core.sequence.io.GenbankReaderHelper;
import org.biojava.nbio.core.alignment.matrices.SubstitutionMatrixHelper;
import org.biojava.nbio.core.alignment.template.SubstitutionMatrix;

import org.biojava.nbio.alignment.Alignments;
import org.biojava.nbio.alignment.Alignments.PairwiseSequenceAlignerType;
import org.biojava.nbio.alignment.SimpleGapPenalty;
import org.biojava.nbio.alignment.template.PairwiseSequenceAligner;
import org.biojava.nbio.alignment.template.GapPenalty;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Map;
import java.util.Random;

/**
 * BioJava startup benchmark.
 *
 * Workloads split across two cacheable artifacts:
 *   biojava-core      — sequence I/O (FASTA, GenBank), transcription, compound stats
 *   biojava-alignment — pairwise alignment (Needleman–Wunsch, Smith–Waterman)
 *
 * Each workload loads a largely disjoint class subtree (format parsers vs.
 * transcription engine vs. dynamic-programming aligners + substitution
 * matrices), on a shared sequence/compound core. The log4j binding is excluded
 * at build time (slf4j-simple is used instead) so no module-info-bearing JAR is
 * on the runtime classpath; biojava logs only through slf4j-api.
 */
public class Main {

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: Main <command> <workdir>");
            System.exit(1);
        }
        String cmd = args[0];
        Path workDir = Paths.get(args[1]);
        switch (cmd) {
            case "prepare"      -> prepare(workDir);
            case "fasta-parse"  -> fastaParse(workDir);
            case "genbank-parse" -> genbankParse(workDir);
            case "transcribe"   -> transcribe(workDir);
            case "revcomp-gc"   -> revcompGc(workDir);
            case "align-global" -> align(PairwiseSequenceAlignerType.GLOBAL);
            case "align-local"  -> align(PairwiseSequenceAlignerType.LOCAL);
            default -> { System.err.println("Unknown command: " + cmd); System.exit(1); }
        }
    }

    static void prepare(Path workDir) throws Exception {
        Files.createDirectories(workDir);
        Files.writeString(workDir.resolve("seqs.fasta"), FASTA);
        Files.writeString(workDir.resolve("seq.gb"), GENBANK);
    }

    // biojava-core: FASTA parser subtree
    static void fastaParse(Path workDir) throws Exception {
        Map<String, DNASequence> seqs =
            FastaReaderHelper.readFastaDNASequence(workDir.resolve("seqs.fasta").toFile());
        long total = 0;
        for (DNASequence s : seqs.values()) total += s.getLength();
        if (total == 0) throw new IllegalStateException("empty FASTA");
    }

    // biojava-core: GenBank parser subtree
    static void genbankParse(Path workDir) throws Exception {
        Map<String, DNASequence> seqs =
            GenbankReaderHelper.readGenbankDNASequence(workDir.resolve("seq.gb").toFile());
        for (DNASequence s : seqs.values()) s.getSequenceAsString();
    }

    // biojava-core: transcription engine + translation subtree
    static void transcribe(Path workDir) throws Exception {
        DNASequence dna = new DNASequence(repeat("ATGGCCATTGTAATGGGCCGCTGAAAGGGTGCCCGATAG", 30));
        RNASequence rna = dna.getRNASequence();
        ProteinSequence protein = rna.getProteinSequence();
        if (protein.getLength() == 0) throw new IllegalStateException("no protein");
    }

    // biojava-core: compound stats / reverse complement subtree
    static void revcompGc(Path workDir) throws Exception {
        DNASequence dna = new DNASequence(randomDna(20_000));
        dna.getReverseComplement().getViewedSequence().getLength();
        int gc = dna.getGCCount();
        if (gc < 0) throw new IllegalStateException("bad GC");
    }

    // biojava-alignment: pairwise dynamic-programming aligner subtree
    static void align(PairwiseSequenceAlignerType type) throws Exception {
        ProteinSequence query  = new ProteinSequence("MTADGPRELLQLRAAVRHRGLLAELLRDR");
        ProteinSequence target = new ProteinSequence("MTADGPKELLQLRSAVRHHGLLAELLRER");
        SubstitutionMatrix<AminoAcidCompound> matrix = SubstitutionMatrixHelper.getBlosum62();
        GapPenalty gap = new SimpleGapPenalty();
        PairwiseSequenceAligner<ProteinSequence, AminoAcidCompound> aligner =
            Alignments.getPairwiseAligner(query, target, type, gap, matrix);
        aligner.getScore();
    }

    // -------------------------------------------------------------------------

    static String repeat(String s, int n) {
        StringBuilder sb = new StringBuilder(s.length() * n);
        for (int i = 0; i < n; i++) sb.append(s);
        return sb.toString();
    }

    static String randomDna(int len) {
        char[] bases = {'A', 'C', 'G', 'T'};
        Random r = new Random(42);
        StringBuilder sb = new StringBuilder(len);
        for (int i = 0; i < len; i++) sb.append(bases[r.nextInt(4)]);
        return sb.toString();
    }

    static final String FASTA = """
        >seq1 sample DNA
        ATGGCCATTGTAATGGGCCGCTGAAAGGGTGCCCGATAGCTAGCTAGCATCGATCGTAGC
        TAGCTAGCATCGATCGATCGTACGTAGCTAGCTAGCTAGCATCGATCGATCGTAGCTAGC
        >seq2 another DNA
        TTGACCAATTGGCCATTGTAATGGGCCGCTGAAAGGGTGCCCGATAGCTAGCATCGATCG
        ATCGTAGCTAGCTAGCATCGATCGATCGTACGTAGCTAGCTAGCTAGCATCGATCGATCG
        >seq3 third DNA
        GGGCCCAAATTTGGGCCCAAATTTATGGCCATTGTAATGGGCCGCTGAAAGGGTGCCCGA
        """;

    // A minimal but well-formed GenBank record.
    static final String GENBANK = """
        LOCUS       SAMPLE                   120 bp    DNA     linear   SYN 01-JAN-2020
        DEFINITION  Synthetic sample sequence.
        ACCESSION   SAMPLE
        VERSION     SAMPLE.1
        FEATURES             Location/Qualifiers
             source          1..120
                             /organism="synthetic construct"
        ORIGIN
                1 atggccattg taatgggccg ctgaaagggt gcccgatagc tagctagcat cgatcgtagc
               61 tagctagcat cgatcgatcg tacgtagcta gctagctagc atcgatcgat cgtagctagc
        //
        """;
}
