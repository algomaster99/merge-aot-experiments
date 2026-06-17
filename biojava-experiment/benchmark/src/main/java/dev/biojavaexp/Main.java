package dev.biojavaexp;

import org.biojava.nbio.core.sequence.ProteinSequence;
import org.biojava.nbio.core.sequence.compound.AminoAcidCompound;
import org.biojava.nbio.core.sequence.io.FastaWriterHelper;
import org.biojava.nbio.core.sequence.io.GenbankReaderHelper;
import org.biojava.nbio.core.sequence.io.GenbankWriterHelper;
import org.biojava.nbio.core.util.ConcurrencyTools;
import org.biojava.nbio.core.alignment.matrices.SubstitutionMatrixHelper;
import org.biojava.nbio.core.alignment.template.SubstitutionMatrix;

import org.biojava.nbio.alignment.Alignments;
import org.biojava.nbio.alignment.Alignments.PairwiseSequenceAlignerType;
import org.biojava.nbio.alignment.SimpleGapPenalty;
import org.biojava.nbio.alignment.template.PairwiseSequenceAligner;
import org.biojava.nbio.alignment.template.GapPenalty;

import org.biojava.nbio.aaproperties.PeptideProperties;
import org.biojava.nbio.aaproperties.xml.AminoAcidCompositionTable;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;

/**
 * BioJava startup benchmark.
 *
 * Workloads are chosen to minimise pairwise class-set overlap so that cross-workload
 * single.aot is a poor fit and tree.aot (built from full test suites) can win.
 * Workloads with high cross-workload coverage (≥94 %) — fasta-parse, revcomp-gc,
 * codon-usage — were dropped because a random other single.aot already covers nearly
 * all of their class set, leaving no headroom for tree.aot.
 *
 *   biojava-core/io-write       — genbank-write (GenbankReader + Fasta/GenbankWriter)
 *   biojava-alignment/pairwise  — align-global (Needleman–Wunsch DP)
 *   biojava-alignment/msa       — msa (GuideTree, profile–profile)
 *   biojava-aa-prop/jaxb        — aa-prop (JAXB XML unmarshal → molecular weight)
 *
 * The aa-prop workload deliberately triggers the JAXB path (obtainAminoAcidCompositionTable
 * + getMolecularWeightBasedOnXML) which loads ~200-300 unique JAXB-runtime classes absent
 * from every other workload, pushing its cross-workload coverage below the ~88 % threshold
 * at which tree.aot starts winning.
 *
 * module-info mitigation: log4j-core and jaxb-runtime both carry module-info; the shade
 * plugin strips all module-info.class files from the fat JAR, so running in classpath mode
 * is safe.
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
            case "genbank-write"  -> genbankWrite(workDir);
            case "align-global"   -> align(PairwiseSequenceAlignerType.GLOBAL);
            case "msa"            -> msa();
            case "aa-prop"        -> aaProp(workDir);
            default -> { System.err.println("Unknown command: " + cmd); System.exit(1); }
        }
    }

    static void prepare(Path workDir) throws Exception {
        Files.createDirectories(workDir);
        Files.writeString(workDir.resolve("seq.gb"), GENBANK);
        // Extract aa-prop XML resources from the fat JAR into the work dir so the
        // JAXB-based getMolecularWeightBasedOnXML path can locate them via File args.
        for (String res : new String[]{"ElementMass.xml", "AminoAcidComposition.xml"}) {
            try (InputStream is = Main.class.getResourceAsStream("/" + res)) {
                if (is == null) throw new IllegalStateException("resource not found: " + res);
                Files.copy(is, workDir.resolve(res), StandardCopyOption.REPLACE_EXISTING);
            }
        }
    }

    // biojava-core: sequence serialisation — writer class subtree (FastaWriter,
    // GenbankWriter, GenericFastaHeaderFormat).
    static void genbankWrite(Path workDir) throws Exception {
        // Round-trip: parse the GenBank record written by prepare(), then write both FASTA and GenBank.
        var seqs = GenbankReaderHelper.readGenbankDNASequence(workDir.resolve("seq.gb").toFile());
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

    // biojava-aa-prop: JAXB-based molecular-weight path.
    // Calls obtainAminoAcidCompositionTable (triggers JAXBContext + Unmarshaller) then
    // getMolecularWeightBasedOnXML.  The ~200-300 JAXB-runtime classes loaded here are
    // absent from every other workload, keeping cross-workload single.aot coverage low.
    static void aaProp(Path workDir) throws Exception {
        File elemMass = workDir.resolve("ElementMass.xml").toFile();
        File aaComp   = workDir.resolve("AminoAcidComposition.xml").toFile();
        AminoAcidCompositionTable table =
            PeptideProperties.obtainAminoAcidCompositionTable(elemMass, aaComp);
        double mw = PeptideProperties.getMolecularWeightBasedOnXML(
            "MTADGPRELLQLRAAVRHRGLLAELLRDR", table);
        double pi = PeptideProperties.getIsoelectricPoint("MTADGPRELLQLRAAVRHRGLLAELLRDR");
        if (mw <= 0 || pi <= 0) throw new IllegalStateException("bad aa-prop result");
    }

    // -------------------------------------------------------------------------

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
