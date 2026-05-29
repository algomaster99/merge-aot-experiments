package dev.biojavaexp;

import org.biojava.nbio.core.sequence.DNASequence;
import org.biojava.nbio.core.sequence.ProteinSequence;
import org.biojava.nbio.core.sequence.RNASequence;
import org.biojava.nbio.core.sequence.compound.AminoAcidCompound;
import org.biojava.nbio.core.sequence.compound.AminoAcidCompoundSet;
import org.biojava.nbio.core.sequence.compound.RNACompoundSet;
import org.biojava.nbio.core.sequence.io.FastaReaderHelper;
import org.biojava.nbio.core.sequence.io.FastaWriterHelper;
import org.biojava.nbio.core.sequence.io.GenbankReaderHelper;
import org.biojava.nbio.core.sequence.io.GenbankWriterHelper;
import org.biojava.nbio.core.sequence.io.IUPACParser;
import org.biojava.nbio.core.sequence.transcription.Table;
import org.biojava.nbio.core.util.ConcurrencyTools;
import org.biojava.nbio.core.alignment.matrices.SubstitutionMatrixHelper;
import org.biojava.nbio.core.alignment.template.SubstitutionMatrix;

import org.biojava.nbio.alignment.Alignments;
import org.biojava.nbio.alignment.Alignments.PairwiseSequenceAlignerType;
import org.biojava.nbio.alignment.SimpleGapPenalty;
import org.biojava.nbio.alignment.template.PairwiseSequenceAligner;
import org.biojava.nbio.alignment.template.GapPenalty;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;

/**
 * BioJava startup benchmark.
 *
 * Workloads split across two cacheable artifacts:
 *   biojava-core      — sequence I/O (FASTA, GenBank), transcription, compound stats,
 *                       codon table enumeration (IUPACParser/SAX), sequence serialisation
 *   biojava-alignment — pairwise alignment (Needleman–Wunsch, Smith–Waterman),
 *                       progressive multiple sequence alignment (GuideTree, profile–profile)
 *
 * Each workload loads a largely disjoint class subtree, on a shared sequence/compound
 * core.  The log4j binding is excluded at build time (slf4j-simple is used instead) so
 * no module-info-bearing JAR is on the runtime classpath; biojava logs only through slf4j-api.
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
            case "prepare"        -> prepare(workDir);
            case "fasta-parse"    -> fastaParse(workDir);
            case "transcribe"     -> transcribe(workDir);
            case "revcomp-gc"     -> revcompGc(workDir);
            case "align-global"   -> align(PairwiseSequenceAlignerType.GLOBAL);
            case "codon-usage"    -> codonUsage();
            case "genbank-write"  -> genbankWrite(workDir);
            case "msa"            -> msa();
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

    // biojava-core: IUPACParser (SAX-based XML resource) + codon-table enumeration subtree.
    // Distinct from all other workloads: loads SAX parser classes, IUPACParser, Table$Codon,
    // RNACompoundSet, and related codon-lookup infrastructure.
    static void codonUsage() throws Exception {
        IUPACParser.IUPACTable table = IUPACParser.getInstance().getTable(1); // standard genetic code
        List<Table.Codon> codons = table.getCodons(
            RNACompoundSet.getRNACompoundSet(),
            AminoAcidCompoundSet.getAminoAcidCompoundSet());
        Map<String, Integer> usage = new HashMap<>();
        int stops = 0;
        for (Table.Codon c : codons) {
            if (c.isStop()) { stops++; continue; }
            usage.merge(c.getAminoAcid().getShortName(), 1, Integer::sum);
        }
        if (usage.isEmpty() || stops == 0) throw new IllegalStateException("bad codon table");
    }

    // biojava-core: sequence serialisation — writer class subtree (FastaWriter,
    // GenbankWriter, GenericFastaHeaderFormat).  Distinct from the reader-side
    // classes loaded by fasta-parse and genbank-parse.
    static void genbankWrite(Path workDir) throws Exception {
        // Round-trip: parse the GenBank record written by prepare(), then write both FASTA and GenBank.
        Map<String, DNASequence> seqs =
            GenbankReaderHelper.readGenbankDNASequence(workDir.resolve("seq.gb").toFile());
        ByteArrayOutputStream fastaOut = new ByteArrayOutputStream();
        FastaWriterHelper.writeNucleotideSequence(fastaOut, seqs.values());
        ByteArrayOutputStream gbOut = new ByteArrayOutputStream();
        GenbankWriterHelper.writeNucleotideSequence(gbOut, seqs.values());
        if (fastaOut.size() == 0 || gbOut.size() == 0) throw new IllegalStateException("empty write output");
    }

    // biojava-alignment: progressive multiple sequence alignment subtree.
    // Distinct from pairwise alignment: loads GuideTree, SimpleProfileProfileAligner,
    // FractionalIdentityInProfileScorer, AbstractProfileProfileAligner, etc.
    // ConcurrencyTools.shutdown() is required: getMultipleSequenceAlignment submits tasks
    // to BioJava's global ThreadPoolExecutor whose non-daemon threads prevent JVM exit.
    static void msa() throws Exception {
        List<ProteinSequence> seqs = new ArrayList<>();
        seqs.add(new ProteinSequence("MTADGPRELLQLRAAVRHRGLLAELLRDR"));
        seqs.add(new ProteinSequence("MTADGPKELLQLRSAVRHHGLLAELLRER"));
        seqs.add(new ProteinSequence("MPADGPRQLLQLRAAVRHRGLLAELLRDK"));
        seqs.add(new ProteinSequence("MTVDGPRELLELRAAVRHRGLLSELLRDR"));
        org.biojava.nbio.core.alignment.template.Profile<ProteinSequence, AminoAcidCompound> profile =
            Alignments.getMultipleSequenceAlignment(seqs);
        ConcurrencyTools.shutdown();
        if (profile.getSize() == 0) throw new IllegalStateException("empty MSA");
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
