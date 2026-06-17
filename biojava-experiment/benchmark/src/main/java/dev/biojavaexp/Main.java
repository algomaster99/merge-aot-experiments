package dev.biojavaexp;

import org.biojava.nbio.core.sequence.ProteinSequence;
import org.biojava.nbio.core.sequence.compound.AminoAcidCompound;
import org.biojava.nbio.core.sequence.io.FastaWriterHelper;
import org.biojava.nbio.core.sequence.io.GenbankReaderHelper;
import org.biojava.nbio.core.sequence.io.GenbankWriterHelper;
import org.biojava.nbio.core.util.ConcurrencyTools;
import org.biojava.nbio.alignment.Alignments;

import org.biojava.nbio.aaproperties.PeptideProperties;
import org.biojava.nbio.aaproperties.xml.AminoAcidCompositionTable;

import org.biojava.nbio.structure.Atom;
import org.biojava.nbio.structure.Chain;
import org.biojava.nbio.structure.Group;
import org.biojava.nbio.structure.Structure;
import org.biojava.nbio.structure.io.PDBFileParser;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
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
 *   biojava-alignment/msa       — msa (GuideTree, profile–profile)
 *   biojava-aa-prop/jaxb        — aa-prop (JAXB XML unmarshal → molecular weight)
 *   biojava-structure/pdb       — pdb-parse (PDBFileParser → 3D atom coordinates)
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
            case "msa"            -> msa();
            case "aa-prop"        -> aaProp(workDir);
            case "pdb-parse"      -> pdbParse();
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
        System.out.println("=== FASTA output ===");
        System.out.println(fastaOut);
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
        System.out.println("=== MSA output ===");
        System.out.println(profile);
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
        System.out.printf("=== aa-prop ===%nmolecular weight: %.2f Da%nisoelectric point: pH %.2f%n", mw, pi);
    }

    // biojava-structure: PDB file parsing — loads Structure, Chain, Group, Atom and the
    // entire 3D-coordinate infrastructure. Completely disjoint from sequence-analysis and
    // aa-prop class trees, giving low cross-workload single.aot coverage and a tree.aot win.
    // Input is an AlphaFold-predicted 4-residue fragment (MET-ARG-LYS-GLN) embedded as a
    // string constant so no network access or external file is required.
    static void pdbParse() throws Exception {
        PDBFileParser parser = new PDBFileParser();
        Structure structure = parser.parsePDBFile(
            new ByteArrayInputStream(PDB.getBytes(StandardCharsets.UTF_8)));
        Chain chain = structure.getChain("A");
        List<Group> groups = chain.getAtomGroups();
        if (groups.isEmpty()) throw new IllegalStateException("no residues parsed");
        System.out.println("=== PDB parse ===");
        System.out.println("Title: " + structure.getPDBHeader().getTitle().trim());
        System.out.printf("Chain A: %d residues, %d atoms%n",
            groups.size(), groups.stream().mapToInt(g -> g.getAtoms().size()).sum());
        for (Group g : groups) {
            Atom ca = g.getAtom("CA");
            System.out.printf("  %-3s %d  CA=(%.2f, %.2f, %.2f)%n",
                g.getPDBName(), g.getResidueNumber().getSeqNum(),
                ca.getX(), ca.getY(), ca.getZ());
        }
    }

    // -------------------------------------------------------------------------

    // AlphaFold-predicted 4-residue fragment (MET-ARG-LYS-GLN) from Danio rerio IL-1,
    // truncated from biojava-structure test resources (AF-A0A0R4IYF1-F1-model_v2.pdb).
    static final String PDB = """
        HEADER                                            01-JUL-21
        TITLE     ALPHAFOLD MONOMER V2.0 PREDICTION FOR INTERLEUKIN-1 (A0A0R4IYF1)
        COMPND    MOL_ID: 1;
        COMPND   2 MOLECULE: INTERLEUKIN-1;
        COMPND   3 CHAIN: A
        SEQRES   1 A  4  MET ARG LYS GLN
        CRYST1    1.000    1.000    1.000  90.00  90.00  90.00 P 1           1
        MODEL        1
        ATOM      1  N   MET A   1      19.682  12.062  34.184  1.00 39.14           N\s
        ATOM      2  CA  MET A   1      20.443  10.838  34.522  1.00 39.14           C\s
        ATOM      3  C   MET A   1      20.073   9.731  33.538  1.00 39.14           C\s
        ATOM      4  CB  MET A   1      20.138  10.405  35.966  1.00 39.14           C\s
        ATOM      5  O   MET A   1      19.030   9.110  33.696  1.00 39.14           O\s
        ATOM      6  CG  MET A   1      20.829  11.294  37.004  1.00 39.14           C\s
        ATOM      7  SD  MET A   1      20.292  10.920  38.687  1.00 39.14           S\s
        ATOM      8  CE  MET A   1      21.522  11.848  39.645  1.00 39.14           C\s
        ATOM      9  N   ARG A   2      20.850   9.531  32.464  1.00 38.04           N\s
        ATOM     10  CA  ARG A   2      20.614   8.428  31.516  1.00 38.04           C\s
        ATOM     11  C   ARG A   2      21.360   7.192  32.016  1.00 38.04           C\s
        ATOM     12  CB  ARG A   2      21.010   8.815  30.077  1.00 38.04           C\s
        ATOM     13  O   ARG A   2      22.578   7.197  32.112  1.00 38.04           O\s
        ATOM     14  CG  ARG A   2      19.854   9.506  29.332  1.00 38.04           C\s
        ATOM     15  CD  ARG A   2      20.250   9.851  27.888  1.00 38.04           C\s
        ATOM     16  NE  ARG A   2      19.107  10.368  27.105  1.00 38.04           N\s
        ATOM     17  NH1 ARG A   2      20.285  11.015  25.235  1.00 38.04           N\s
        ATOM     18  NH2 ARG A   2      18.073  11.268  25.278  1.00 38.04           N\s
        ATOM     19  CZ  ARG A   2      19.161  10.879  25.883  1.00 38.04           C\s
        ATOM     20  N   LYS A   3      20.589   6.174  32.391  1.00 33.68           N\s
        ATOM     21  CA  LYS A   3      21.032   4.888  32.935  1.00 33.68           C\s
        ATOM     22  C   LYS A   3      21.760   4.115  31.825  1.00 33.68           C\s
        ATOM     23  CB  LYS A   3      19.758   4.189  33.472  1.00 33.68           C\s
        ATOM     24  O   LYS A   3      21.111   3.629  30.901  1.00 33.68           O\s
        ATOM     25  CG  LYS A   3      19.960   3.207  34.636  1.00 33.68           C\s
        ATOM     26  CD  LYS A   3      18.588   2.749  35.176  1.00 33.68           C\s
        ATOM     27  CE  LYS A   3      18.733   1.906  36.451  1.00 33.68           C\s
        ATOM     28  NZ  LYS A   3      17.418   1.494  37.015  1.00 33.68           N\s
        ATOM     29  N   GLN A   4      23.091   4.048  31.878  1.00 37.59           N\s
        ATOM     30  CA  GLN A   4      23.877   3.144  31.035  1.00 37.59           C\s
        ATOM     31  C   GLN A   4      23.517   1.704  31.419  1.00 37.59           C\s
        ATOM     32  CB  GLN A   4      25.384   3.446  31.184  1.00 37.59           C\s
        ATOM     33  O   GLN A   4      23.656   1.303  32.573  1.00 37.59           O\s
        ATOM     34  CG  GLN A   4      25.896   4.332  30.030  1.00 37.59           C\s
        ATOM     35  CD  GLN A   4      27.116   5.178  30.386  1.00 37.59           C\s
        ATOM     36  NE2 GLN A   4      28.052   5.368  29.481  1.00 37.59           N\s
        ATOM     37  OE1 GLN A   4      27.214   5.742  31.460  1.00 37.59           O\s
        ENDMDL
        END
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
